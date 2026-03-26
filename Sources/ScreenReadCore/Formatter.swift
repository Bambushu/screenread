// Sources/ScreenReadCore/Formatter.swift
import Foundation

public enum Formatter {

    // MARK: - Text Tree

    public static func formatTextTree(_ node: AXNode) -> String {
        var lines: [String] = []
        appendTextTree(node, indent: 0, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendTextTree(_ node: AXNode, indent: Int, lines: inout [String]) {
        let prefix = String(repeating: "  ", count: indent)
        let role = cleanRole(node.role)
        let label = buildLabel(node)
        let line = label.isEmpty ? "\(prefix)[\(role)]" : "\(prefix)[\(role)] \(label)"
        lines.append(line)
        for child in node.children {
            appendTextTree(child, indent: indent + 1, lines: &lines)
        }
    }

    // MARK: - Text Only

    public static func formatTextOnly(_ node: AXNode) -> String {
        var lines: [String] = []
        appendTextOnly(node, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendTextOnly(_ node: AXNode, lines: inout [String]) {
        let text = buildLabel(node)
        if !text.isEmpty {
            lines.append(text)
        }
        for child in node.children {
            appendTextOnly(child, lines: &lines)
        }
    }

    // MARK: - JSON

    public static func formatJSON(_ node: AXNode) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(node),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Window List

    public static func formatWindowList(_ windows: [WindowInfo]) -> String {
        windows.map { $0.formatted }.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func cleanRole(_ role: String) -> String {
        // "AXButton" -> "button", "AXStaticText" -> "statictext"
        var cleaned = role
        if cleaned.hasPrefix("AX") {
            cleaned = String(cleaned.dropFirst(2))
        }
        return cleaned.lowercased()
    }

    private static func buildLabel(_ node: AXNode) -> String {
        // Prefer title, fall back to value
        if let title = node.title, !title.isEmpty {
            if let value = node.value, !value.isEmpty, value != title {
                return "\(title): \(value)"
            }
            return title
        }
        if let value = node.value, !value.isEmpty {
            return value
        }
        return ""
    }
}
