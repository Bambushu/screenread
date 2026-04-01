// Sources/screenread-mcp/main.swift
import Foundation
import ApplicationServices
import ScreenReadCore

// MARK: - Response Helpers

enum MCPTransportError: Error {
    case invalidUTF8
    case invalidHeader(String)
    case missingContentLength
    case invalidContentLength(String)
    case unexpectedEOF
}

final class StdioMessageTransport {
    private let input: FileHandle
    private let output: FileHandle
    private var inputBuffer = Data()

    init(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) {
        self.input = input
        self.output = output
    }

    func readMessage() throws -> Data? {
        var contentLength: Int?

        while true {
            guard let line = try readHeaderLine() else {
                if contentLength == nil {
                    return nil
                }
                throw MCPTransportError.unexpectedEOF
            }

            if line.isEmpty {
                break
            }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw MCPTransportError.invalidHeader(line)
            }

            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if name == "content-length" {
                guard let parsed = Int(value), parsed >= 0 else {
                    throw MCPTransportError.invalidContentLength(value)
                }
                contentLength = parsed
            }
        }

        guard let contentLength else {
            throw MCPTransportError.missingContentLength
        }

        return try readExactly(count: contentLength)
    }

    func writeMessage(_ data: Data) {
        let header = "Content-Length: \(data.count)\r\n\r\n"
        if let headerData = header.data(using: .utf8) {
            output.write(headerData)
        }
        output.write(data)
        fflush(stdout)
    }

    private func readHeaderLine() throws -> String? {
        while true {
            if let newlineIndex = inputBuffer.firstIndex(of: 0x0A) {
                let lineData = inputBuffer.prefix(upTo: newlineIndex)
                inputBuffer.removeSubrange(...newlineIndex)

                var normalized = Data(lineData)
                if normalized.last == 0x0D {
                    normalized.removeLast()
                }

                guard let line = String(data: normalized, encoding: .utf8) else {
                    throw MCPTransportError.invalidUTF8
                }
                return line
            }

            guard try readIntoBuffer() else {
                if inputBuffer.isEmpty {
                    return nil
                }
                throw MCPTransportError.unexpectedEOF
            }
        }
    }

    private func readExactly(count: Int) throws -> Data {
        while inputBuffer.count < count {
            guard try readIntoBuffer() else {
                throw MCPTransportError.unexpectedEOF
            }
        }

        let data = inputBuffer.prefix(count)
        inputBuffer.removeFirst(count)
        return Data(data)
    }

    private func readIntoBuffer() throws -> Bool {
        guard let chunk = try input.read(upToCount: 4096), !chunk.isEmpty else {
            return false
        }
        inputBuffer.append(chunk)
        return true
    }
}

nonisolated(unsafe) let stdioTransport = StdioMessageTransport()

func sendResponse(_ id: JSONRPCID?, _ result: MCPValue) {
    let response = ScreenReadMCPProtocol.makeSuccessResponse(id: id, result: result)
    sendJSON(response)
}

func sendError(_ id: JSONRPCID?, code: Int, message: String) {
    let response = ScreenReadMCPProtocol.makeErrorResponse(id: id, code: code, message: message)
    sendJSON(response)
}

func sendToolResult(_ id: JSONRPCID?, text: String, isError: Bool = false) {
    sendResponse(id, ScreenReadMCPProtocol.makeToolResult(text: text, isError: isError))
}

func sendJSON(_ response: JSONRPCResponse) {
    let encoded = ScreenReadMCPProtocol.encodeResponse(response)
    guard let data = encoded.data(using: .utf8) else {
        if let fallback = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal serialization error\"}}".data(using: .utf8) {
            stdioTransport.writeMessage(fallback)
        }
        return
    }
    stdioTransport.writeMessage(data)
}

// MARK: - Tool Execution

struct ToolResult {
    let text: String
    let isError: Bool
}

func executeSnapshot(_ params: [String: MCPValue]?) -> ToolResult {
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

func executeFindText(_ params: [String: MCPValue]?) -> ToolResult {
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

func executeClickable(_ params: [String: MCPValue]?) -> ToolResult {
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

func executeWatch(_ params: [String: MCPValue]?) -> ToolResult {
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

while true {
    let data: Data
    do {
        guard let message = try stdioTransport.readMessage() else { break }
        data = message
    } catch {
        sendError(nil, code: -32700, message: "Parse error")
        continue
    }

    guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
        sendError(nil, code: -32700, message: "Parse error")
        continue
    }

    if let error = ScreenReadMCPProtocol.validateRequest(request) {
        sendError(request.id, code: error.code, message: error.message)
        continue
    }

    switch request.method {
    case "initialize":
        sendResponse(request.id, .object([
            "protocolVersion": .string(ScreenReadMCPProtocol.protocolVersion),
            "capabilities": .object([
                "tools": .object([
                    "listChanged": .bool(false),
                ]),
            ]),
            "serverInfo": .object([
                "name": .string("screenread"),
                "version": .string("0.2.0"),
            ]),
        ]))

    case "notifications/initialized":
        break // no response

    case "tools/list":
        sendResponse(request.id, .object([
            "tools": .array(ScreenReadMCPProtocol.toolDefinitions.map(\.jsonValue)),
        ]))

    case "tools/call":
        switch ScreenReadMCPProtocol.decodeToolCall(from: request.params) {
        case .failure(let error):
            sendError(request.id, code: error.code, message: error.message)
        case .success(let toolCall):
            switch toolCall.tool {
            case .snapshot:
                let result = executeSnapshot(toolCall.arguments)
                sendToolResult(request.id, text: result.text, isError: result.isError)
            case .list:
                let result = executeList()
                sendToolResult(request.id, text: result.text, isError: result.isError)
            case .findText:
                let result = executeFindText(toolCall.arguments)
                sendToolResult(request.id, text: result.text, isError: result.isError)
            case .clickable:
                let result = executeClickable(toolCall.arguments)
                sendToolResult(request.id, text: result.text, isError: result.isError)
            case .watch:
                let result = executeWatch(toolCall.arguments)
                sendToolResult(request.id, text: result.text, isError: result.isError)
            }
        }

    default:
        sendError(request.id, code: -32601, message: "Method not found: \(request.method)")
    }
}
