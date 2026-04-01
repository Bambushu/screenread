import Foundation

public struct JSONRPCRequest: Decodable, Equatable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let method: String
    public let params: [String: MCPValue]?

    public init(jsonrpc: String, id: JSONRPCID?, method: String, params: [String: MCPValue]?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

public enum JSONRPCID: Codable, Equatable, Sendable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCID.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected int or string")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

public indirect enum MCPValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([MCPValue])
    case object([String: MCPValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([MCPValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: MCPValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.typeMismatch(
                MCPValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var objectValue: [String: MCPValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

public struct JSONRPCError: Codable, Equatable, Error, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct JSONRPCResponse: Codable, Equatable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let result: MCPValue?
    public let error: JSONRPCError?

    public init(jsonrpc: String = "2.0", id: JSONRPCID?, result: MCPValue? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct MCPToolDefinition: Equatable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: [String: MCPValue]

    public init(name: String, description: String, inputSchema: [String: MCPValue]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public var jsonValue: MCPValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object(inputSchema),
        ])
    }
}

public enum ScreenReadMCPTool: String, CaseIterable, Sendable {
    case snapshot = "screenread_snapshot"
    case list = "screenread_list"
    case findText = "screenread_find_text"
    case clickable = "screenread_clickable"
    case watch = "screenread_watch"
}

public struct ScreenReadMCPToolCall: Equatable, Sendable {
    public let tool: ScreenReadMCPTool
    public let arguments: [String: MCPValue]

    public init(tool: ScreenReadMCPTool, arguments: [String: MCPValue]) {
        self.tool = tool
        self.arguments = arguments
    }
}

public enum ScreenReadMCPProtocol {
    public static let jsonrpcVersion = "2.0"
    public static let protocolVersion = "2025-11-25"

    public static let toolDefinitions: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: ScreenReadMCPTool.snapshot.rawValue,
            description: "Read the accessibility tree of a macOS window or application. With no parameters, reads the frontmost (active) app. Returns structured text of all UI elements.",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "app": .object(["type": .string("string"), "description": .string("App name to read (e.g. 'Safari')")]),
                    "window": .object(["type": .string("string"), "description": .string("Fuzzy match on window title")]),
                    "pid": .object(["type": .string("integer"), "description": .string("Target by process ID")]),
                    "depth": .object(["type": .string("integer"), "description": .string("Max tree depth (default: 5). Use 0 for unlimited - may be slow on large apps.")]),
                    "textOnly": .object(["type": .string("boolean"), "description": .string("Return only readable text, no structure")]),
                    "roles": .object(["type": .string("string"), "description": .string("Comma-separated AX roles to include (e.g. 'AXButton,AXLink,AXTextField')")]),
                    "ignore": .object(["type": .string("string"), "description": .string("Comma-separated AX roles to exclude (e.g. 'AXGroup,AXScrollArea,AXUnknown')")]),
                ]),
                "additionalProperties": .bool(false),
            ]
        ),
        MCPToolDefinition(
            name: ScreenReadMCPTool.list.rawValue,
            description: "List all open windows on macOS. Returns one line per window: 'AppName [PID] - Window Title'.",
            inputSchema: [
                "type": .string("object"),
                "additionalProperties": .bool(false),
            ]
        ),
        MCPToolDefinition(
            name: ScreenReadMCPTool.findText.rawValue,
            description: "Search for visible text across all open windows. Plain text substring match (no regex). Returns matches with window context.",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string"), "description": .string("Plain text substring to search for (no regex). Case-insensitive by default.")]),
                    "caseSensitive": .object(["type": .string("boolean"), "description": .string("Case-sensitive search (default: false)")]),
                ]),
                "required": .array([.string("query")]),
                "additionalProperties": .bool(false),
            ]
        ),
        MCPToolDefinition(
            name: ScreenReadMCPTool.clickable.rawValue,
            description: "List interactive elements (buttons, links, text fields) with their click coordinates. Returns a table with role, label, center x/y, and state.",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "app": .object(["type": .string("string"), "description": .string("App name to read (e.g. 'Safari')")]),
                    "window": .object(["type": .string("string"), "description": .string("Fuzzy match on window title")]),
                    "pid": .object(["type": .string("integer"), "description": .string("Target by process ID")]),
                    "roles": .object(["type": .string("string"), "description": .string("Override default interactive roles (e.g. 'AXButton,AXLink')")]),
                ]),
                "additionalProperties": .bool(false),
            ]
        ),
        MCPToolDefinition(
            name: ScreenReadMCPTool.watch.rawValue,
            description: "Watch an app for UI changes over a duration. Polls the accessibility tree at an interval and reports additions, removals, and value/state changes.",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "app": .object(["type": .string("string"), "description": .string("App name to watch (e.g. 'Safari')")]),
                    "window": .object(["type": .string("string"), "description": .string("Fuzzy match on window title")]),
                    "pid": .object(["type": .string("integer"), "description": .string("Target by process ID")]),
                    "duration": .object(["type": .string("integer"), "description": .string("How long to watch in seconds (default: 10, max: 60)")]),
                    "interval": .object(["type": .string("integer"), "description": .string("Poll interval in seconds (default: 2, min: 1)")]),
                    "textOnly": .object(["type": .string("boolean"), "description": .string("Compare text content only (default: false)")]),
                ]),
                "additionalProperties": .bool(false),
            ]
        ),
    ]

    public static func validateRequest(_ request: JSONRPCRequest) -> JSONRPCError? {
        guard request.jsonrpc == jsonrpcVersion else {
            return JSONRPCError(code: -32600, message: "Invalid Request: unsupported jsonrpc version '\(request.jsonrpc)'")
        }
        return nil
    }

    public static func decodeToolCall(from params: [String: MCPValue]?) -> Result<ScreenReadMCPToolCall, JSONRPCError> {
        guard let name = params?["name"]?.stringValue, !name.isEmpty else {
            return .failure(JSONRPCError(code: -32602, message: "Invalid params: 'name' must be a non-empty string"))
        }
        guard let tool = ScreenReadMCPTool(rawValue: name) else {
            return .failure(JSONRPCError(code: -32601, message: "Unknown tool: \(name)"))
        }

        let rawArguments: [String: MCPValue]
        if let arguments = params?["arguments"] {
            switch arguments {
            case .null:
                rawArguments = [:]
            case .object(let values):
                rawArguments = values
            default:
                return .failure(JSONRPCError(code: -32602, message: "Invalid params: 'arguments' must be an object when provided"))
            }
        } else {
            rawArguments = [:]
        }

        switch normalizeArguments(for: tool, arguments: rawArguments) {
        case .success(let normalizedArguments):
            return .success(ScreenReadMCPToolCall(tool: tool, arguments: normalizedArguments))
        case .failure(let error):
            return .failure(error)
        }
    }

    public static func makeSuccessResponse(id: JSONRPCID?, result: MCPValue) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: result, error: nil)
    }

    public static func makeErrorResponse(id: JSONRPCID?, code: Int, message: String) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: code, message: message))
    }

    public static func makeToolResult(text: String, isError: Bool) -> MCPValue {
        .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ]),
            ]),
            "isError": .bool(isError),
        ])
    }

    public static func encodeResponse(_ response: JSONRPCResponse) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(response),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal serialization error"}}"#
        }
        return string
    }

    private static func normalizeArguments(for tool: ScreenReadMCPTool, arguments: [String: MCPValue]) -> Result<[String: MCPValue], JSONRPCError> {
        switch tool {
        case .snapshot:
            return normalizeSnapshotArguments(arguments)
        case .list:
            return validateNoArguments(arguments, for: tool)
        case .findText:
            return normalizeFindTextArguments(arguments)
        case .clickable:
            return normalizeClickableArguments(arguments)
        case .watch:
            return normalizeWatchArguments(arguments)
        }
    }

    private static func normalizeSnapshotArguments(_ arguments: [String: MCPValue]) -> Result<[String: MCPValue], JSONRPCError> {
        let allowedKeys: Set<String> = ["app", "window", "pid", "depth", "textOnly", "roles", "ignore"]
        if let error = validateUnknownKeys(arguments, allowedKeys: allowedKeys) {
            return .failure(error)
        }

        var normalized: [String: MCPValue] = [:]
        if let app = requireStringIfPresent(arguments, key: "app") { normalized["app"] = app }
        else if arguments["app"] != nil { return .failure(invalidType(key: "app", expected: "string")) }

        if let window = requireStringIfPresent(arguments, key: "window") { normalized["window"] = window }
        else if arguments["window"] != nil { return .failure(invalidType(key: "window", expected: "string")) }

        if let pid = requireIntIfPresent(arguments, key: "pid") { normalized["pid"] = pid }
        else if arguments["pid"] != nil { return .failure(invalidType(key: "pid", expected: "integer")) }

        if let depth = requireIntIfPresent(arguments, key: "depth") { normalized["depth"] = depth }
        else if arguments["depth"] != nil { return .failure(invalidType(key: "depth", expected: "integer")) }
        else { normalized["depth"] = .int(5) }

        if let textOnly = requireBoolIfPresent(arguments, key: "textOnly") { normalized["textOnly"] = textOnly }
        else if arguments["textOnly"] != nil { return .failure(invalidType(key: "textOnly", expected: "boolean")) }
        else { normalized["textOnly"] = .bool(false) }

        if let roles = requireStringIfPresent(arguments, key: "roles") { normalized["roles"] = roles }
        else if arguments["roles"] != nil { return .failure(invalidType(key: "roles", expected: "string")) }

        if let ignore = requireStringIfPresent(arguments, key: "ignore") { normalized["ignore"] = ignore }
        else if arguments["ignore"] != nil { return .failure(invalidType(key: "ignore", expected: "string")) }

        return .success(normalized)
    }

    private static func normalizeFindTextArguments(_ arguments: [String: MCPValue]) -> Result<[String: MCPValue], JSONRPCError> {
        let allowedKeys: Set<String> = ["query", "caseSensitive"]
        if let error = validateUnknownKeys(arguments, allowedKeys: allowedKeys) {
            return .failure(error)
        }

        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            if arguments["query"] == nil || arguments["query"] == .null {
                return .failure(JSONRPCError(code: -32602, message: "Invalid params: 'query' is required"))
            }
            return .failure(JSONRPCError(code: -32602, message: "Invalid params: 'query' must be a non-empty string"))
        }

        var normalized: [String: MCPValue] = ["query": .string(query)]
        if let caseSensitive = requireBoolIfPresent(arguments, key: "caseSensitive") {
            normalized["caseSensitive"] = caseSensitive
        } else if arguments["caseSensitive"] != nil {
            return .failure(invalidType(key: "caseSensitive", expected: "boolean"))
        } else {
            normalized["caseSensitive"] = .bool(false)
        }

        return .success(normalized)
    }

    private static func normalizeClickableArguments(_ arguments: [String: MCPValue]) -> Result<[String: MCPValue], JSONRPCError> {
        let allowedKeys: Set<String> = ["app", "window", "pid", "roles"]
        if let error = validateUnknownKeys(arguments, allowedKeys: allowedKeys) {
            return .failure(error)
        }

        var normalized: [String: MCPValue] = [:]
        if let app = requireStringIfPresent(arguments, key: "app") { normalized["app"] = app }
        else if arguments["app"] != nil { return .failure(invalidType(key: "app", expected: "string")) }

        if let window = requireStringIfPresent(arguments, key: "window") { normalized["window"] = window }
        else if arguments["window"] != nil { return .failure(invalidType(key: "window", expected: "string")) }

        if let pid = requireIntIfPresent(arguments, key: "pid") { normalized["pid"] = pid }
        else if arguments["pid"] != nil { return .failure(invalidType(key: "pid", expected: "integer")) }

        if let roles = requireStringIfPresent(arguments, key: "roles") { normalized["roles"] = roles }
        else if arguments["roles"] != nil { return .failure(invalidType(key: "roles", expected: "string")) }

        return .success(normalized)
    }

    private static func normalizeWatchArguments(_ arguments: [String: MCPValue]) -> Result<[String: MCPValue], JSONRPCError> {
        let allowedKeys: Set<String> = ["app", "window", "pid", "duration", "interval", "textOnly"]
        if let error = validateUnknownKeys(arguments, allowedKeys: allowedKeys) {
            return .failure(error)
        }

        var normalized: [String: MCPValue] = [:]
        if let app = requireStringIfPresent(arguments, key: "app") { normalized["app"] = app }
        else if arguments["app"] != nil { return .failure(invalidType(key: "app", expected: "string")) }

        if let window = requireStringIfPresent(arguments, key: "window") { normalized["window"] = window }
        else if arguments["window"] != nil { return .failure(invalidType(key: "window", expected: "string")) }

        if let pid = requireIntIfPresent(arguments, key: "pid") { normalized["pid"] = pid }
        else if arguments["pid"] != nil { return .failure(invalidType(key: "pid", expected: "integer")) }

        if let duration = requireIntIfPresent(arguments, key: "duration") { normalized["duration"] = duration }
        else if arguments["duration"] != nil { return .failure(invalidType(key: "duration", expected: "integer")) }
        else { normalized["duration"] = .int(10) }

        if let interval = requireIntIfPresent(arguments, key: "interval") { normalized["interval"] = interval }
        else if arguments["interval"] != nil { return .failure(invalidType(key: "interval", expected: "integer")) }
        else { normalized["interval"] = .int(2) }

        if let textOnly = requireBoolIfPresent(arguments, key: "textOnly") { normalized["textOnly"] = textOnly }
        else if arguments["textOnly"] != nil { return .failure(invalidType(key: "textOnly", expected: "boolean")) }
        else { normalized["textOnly"] = .bool(false) }

        return .success(normalized)
    }

    private static func validateNoArguments(_ arguments: [String: MCPValue], for tool: ScreenReadMCPTool) -> Result<[String: MCPValue], JSONRPCError> {
        guard arguments.isEmpty else {
            return .failure(JSONRPCError(code: -32602, message: "Invalid params: \(tool.rawValue) does not accept arguments"))
        }
        return .success([:])
    }

    private static func validateUnknownKeys(_ arguments: [String: MCPValue], allowedKeys: Set<String>) -> JSONRPCError? {
        let unknownKeys = arguments.keys.filter { !allowedKeys.contains($0) }.sorted()
        guard !unknownKeys.isEmpty else { return nil }
        return JSONRPCError(code: -32602, message: "Invalid params: unknown argument(s): \(unknownKeys.joined(separator: ", "))")
    }

    private static func requireStringIfPresent(_ arguments: [String: MCPValue], key: String) -> MCPValue? {
        guard let value = arguments[key] else { return nil }
        return value.stringValue.map(MCPValue.string)
    }

    private static func requireIntIfPresent(_ arguments: [String: MCPValue], key: String) -> MCPValue? {
        guard let value = arguments[key] else { return nil }
        return value.intValue.map(MCPValue.int)
    }

    private static func requireBoolIfPresent(_ arguments: [String: MCPValue], key: String) -> MCPValue? {
        guard let value = arguments[key] else { return nil }
        return value.boolValue.map(MCPValue.bool)
    }

    private static func invalidType(key: String, expected: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: "Invalid params: '\(key)' must be a \(expected)")
    }
}
