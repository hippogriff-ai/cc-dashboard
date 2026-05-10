import XCTest
@testable import cc_dashboard

@MainActor
final class PopoverViewModelTests: XCTestCase {
    // Verifies showError populates `lastError` synchronously with the given message.
    func testShowErrorSetsLastError() {
        let vm = PopoverViewModel()
        vm.showError("X")
        XCTAssertEqual(vm.lastError?.message, "X")
        XCTAssertEqual(vm.lastError?.kind, .error)
    }

    // Verifies the auto-dismiss timer clears `lastError` after the configured interval.
    func testShowErrorAutoDismissesAfterTimeout() async {
        let vm = PopoverViewModel()
        vm.showError("X", after: 0.05)
        XCTAssertNotNil(vm.lastError)
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        XCTAssertNil(vm.lastError)
    }

    // Verifies a second showError replaces the first while the prior timer is still pending.
    func testShowErrorOverridesPrevious() {
        let vm = PopoverViewModel()
        vm.showError("A", after: 1)
        vm.showError("B", after: 1)
        XCTAssertEqual(vm.lastError?.message, "B")
    }

    // Verifies overriding cancels the prior timer so B's longer interval governs the dismissal.
    func testShowErrorOverrideResetsTimer() async {
        let vm = PopoverViewModel()
        vm.showError("A", after: 0.05)
        vm.showError("B", after: 1)
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s — past A's 0.05s but well inside B's 1s.
        XCTAssertEqual(vm.lastError?.message, "B")
    }

    // Verifies dismissError clears state synchronously and cancels the pending timer.
    func testDismissErrorCancelsTimer() {
        let vm = PopoverViewModel()
        vm.showError("X", after: 0.05)
        vm.dismissError()
        XCTAssertNil(vm.lastError)
    }

    // Verifies after: 0 produces a persistent banner that does not auto-dismiss.
    func testShowErrorWithZeroIntervalIsPersistent() async {
        let vm = PopoverViewModel()
        vm.showError("Persistent", after: 0)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vm.lastError?.message, "Persistent")
    }

    // Verifies `kind` is preserved on the published PopoverError.
    func testShowErrorPreservesKind() {
        let vm = PopoverViewModel()
        vm.showError("Y", kind: .warning, after: 0)
        XCTAssertEqual(vm.lastError?.kind, .warning)
    }
}
