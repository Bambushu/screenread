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
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict }
        else { value = "" }
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
          let str = String(data: data, encoding: .utf8) else { return }
    print(str)
    fflush(stdout)
}

// MARK: - Tool Definitions

let tools: [[String: Any]] = [
    [
        "name": "screenread_snapshot",
        "description": "Read the accessibility tree of a macOS window or application. Returns structured text representation of all UI elements.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "app": ["type": "string", "description": "App name to read (e.g. 'Safari')"],
                "window": ["type": "string", "description": "Fuzzy match on window title"],
                "pid": ["type": "integer", "description": "Target by process ID"],
                "depth": ["type": "integer", "description": "Max tree depth (default: 5, 0 = unlimited)"],
                "textOnly": ["type": "boolean", "description": "Return only readable text, no structure"],
                "roles": ["type": "string", "description": "Comma-separated roles to include"],
                "ignore": ["type": "string", "description": "Comma-separated roles to exclude"],
            ] as [String: Any],
        ] as [String: Any],
    ],
    [
        "name": "screenread_list",
        "description": "List all open windows on macOS with their app name, title, and PID.",
        "inputSchema": [
            "type": "object",
            "additionalProperties": false,
        ] as [String: Any],
    ],
    [
        "name": "screenread_find_text",
        "description": "Search for visible text across all open windows. Returns matches with window context.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Text to search for"],
                "caseSensitive": ["type": "boolean", "description": "Case-sensitive search (default: false)"],
            ] as [String: Any],
            "required": ["query"],
        ] as [String: Any],
    ],
]

// MARK: - Tool Execution

func executeSnapshot(_ params: [String: AnyCodable]?) -> String {
    let resolver = TargetResolver()

    do {
        let target: AXUIElement
        if let pid = params?["pid"]?.intValue {
            target = try resolver.resolvePID(Int32(pid))
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
        guard let tree = walker.walk(target) else {
            return "Window found but accessibility tree is empty."
        }

        return textOnly ? Formatter.formatTextOnly(tree) : Formatter.formatTextTree(tree)
    } catch {
        return "Error: \(error)"
    }
}

func executeList() -> String {
    let resolver = TargetResolver()
    let windows = resolver.listWindows()
    return windows.map { "\($0.app) [\($0.pid)] — \($0.title)" }.joined(separator: "\n")
}

func executeFindText(_ params: [String: AnyCodable]?) -> String {
    guard let query = params?["query"]?.stringValue else {
        return "Error: 'query' parameter is required"
    }
    let caseSensitive = params?["caseSensitive"]?.boolValue ?? false
    let resolver = TargetResolver()
    let walker = AXTreeWalker(maxDepth: 0, includeRoles: nil, excludeRoles: nil, truncateAt: 0)
    var results: [String] = []

    for app in resolver.listWindows() {
        do {
            let element = try resolver.resolvePID(app.pid)
            guard let tree = walker.walk(element) else { continue }
            let text = Formatter.formatTextOnly(tree)
            let lines = text.components(separatedBy: "\n")
            for line in lines {
                let matches = caseSensitive
                    ? line.contains(query)
                    : line.lowercased().contains(query.lowercased())
                if matches {
                    results.append("[\(app.app) — \(app.title)] \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        } catch {
            continue
        }
    }

    return results.isEmpty ? "No matches found for '\(query)'" : results.joined(separator: "\n")
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
            "serverInfo": ["name": "screenread", "version": "0.1.0"],
        ] as [String: Any])

    case "notifications/initialized":
        break // no response

    case "tools/list":
        sendResponse(request.id, ["tools": tools])

    case "tools/call":
        let toolName = (request.params?["name"]?.stringValue) ?? ""
        let args = request.params?["arguments"]
        let argsDict: [String: AnyCodable]?
        if let argValue = args?.value as? [String: AnyCodable] {
            argsDict = argValue
        } else {
            argsDict = nil
        }

        switch toolName {
        case "screenread_snapshot":
            sendToolResult(request.id, text: executeSnapshot(argsDict))
        case "screenread_list":
            sendToolResult(request.id, text: executeList())
        case "screenread_find_text":
            sendToolResult(request.id, text: executeFindText(argsDict))
        default:
            sendError(request.id, code: -32601, message: "Unknown tool: \(toolName)")
        }

    default:
        sendError(request.id, code: -32601, message: "Method not found: \(request.method)")
    }
}
