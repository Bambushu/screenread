// Sources/screenread/ScreenRead.swift
import ArgumentParser
import ScreenReadCore
import Foundation
import ApplicationServices

@main
struct ScreenRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read the macOS accessibility tree from any application.",
        version: "0.1.0"
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

    mutating func run() throws {
        let resolver = TargetResolver()

        // Handle --list
        if list {
            let windows = resolver.listWindows()
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(windows)
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                for w in windows {
                    print("\(w.app) [\(w.pid)] — \(w.title)")
                }
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

        // Walk tree
        let walker = AXTreeWalker(
            maxDepth: effectiveDepth,
            includeRoles: includeRoles,
            excludeRoles: excludeRoles,
            truncateAt: full ? 0 : 500
        )

        guard let tree = walker.walk(target) else {
            throw ScreenReadError.emptyTree
        }

        // Format output
        if json {
            print(Formatter.formatJSON(tree))
        } else if textOnly {
            print(Formatter.formatTextOnly(tree))
        } else {
            print(Formatter.formatTextTree(tree))
        }
    }
}
