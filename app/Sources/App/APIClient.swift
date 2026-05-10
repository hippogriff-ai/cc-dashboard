import Foundation

// MARK: - Codable types

/// Mirrors backend `Event` union (see `backend/src/types.ts`).
enum SessionEvent: String, Codable {
    case permissionPending = "PERMISSION_PENDING"
    case toolFailed = "TOOL_FAILED"
    case ask = "ASK"
    case working = "WORKING"
    case idleAfterComplete = "IDLE_AFTER_COMPLETE"
    case clear = "CLEAR"
}

struct OpenTool: Codable, Hashable {
    let name: String
    let id: String?
}

struct GitInfo: Codable {
    let branch: String?
    let dirty: Int
    let lastCommit: String?

    enum CodingKeys: String, CodingKey {
        case branch
        case dirty
        case lastCommit = "last_commit"
    }
}

struct LiveSession: Codable, Identifiable {
    // ClassifyResult fields (flattened by TS `extends`)
    let event: SessionEvent
    let reason: String
    let priority: Int
    let lastUser: String
    let lastAssistant: String
    let openTool: OpenTool?

    // LiveSession-specific fields
    let pid: Int
    let sessionId: String
    let cwd: String
    let repo: String
    let branch: String?
    let dirty: Int
    let startedAt: Int
    let lastActivity: Double      // ms epoch
    let ageSec: Int
    let staleDecay: Int
    let transcriptFound: Bool

    var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case event
        case reason
        case priority
        case lastUser = "last_user"
        case lastAssistant = "last_assistant"
        case openTool = "open_tool"
        case pid
        case sessionId
        case cwd
        case repo
        case branch
        case dirty
        case startedAt = "started_at"
        case lastActivity = "last_activity"
        case ageSec = "age_sec"
        case staleDecay = "stale_decay"
        case transcriptFound = "transcript_found"
    }
}

struct RecentRepo: Codable, Identifiable {
    // ClassifyResult fields
    let event: SessionEvent
    let reason: String
    let priority: Int
    let lastUser: String
    let lastAssistant: String
    let openTool: OpenTool?

    // RecentRepo-specific fields
    let cwd: String
    let repo: String
    let branch: String?
    let dirty: Int
    let lastCommit: String?
    let sessionId: String
    let lastActivity: Double

    var id: String { cwd }

    enum CodingKeys: String, CodingKey {
        case event
        case reason
        case priority
        case lastUser = "last_user"
        case lastAssistant = "last_assistant"
        case openTool = "open_tool"
        case cwd
        case repo
        case branch
        case dirty
        case lastCommit = "last_commit"
        case sessionId
        case lastActivity = "last_activity"
    }
}

struct PromptEntry: Codable {
    let display: String
    /// Millisecond epoch. The backend (`backend/src/claude/recent.ts`) emits
    /// this as a JSON Number (`1778243777955`). Decoding it as `String?`
    /// caused `/api/panel` to return a Codable error and the Restore detail
    /// pane to render "Couldn't load panel" — fixed Loop 39.
    let timestamp: Double?
}

struct Panel: Codable {
    let cwd: String
    let repo: String
    let sessionId: String?
    let transcriptFound: Bool
    let git: GitInfo
    let diffSummary: String?
    let recentPrompts: [PromptEntry]
    let lastUser: String
    let lastAssistant: String
    let event: SessionEvent
    let reason: String
    let openTool: OpenTool?

    enum CodingKeys: String, CodingKey {
        case cwd
        case repo
        case sessionId
        case transcriptFound = "transcript_found"
        case git
        case diffSummary = "diff_summary"
        case recentPrompts = "recent_prompts"
        case lastUser = "last_user"
        case lastAssistant = "last_assistant"
        case event
        case reason
        case openTool = "open_tool"
    }
}

struct FileTouch: Codable, Identifiable {
    let path: String
    let edits: Int
    let lastTouch: Double

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path
        case edits
        case lastTouch = "last_touch"
    }
}

struct Tokens: Codable {
    let input: Int
    let cachedRead: Int
    let cachedCreate: Int
    let output: Int
    let contextLimit: Int

    enum CodingKeys: String, CodingKey {
        case input
        case cachedRead = "cached_read"
        case cachedCreate = "cached_create"
        case output
        case contextLimit = "context_limit"
    }
}

struct DecisionPair: Codable, Identifiable {
    let q: String
    let a: String

    var id: String { q + a }
}

struct SessionDetail: Codable {
    let sessionId: String
    let cwd: String
    let repo: String
    let branch: String?
    let branchHistory: [String]
    let filesChanged: [FileTouch]
    let tokens: Tokens
    let loadHistory: [Int]    // tool_use count per minute, length 32
    let lastAssistant: String
    let openTool: OpenTool?
    let decisions: [DecisionPair]
    /// One of `"cc" | "opencode" | "pi" | "codex"`. Modelled as String so the Swift
    /// layer doesn't need updating when the backend registry grows.
    let source: String
    let ageSec: Int

    enum CodingKeys: String, CodingKey {
        case sessionId
        case cwd
        case repo
        case branch
        case branchHistory = "branch_history"
        case filesChanged = "files_changed"
        case tokens
        case loadHistory = "load_history"
        case lastAssistant = "last_assistant"
        case openTool = "open_tool"
        case decisions
        case source
        case ageSec = "age_sec"
    }
}

// MARK: - Response wrappers (server endpoint shapes)

struct LiveResponse: Codable {
    let sessions: [LiveSession]
    let ide: String
    let ts: Double
}

struct RecentResponse: Codable {
    let repos: [RecentRepo]
    let ide: String
    let ts: Double
}

struct DecisionsResponse: Codable {
    let decisions: [DecisionPair]
}

struct FocusResult: Codable {
    let ok: Bool
    let matched: Bool
    let reason: String?
    let detail: String?
    let windowIndex: Int?
    let matchedTitle: String?
    let score: Int?
    let margin: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case matched
        case reason
        case detail
        case windowIndex = "window_index"
        case matchedTitle = "matched_title"
        case score
        case margin
    }
}

struct ResumeResult: Codable {
    let command: String
    let copiedToClipboard: Bool

    enum CodingKeys: String, CodingKey {
        case command
        case copiedToClipboard = "copied_to_clipboard"
    }
}

struct ForkResult: Codable {
    let summary: String
    let copiedToClipboard: Bool

    enum CodingKeys: String, CodingKey {
        case summary
        case copiedToClipboard = "copied_to_clipboard"
    }
}

struct OpenIdeResult: Codable {
    let ok: Bool
    let ide: String?
    let error: String?
    let detail: String?
}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case http(status: Int, body: String)
    case decodeFailed(underlying: Error)
    case encodeFailed(underlying: Error)
    case nonHTTPResponse
    case malformedURL

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "HTTP \(status): \(body)"
        case .decodeFailed(let err):
            return "JSON decode failed: \(err.localizedDescription)"
        case .encodeFailed(let err):
            return "JSON encode failed: \(err.localizedDescription)"
        case .nonHTTPResponse:
            return "Backend returned a non-HTTP response"
        case .malformedURL:
            return "Could not construct backend URL"
        }
    }
}

// MARK: - Client

/// Thread-safe HTTP client for the bundled TypeScript sidecar. Actor-isolated so
/// `URLSession` requests don't race with concurrent callers.
actor APIClient {
    private let port: Int
    private let session: URLSession

    init(port: Int) {
        self.port = port
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        // Loop 25 smoke testing surfaced that URLSession.ephemeral with
        // default `waitsForConnectivity = true` silently hangs on 127.0.0.1
        // requests under hardened-runtime + LSUIElement apps. Setting to
        // false makes localhost connections fail-fast on transport errors
        // instead of being silently held in a "waiting for connectivity"
        // state. Localhost is always reachable; we don't want the
        // reachability monitor in this path.
        cfg.waitsForConnectivity = false
        // Disable HTTP/2 / connection pooling fanout that can interact poorly
        // with Bun.serve under high request rate from the 2s/4s polling cadence.
        cfg.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: cfg)
    }

    private func makeURL(path: String, query: [String: String]) throws -> URL {
        var c = URLComponents()
        c.scheme = "http"
        c.host = "127.0.0.1"
        c.port = port
        c.path = path
        if !query.isEmpty {
            // Use percentEncodedQueryItems with an explicit allowed-character set so
            // that `+` (and other reserved chars) get percent-encoded. URLComponents'
            // default queryItems setter does NOT encode `+`, which the backend would
            // then decode as a space — silently corrupting paths like `/Users/a+b/c`.
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))
            c.percentEncodedQueryItems = query.map { (k, v) in
                URLQueryItem(
                    name: k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k,
                    value: v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
                )
            }
        }
        guard let url = c.url else { throw APIError.malformedURL }
        return url
    }

    private func cwdSid(_ cwd: String, _ sid: String?) -> [String: String] {
        var d = ["cwd": cwd]
        if let sid { d["sid"] = sid }
        return d
    }

    /// Per-request timeout overrides. Polls (`/api/health`, `/api/live`,
    /// `/api/recent`) need a tight 5s window so a hung backend surfaces fast.
    /// Action endpoints that shell to other apps (resume, fork, open-ide)
    /// need longer or they'll time out before the action completes; 30s is
    /// conservative against the observed tail. (`/api/focus` was previously
    /// in this list but was moved into the Swift app process — see
    /// `GhosttyFocus.swift` — so it's no longer an HTTP path.)
    private static func timeout(for path: String) -> TimeInterval {
        switch path {
        case "/api/resume", "/api/fork", "/api/open-ide":
            return 30
        default:
            return 5
        }
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let url = try makeURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.timeoutInterval = Self.timeout(for: path)
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)
        return try decode(data: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = try makeURL(path: path, query: [:])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.timeout(for: path)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw APIError.encodeFailed(underlying: error)
        }
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)
        return try decode(data: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.nonHTTPResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let preview = data.prefix(4096)
            var bodyStr = String(data: preview, encoding: .utf8)
                ?? "<non-utf8, \(data.count) bytes>"
            if data.count > 4096 {
                bodyStr += "…[truncated, total=\(data.count)]"
            }
            throw APIError.http(status: http.statusCode, body: bodyStr)
        }
    }

    private func decode<T: Decodable>(data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodeFailed(underlying: error)
        }
    }

    func live() async throws -> LiveResponse {
        try await get("/api/live")
    }

    func recent(days: Int = 14) async throws -> RecentResponse {
        try await get("/api/recent", query: ["days": String(days)])
    }

    func panel(cwd: String, sid: String?) async throws -> Panel {
        try await get("/api/panel", query: cwdSid(cwd, sid))
    }

    func sessionDetail(sid: String) async throws -> SessionDetail {
        try await get("/api/session-detail", query: ["sid": sid])
    }

    func decisions(cwd: String) async throws -> DecisionsResponse {
        try await get("/api/decisions", query: ["cwd": cwd])
    }

    func resume(cwd: String, sid: String?) async throws -> ResumeResult {
        try await post("/api/resume", body: cwdSid(cwd, sid))
    }

    func fork(cwd: String, sid: String?) async throws -> ForkResult {
        try await post("/api/fork", body: cwdSid(cwd, sid))
    }

    func openIde(cwd: String) async throws -> OpenIdeResult {
        try await post("/api/open-ide", body: ["cwd": cwd])
    }
}
