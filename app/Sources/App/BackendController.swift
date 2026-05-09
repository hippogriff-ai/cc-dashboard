import Foundation
import os

private let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "BackendController")

/// Holds a weak reference to a class so it can be captured by-let into Sendable closures
/// without producing "captured var 'self' in concurrently-executing code" warnings.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// Spawns and supervises the bundled `cc-dashboard-backend` sidecar.
///
/// Stdout contract (set by the TypeScript sidecar in `backend/src/server.ts`): the
/// first line on stdout is exactly `{"port":<int>}\n`; the controller never expects
/// further structured stdout. Backend logs go to stderr — the controller drains
/// stderr and forwards it to `os.Logger` at warn level so failures are never silent.
@MainActor
final class BackendController: ObservableObject {
    enum State {
        case idle
        case starting
        case ready(port: Int)
        case failed(reason: String)
    }

    @Published private(set) var state: State = .idle

    private var process: Process?
    private var respawnAttempts = 0
    private let maxRespawn = 2
    private let portReadTimeoutSeconds: TimeInterval = 5.0
    private var isStopping = false
    private var lastTerminationStatus: Int32?
    private var lastTerminationReason: Process.TerminationReason?

    func start() {
        guard case .idle = state else { return }
        isStopping = false
        state = .starting
        spawnAndWait()
    }

    private func spawnAndWait() {
        guard let url = Bundle.main.url(
            forResource: "cc-dashboard-backend",
            withExtension: nil,
            subdirectory: "backend"
        ) else {
            logger.error("backend binary not found in bundle")
            state = .failed(reason: "Backend binary missing from app bundle")
            return
        }

        let p = Process()
        p.executableURL = url
        p.arguments = ["--port", "0"]

        // Parent-death detection: assign a Pipe to the child's stdin and never
        // write to it. We hold the write-end alive for the lifetime of this
        // process; when we die by any cause — graceful Cmd-Q, SIGKILL, force
        // quit, OOM, crash, debugger detach — the kernel closes our FDs and
        // the child's stdin gets EOF. The backend detects that in its stdin
        // 'end'/'close' handler and self-terminates immediately. This is more
        // reliable than the ppid-change poll watchdog the backend keeps as a
        // fallback: kernel-level signal, no polling, no 2s window during
        // which an orphaned sidecar can keep watching JSONLs and burn CPU.
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        do {
            try p.run()
        } catch {
            logger.error("backend spawn failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(reason: "Spawn failed: \(error.localizedDescription)")
            return
        }
        process = p

        // ---- stderr drain ----
        // Run for the lifetime of the child, not until the first empty read
        // (`availableData` returns empty during transient pauses, not only at EOF).
        // Polls `isRunning`; once the child exits, we do one final flush.
        let stderrProcess = p
        Task.detached {
            let handle = errPipe.fileHandleForReading
            var buffer = Data()
            while stderrProcess.isRunning {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    if Task.isCancelled { break }
                    do {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    } catch {
                        break
                    }
                    continue
                }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0a) {
                    let lineData = buffer.subdata(in: 0..<nl)
                    buffer.removeSubrange(0...nl)
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        logger.warning("backend stderr: \(line, privacy: .public)")
                    }
                }
            }
            // Final flush after the child exits.
            let tail = handle.availableData
            if !tail.isEmpty { buffer.append(tail) }
            while let nl = buffer.firstIndex(of: 0x0a) {
                let lineData = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    logger.warning("backend stderr: \(line, privacy: .public)")
                }
            }
            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
                logger.warning("backend stderr: \(line, privacy: .public)")
            }
        }

        // ---- stdout: read port announcement (with timeout), then continue draining ----
        let timeoutSeconds = portReadTimeoutSeconds
        let weakProcess = p
        let weakSelf = WeakBox(self)
        Task.detached {
            let handle = outPipe.fileHandleForReading
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            var buf = Data()
            var timedOut = false

            while !buf.contains(0x0a) {
                if Date() >= deadline {
                    timedOut = true
                    break
                }
                let chunk = handle.availableData
                if chunk.isEmpty {
                    if Task.isCancelled { return }
                    do {
                        try await Task.sleep(nanoseconds: 50_000_000)
                    } catch {
                        return
                    }
                    continue
                }
                buf.append(chunk)
            }

            if timedOut {
                logger.error("backend port announcement timed out after \(timeoutSeconds, privacy: .public)s")
                // Clear handler BEFORE terminate so the resulting termination
                // does not trigger the respawn path (we are declaring a hard failure).
                weakProcess.terminationHandler = nil
                weakProcess.terminate()
                await MainActor.run {
                    weakSelf.value?.state = .failed(reason: "Backend did not announce port within \(Int(timeoutSeconds))s")
                }
                return
            }

            guard let nlIndex = buf.firstIndex(of: 0x0a),
                  let obj = try? JSONSerialization.jsonObject(with: buf.subdata(in: 0..<nlIndex)) as? [String: Any],
                  let port = obj["port"] as? Int else {
                logger.error("backend port announcement parse failed")
                weakProcess.terminationHandler = nil
                weakProcess.terminate()
                await MainActor.run {
                    weakSelf.value?.state = .failed(reason: "Failed to parse backend port announcement")
                }
                return
            }

            await MainActor.run {
                weakSelf.value?.state = .ready(port: port)
                weakSelf.value?.respawnAttempts = 0
            }
            logger.info("backend ready on port \(port, privacy: .public)")

            // Continue draining stdout for the remainder of the child's lifetime.
            // The backend should not write anything else here, but if it does we must
            // empty the pipe — otherwise the kernel buffer fills and the child blocks
            // on `write()`. Anything we receive is unexpected, so log at info level.
            var tailBuf = buf.subdata(in: (nlIndex + 1)..<buf.count)
            while weakProcess.isRunning {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    if Task.isCancelled { return }
                    do {
                        try await Task.sleep(nanoseconds: 200_000_000)
                    } catch {
                        return
                    }
                    continue
                }
                tailBuf.append(chunk)
                while let nl = tailBuf.firstIndex(of: 0x0a) {
                    let lineData = tailBuf.subdata(in: 0..<nl)
                    tailBuf.removeSubrange(0...nl)
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        logger.info("backend stdout: \(line, privacy: .public)")
                    }
                }
            }
        }

        // ---- termination handler ----
        // Capture the actual exit status / reason so respawn / failure messages
        // are diagnosable rather than the opaque "Backend kept crashing".
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor in
                self?.handleTermination(status: status, reason: reason)
            }
        }
    }

    private func handleTermination(status: Int32, reason: Process.TerminationReason) {
        process = nil
        lastTerminationStatus = status
        lastTerminationReason = reason
        let reasonDesc: String
        switch reason {
        case .exit: reasonDesc = "exit"
        case .uncaughtSignal: reasonDesc = "uncaughtSignal"
        @unknown default: reasonDesc = "unknown"
        }

        if isStopping {
            logger.info("backend terminated as part of intentional shutdown (status=\(status, privacy: .public), reason=\(reasonDesc, privacy: .public))")
            return
        }

        respawnAttempts += 1
        if respawnAttempts <= maxRespawn {
            logger.warning("backend exited (status=\(status, privacy: .public), reason=\(reasonDesc, privacy: .public)); respawning (attempt \(self.respawnAttempts, privacy: .public))")
            state = .idle
            start()
        } else {
            logger.error("backend exited too many times; giving up (last status=\(status, privacy: .public), reason=\(reasonDesc, privacy: .public))")
            state = .failed(reason: "Backend exited \(respawnAttempts) times; last status=\(status), reason=\(reasonDesc)")
        }
    }

    func stop() {
        isStopping = true
        guard let p = process else { return }
        // Clear the termination handler BEFORE terminating so an intentional
        // shutdown does not trigger respawn.
        p.terminationHandler = nil
        p.terminate()
        process = nil
    }
}
