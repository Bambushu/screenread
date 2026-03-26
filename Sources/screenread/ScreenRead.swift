// Sources/screenread/ScreenRead.swift
import ArgumentParser
import ScreenReadCore

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
    @Option(name: .long, help: "Comma-separated roles to include")
    var role: String?

    @Option(name: .long, help: "Comma-separated roles to exclude")
    var ignore: String?

    mutating func run() throws {
        print("screenread v0.1.0 — not yet implemented")
    }
}
