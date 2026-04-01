// Sources/screenread/ScreenRead.swift
import ArgumentParser
import ScreenReadCore
import Foundation
import ApplicationServices

@main
struct ScreenRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read the macOS accessibility tree from any application.",
        version: "0.2.0"
    )

    // Target
    @Option(name: .long, help: "Read frontmost window of app by name")
    var app: String?

    @Option(name: .long, help: "Fuzzy match on window title")
    var window: String?

    @Option(name: .long, help: "Target by process ID")
    var pid: Int32?

    @Flag(name: .long, help: "List all windows")
    var list = false

    @Option(name: .long, help: "Search for text across all open windows")
    var find: String?

    // Output
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Flag(name: .long, help: "Only readable text, no structure")
    var textOnly = false

    @Option(name: .long, help: "Max tree depth (default: 5, 0 = unlimited)")
    var depth: Int = 5

    @Flag(name: .long, help: "Alias for --depth 2")
    var shallow = false

    @Flag(name: .long, help: "Don't truncate long text values")
    var full = false

    // Filtering
    @Option(name: .long, help: "Comma-separated roles to include (e.g. AXButton,AXLink)")
    var role: String?

    @Option(name: .long, help: "Comma-separated roles to exclude (e.g. AXGroup,AXScrollArea)")
    var ignore: String?

    // Modes
    @Flag(name: .long, help: "Output interactive elements with click coordinates")
    var clickable = false

    @Flag(name: .long, help: "Stream JSONL output (one JSON object per node per line)")
    var stream = false

    @Flag(name: .long, help: "Watch for changes (poll-based, Ctrl+C to stop)")
    var watch = false

    @Option(name: .long, help: "Poll interval in seconds for --watch (default: 2)")
    var interval: Int = 2

    mutating func run() throws {
        let resolver = TargetResolver()

        // Handle --find
        if let query = find {
            guard !query.isEmpty else {
                throw ValidationError("--find requires a non-empty search string")
            }
            let queryLower = query.lowercased()
            var results: [String] = []
            let maxResults = 100
            var seenPIDs = Set<Int32>()

            for app in try resolver.listWindows() {
                if results.count >= maxResults { break }
                guard seenPIDs.insert(app.pid).inserted else { continue }

                do {
                    let element = try resolver.resolvePID(app.pid)
                    let walker = AXTreeWalker(maxDepth: 10, includeRoles: nil, excludeRoles: nil, truncateAt: 500, timeoutSeconds: 3.0)
                    let walkResult = walker.walk(element)
                    guard case .tree(let tree) = walkResult else { continue }
                    let text = Formatter.formatTextOnly(tree)
                    for line in text.components(separatedBy: "\n") {
                        if line.lowercased().contains(queryLower) {
                            results.append("[\(app.app) — \(app.title)] \(line.trimmingCharacters(in: .whitespaces))")
                            if results.count >= maxResults { break }
                        }
                    }
                } catch {
                    continue
                }
            }

            if results.isEmpty {
                print("No matches found for '\(query)'")
            } else {
                for line in results { print(line) }
                if results.count >= maxResults {
                    print("(limited to \(maxResults) results)")
                }
            }
            return
        }

        // Handle --list
        if list {
            let windows = try resolver.listWindows()
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(windows)
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print(Formatter.formatWindowList(windows))
            }
            return
        }

        // Resolve target
        let target: AXUIElement
        if let pidValue = pid {
            target = try resolver.resolvePID(pidValue)
        } else if let windowTitle = window {
            target = try resolver.resolveWindow(windowTitle)
        } else if let appName = app {
            target = try resolver.resolveApp(appName)
        } else {
            target = try resolver.resolveFrontmost()
        }

        // Determine effective depth
        let effectiveDepth = shallow ? 2 : depth

        // Parse role filters
        let includeRoles: Set<String>? = role.map { Set($0.split(separator: ",").map(String.init)) }
        let excludeRoles: Set<String>? = ignore.map { Set($0.split(separator: ",").map(String.init)) }

        // --clickable mode
        if clickable {
            let walker = AXTreeWalker(
                maxDepth: effectiveDepth,
                includeRoles: includeRoles,
                excludeRoles: excludeRoles,
                truncateAt: full ? 0 : 500
            )
            let result = walker.walk(target)
            switch result {
            case .tree(let tree):
                let effectiveRoles = includeRoles ?? Formatter.defaultInteractiveRoles
                if json {
                    print(Formatter.formatClickableJSON(tree, roles: effectiveRoles))
                } else {
                    print(Formatter.formatClickable(tree, roles: effectiveRoles))
                }
            case .timedOut:
                let name = app ?? window ?? "app"
                throw ScreenReadError.timeout(name)
            case .empty:
                throw ScreenReadError.emptyTree
            }
            return
        }

        // --stream mode
        if stream {
            let walker = AXTreeWalker(
                maxDepth: effectiveDepth,
                includeRoles: includeRoles,
                excludeRoles: excludeRoles,
                truncateAt: full ? 0 : 500
            )
            let result = walker.walk(target) { node, depth in
                print(StreamFormatter.formatNodeAsJSONL(node, depth: depth))
                fflush(stdout)
            }
            switch result {
            case .tree:
                break // nodes already printed via callback
            case .timedOut:
                let name = app ?? window ?? "app"
                fputs("error: timed out reading \(name)\n", stderr)
            case .empty:
                fputs("error: empty accessibility tree\n", stderr)
            }
            return
        }

        // --watch mode
        if watch {
            let truncateAt = full ? 0 : 500
            let makeWalker = {
                AXTreeWalker(
                    maxDepth: effectiveDepth,
                    includeRoles: includeRoles,
                    excludeRoles: excludeRoles,
                    truncateAt: truncateAt
                )
            }

            // Initial walk
            let initialResult = makeWalker().walk(target)
            guard case .tree(let initialTree) = initialResult else {
                if case .timedOut = initialResult {
                    let name = app ?? window ?? "app"
                    throw ScreenReadError.timeout(name)
                }
                throw ScreenReadError.emptyTree
            }

            if textOnly {
                print(Formatter.formatTextOnly(initialTree))
            } else {
                print(Formatter.formatTextTree(initialTree))
            }
            fflush(stdout)

            var previousTree = initialTree

            // Poll loop — Ctrl+C kills the process naturally
            while true {
                Thread.sleep(forTimeInterval: Double(interval))

                let pollResult = makeWalker().walk(target)
                guard case .tree(let newTree) = pollResult else { continue }

                let changes = TreeDiffer.diff(old: previousTree, new: newTree)
                if !changes.isEmpty {
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    print("--- \(timestamp) ---")
                    for change in changes {
                        print(change.formatted)
                    }
                    fflush(stdout)
                }
                previousTree = newTree
            }
        }

        // Walk tree
        let walker = AXTreeWalker(
            maxDepth: effectiveDepth,
            includeRoles: includeRoles,
            excludeRoles: excludeRoles,
            truncateAt: full ? 0 : 500
        )

        let result = walker.walk(target)

        switch result {
        case .tree(let tree):
            if json {
                print(Formatter.formatJSON(tree))
            } else if textOnly {
                print(Formatter.formatTextOnly(tree))
            } else {
                print(Formatter.formatTextTree(tree))
            }
        case .timedOut:
            let name = app ?? window ?? "app"
            throw ScreenReadError.timeout(name)
        case .empty:
            throw ScreenReadError.emptyTree
        }
    }
}
