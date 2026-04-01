// Sources/screenread-mcp/main.swift
import Foundation
import ApplicationServices
import ScreenReadCore

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Decodable {
    let jsonrpc: String
    let id: AnyCodableID?
    let method: String
    let params: [String: AnyCodable]?
}

enum AnyCodableID: Decodable, Encodable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(AnyCodableID.self, .init(codingPath: [], debugDescription: "Expected int or string"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }
}

struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else {
            value = NSNull()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
}

// MARK: - Response Helpers

func sendResponse(_ id: AnyCodableID?, _ result: Any) {
    var response: [String: Any] = ["jsonrpc": "2.0"]
    if let id = id {
        switch id {
        case .int(let v): response["id"] = v
        case .string(let v): response["id"] = v
        }
    }
    response["result"] = result
    sendJSON(response)
}

func sendError(_ id: AnyCodableID?, code: Int, message: String) {
    var response: [String: Any] = ["jsonrpc": "2.0"]
    if let id = id {
        switch id {
        case .int(let v): response["id"] = v
        case .string(let v): response["id"] = v
        }
    }
    response["error"] = ["code": code, "message": message] as [String: Any]
    sendJSON(response)
}

func sendToolResult(_ id: AnyCodableID?, text: String, isError: Bool = false) {
    sendResponse(id, [
        "content": [["type": "text", "text": text]],
        "isError": isError,
    ] as [String: Any])
}

func sendJSON(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let str = String(data: data, encoding: .utf8) else {
        // Fallback: don't silently drop — send a minimal error so the client doesn't hang
        print("{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal serialization error\"}}")
        fflush(stdout)
        return
    }
    print(str)
    fflush(stdout)
}

// MARK: - Tool Definitions

let tools: [[String: Any]] = [
    [
        "name": "screenread_snapshot",
        "description": "Read the accessibility tree of a macOS window or application. With no parameters, reads the frontmost (active) app. Returns structured text of all UI elements.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "app": ["type": "string", "description": "App name to read (e.g. 'Safari')"],
                "window": ["type": "string", "description": "Fuzzy match on window title"],
                "pid": ["type": "integer", "description": "Target by process ID"],
                "depth": ["type": "integer", "description": "Max tree depth (default: 5). Use 0 for unlimited — may be slow on large apps."],
                "textOnly": ["type": "boolean", "description": "Return only readable text, no structure"],
                "roles": ["type": "string", "description": "Comma-separated AX roles to include (e.g. 'AXButton,AXLink,AXTextField')"],
                "ignore": ["type": "string", "description": "Comma-separated AX roles to exclude (e.g. 'AXGroup,AXScrollArea,AXUnknown')"],
            ] as [String: Any],
            "additionalProperties": false,
        ] as [String: Any],
    ],
    [
        "name": "screenread_list",
        "description": "List all open windows on macOS. Returns one line per window: 'AppName [PID] — Window Title'.",
        "inputSchema": [
            "type": "object",
            "additionalProperties": false,
        ] as [String: Any],
    ],
    [
        "name": "screenread_find_text",
        "description": "Search for visible text across all open windows. Plain text substring match (no regex). Returns matches with window context.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Plain text substring to search for (no regex). Case-insensitive by default."],
                "caseSensitive": ["type": "boolean", "description": "Case-sensitive search (default: false)"],
            ] as [String: Any],
            "required": ["query"],
            "additionalProperties": false,
        ] as [String: Any],
    ],
    [
        "name": "screenread_clickable",
        "description": "List interactive elements (buttons, links, text fields) with their click coordinates. Returns a table with role, label, center x/y, and state.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "app": ["type": "string", "description": "App name to read (e.g. 'Safari')"],
                "window": ["type": "string", "description": "Fuzzy match on window title"],
                "pid": ["type": "integer", "description": "Target by process ID"],
                "roles": ["type": "string", "description": "Override default interactive roles (e.g. 'AXButton,AXLink')"],
            ] as [String: Any],
            "additionalProperties": false,
        ] as [String: Any],
    ],
    [
        "name": "screenread_watch",
        "description": "Watch an app for UI changes over a duration. Polls the accessibility tree at an interval and reports additions, removals, and value/state changes.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "app": ["type": "string", "description": "App name to watch (e.g. 'Safari')"],
                "window": ["type": "string", "description": "Fuzzy match on window title"],
                "pid": ["type": "integer", "description": "Target by process ID"],
                "duration": ["type": "integer", "description": "How long to watch in seconds (default: 10, max: 60)"],
                "interval": ["type": "integer", "description": "Poll interval in seconds (default: 2, min: 1)"],
                "textOnly": ["type": "boolean", "description": "Compare text content only (default: false)"],
            ] as [String: Any],
            "additionalProperties": false,
        ] as [String: Any],
    ],
]

// MARK: - Tool Execution

struct ToolResult {
    let text: String
    let isError: Bool
}

func executeSnapshot(_ params: [String: AnyCodable]?) -> ToolResult {
    let resolver = TargetResolver()

    do {
        let target: AXUIElement
        if let pid = params?["pid"]?.intValue {
            guard let pid32 = Int32(exactly: pid) else {
                return ToolResult(text: "Invalid PID: \(pid)", isError: true)
            }
            target = try resolver.resolvePID(pid32)
        } else if let windowTitle = params?["window"]?.stringValue {
            target = try resolver.resolveWindow(windowTitle)
        } else if let appName = params?["app"]?.stringValue {
            target = try resolver.resolveApp(appName)
        } else {
            target = try resolver.resolveFrontmost()
        }

        let depth = params?["depth"]?.intValue ?? 5
        let textOnly = params?["textOnly"]?.boolValue ?? false
        let includeRoles: Set<String>? = params?["roles"]?.stringValue.map { Set($0.split(separator: ",").map(String.init)) }
        let excludeRoles: Set<String>? = params?["ignore"]?.stringValue.map { Set($0.split(separator: ",").map(String.init)) }

        let walker = AXTreeWalker(maxDepth: depth, includeRoles: includeRoles, excludeRoles: excludeRoles, truncateAt: 500)
        let result = walker.walk(target)

        switch result {
        case .tree(let tree):
            let output = textOnly ? Formatter.formatTextOnly(tree) : Formatter.formatTextTree(tree)
            return ToolResult(text: output, isError: false)
        case .timedOut:
            return ToolResult(text: "Timed out reading accessibility tree. Try a smaller depth or target a specific window.", isError: true)
        case .empty:
            return ToolResult(text: "Accessibility tree is empty. The app may not support accessibility or may need a moment to load.", isError: true)
        }
    } catch {
        return ToolResult(text: "Error: \(error)", isError: true)
    }
}

func executeList() -> ToolResult {
    let resolver = TargetResolver()
    do {
        let windows = try resolver.listWindows()
        return ToolResult(text: Formatter.formatWindowList(windows), isError: false)
    } catch {
        return ToolResult(text: "Error: \(error)", isError: true)
    }
}

func executeFindText(_ params: [String: AnyCodable]?) -> ToolResult {
    guard let query = params?["query"]?.stringValue, !query.isEmpty else {
        return ToolResult(text: "Error: 'query' parameter is required and must not be empty", isError: true)
    }
    let caseSensitive = params?["caseSensitive"]?.boolValue ?? false
    let queryLower = caseSensitive ? query : query.lowercased()
    let resolver = TargetResolver()
    var results: [String] = []
    let maxResults = 100
    var skippedApps: [String] = []

    // Deduplicate: same PID may appear multiple times (one per window)
    var seenPIDs = Set<Int32>()

    for app in (try? resolver.listWindows()) ?? [] {
        if results.count >= maxResults { break }
        guard seenPIDs.insert(app.pid).inserted else { continue }

        do {
            let element = try resolver.resolvePID(app.pid)
            // Fresh walker per app — each gets its own 3-second timeout budget
            let walker = AXTreeWalker(maxDepth: 10, includeRoles: nil, excludeRoles: nil, truncateAt: 500, timeoutSeconds: 3.0)
            let walkResult = walker.walk(element)

            let tree: AXNode
            switch walkResult {
            case .tree(let node): tree = node
            case .timedOut:
                skippedApps.append("\(app.app) (timed out)")
                continue
            case .empty: continue
            }

            let text = Formatter.formatTextOnly(tree)
            let lines = text.components(separatedBy: "\n")
            for line in lines {
                let matches = caseSensitive
                    ? line.contains(query)
                    : line.lowercased().contains(queryLower)
                if matches {
                    results.append("[\(app.app) — \(app.title)] \(line.trimmingCharacters(in: .whitespaces))")
                    if results.count >= maxResults { break }
                }
            }
        } catch {
            skippedApps.append("\(app.app) (error)")
            continue
        }
    }

    var output: String
    if results.isEmpty {
        output = "No matches found for '\(query)'"
    } else {
        output = results.joined(separator: "\n")
        if results.count >= maxResults {
            output += "\n(limited to \(maxResults) results — use screenread_snapshot with a specific app for more targeted results)"
        }
    }
    if !skippedApps.isEmpty {
        output += "\n(skipped \(skippedApps.count) app(s): \(skippedApps.joined(separator: ", ")))"
    }
    return ToolResult(text: output, isError: false)
}

func executeClickable(_ params: [String: AnyCodable]?) -> ToolResult {
    let resolver = TargetResolver()

    do {
        let target: AXUIElement
        if let pid = params?["pid"]?.intValue {
            guard let pid32 = Int32(exactly: pid) else {
                return ToolResult(text: "Invalid PID: \(pid)", isError: true)
            }
            target = try resolver.resolvePID(pid32)
        } else if let windowTitle = params?["window"]?.stringValue {
            target = try resolver.resolveWindow(windowTitle)
        } else if let appName = params?["app"]?.stringValue {
            target = try resolver.resolveApp(appName)
        } else {
            target = try resolver.resolveFrontmost()
        }

        let roles: Set<String>? = params?["roles"]?.stringValue.map { Set($0.split(separator: ",").map(String.init)) }

        let walker = AXTreeWalker(maxDepth: 5, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
        let result = walker.walk(target)

        switch result {
        case .tree(let tree):
            let output = Formatter.formatClickable(tree, roles: roles)
            return ToolResult(text: output, isError: false)
        case .timedOut:
            return ToolResult(text: "Timed out reading accessibility tree. Try a smaller depth or target a specific window.", isError: true)
        case .empty:
            return ToolResult(text: "Accessibility tree is empty. The app may not support accessibility or may need a moment to load.", isError: true)
        }
    } catch {
        return ToolResult(text: "Error: \(error)", isError: true)
    }
}

func executeWatch(_ params: [String: AnyCodable]?) -> ToolResult {
    let resolver = TargetResolver()

    let duration = min(params?["duration"]?.intValue ?? 10, 60)
    let interval = max(params?["interval"]?.intValue ?? 2, 1)
    let textOnly = params?["textOnly"]?.boolValue ?? false

    let target: AXUIElement
    var appName: String
    do {
        if let pid = params?["pid"]?.intValue {
            guard let pid32 = Int32(exactly: pid) else {
                return ToolResult(text: "Invalid PID: \(pid)", isError: true)
            }
            target = try resolver.resolvePID(pid32)
            appName = "PID \(pid)"
        } else if let windowTitle = params?["window"]?.stringValue {
            target = try resolver.resolveWindow(windowTitle)
            appName = windowTitle
        } else if let name = params?["app"]?.stringValue {
            target = try resolver.resolveApp(name)
            appName = name
        } else {
            target = try resolver.resolveFrontmost()
            appName = "frontmost app"
        }
    } catch {
        return ToolResult(text: "Error: \(error)", isError: true)
    }

    // Walk baseline tree
    let baseWalker = AXTreeWalker(maxDepth: 5, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
    let baseResult = baseWalker.walk(target)
    var baseline: AXNode
    switch baseResult {
    case .tree(let tree):
        baseline = tree
    case .timedOut:
        return ToolResult(text: "Timed out reading initial accessibility tree for \(appName).", isError: true)
    case .empty:
        return ToolResult(text: "Accessibility tree is empty for \(appName).", isError: true)
    }

    // Poll loop
    var allChanges: [(Int, [TreeChange])] = []
    var polls = 0
    var elapsed = 0

    while elapsed < duration {
        Thread.sleep(forTimeInterval: Double(interval))
        elapsed += interval
        polls += 1

        let walker = AXTreeWalker(maxDepth: 5, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
        let walkResult = walker.walk(target)

        let currentTree: AXNode
        switch walkResult {
        case .tree(let tree): currentTree = tree
        case .timedOut, .empty: continue
        }

        var changes = TreeDiffer.diff(old: baseline, new: currentTree)

        if textOnly {
            changes = changes.filter {
                switch $0 {
                case .changed(_, _, _, let field): return field == "title" || field == "value"
                default: return true
                }
            }
        }

        if !changes.isEmpty {
            allChanges.append((elapsed, changes))
        }

        baseline = currentTree
    }

    let totalChanges = allChanges.reduce(0) { $0 + $1.1.count }

    if allChanges.isEmpty {
        return ToolResult(text: "No changes detected in \(appName) over \(duration)s (\(polls) polls)", isError: false)
    }

    var lines: [String] = ["Watched \(appName) for \(duration)s (\(polls) polls, \(totalChanges) changes)"]
    for (ts, changes) in allChanges {
        lines.append("")
        lines.append("t=\(ts)s:")
        for change in changes {
            lines.append("  \(change.formatted)")
        }
    }
    return ToolResult(text: lines.joined(separator: "\n"), isError: false)
}

// MARK: - Main Loop

while let line = readLine() {
    guard let data = line.data(using: .utf8) else { continue }
    guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
        sendError(nil, code: -32700, message: "Parse error")
        continue
    }

    switch request.method {
    case "initialize":
        sendResponse(request.id, [
            "protocolVersion": "2025-11-25",
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "screenread", "version": "0.2.0"],
        ] as [String: Any])

    case "notifications/initialized":
        break // no response

    case "tools/list":
        sendResponse(request.id, ["tools": tools])

    case "tools/call":
        let toolName = (request.params?["name"]?.stringValue) ?? ""
        let argsDict: [String: AnyCodable]? = {
            guard let args = request.params?["arguments"] else { return nil }
            if let typed = args.value as? [String: AnyCodable] { return typed }
            // Fallback: re-decode from raw dict (handles [String: Any] case)
            if let raw = args.value as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {
                return decoded
            }
            return nil
        }()

        switch toolName {
        case "screenread_snapshot":
            let result = executeSnapshot(argsDict)
            sendToolResult(request.id, text: result.text, isError: result.isError)
        case "screenread_list":
            let result = executeList()
            sendToolResult(request.id, text: result.text, isError: result.isError)
        case "screenread_find_text":
            let result = executeFindText(argsDict)
            sendToolResult(request.id, text: result.text, isError: result.isError)
        case "screenread_clickable":
            let result = executeClickable(argsDict)
            sendToolResult(request.id, text: result.text, isError: result.isError)
        case "screenread_watch":
            let result = executeWatch(argsDict)
            sendToolResult(request.id, text: result.text, isError: result.isError)
        default:
            sendError(request.id, code: -32601, message: "Unknown tool: \(toolName)")
        }

    default:
        sendError(request.id, code: -32601, message: "Method not found: \(request.method)")
    }
}
