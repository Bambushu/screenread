// Sources/ScreenReadCore/Formatter.swift
import Foundation

public enum Formatter {

    // MARK: - Default Interactive Roles

    public static let defaultInteractiveRoles: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox",
        "AXRadioButton", "AXPopUpButton", "AXSlider", "AXMenuItem",
        "AXTab", "AXComboBox", "AXIncrementor"
    ]

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
        let flags = buildStateFlags(node)
        var line = label.isEmpty ? "\(prefix)[\(role)]" : "\(prefix)[\(role)] \(label)"
        if !flags.isEmpty {
            line += " \(flags)"
        }
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

    // MARK: - Clickable (TSV)

    public static func formatClickable(_ node: AXNode, roles: Set<String>? = nil) -> String {
        let effectiveRoles = roles ?? defaultInteractiveRoles
        var items: [ClickableItem] = []
        collectClickable(node, roles: effectiveRoles, items: &items)
        var lines = ["ROLE\tLABEL\tX,Y\tSTATE"]
        for item in items {
            lines.append("\(item.role)\t\(item.label)\t\(item.x),\(item.y)\t\(item.state)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Clickable (JSON)

    public static func formatClickableJSON(_ node: AXNode, roles: Set<String>? = nil) -> String {
        let effectiveRoles = roles ?? defaultInteractiveRoles
        var items: [ClickableItem] = []
        collectClickable(node, roles: effectiveRoles, items: &items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(items),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
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

    private static func buildStateFlags(_ node: AXNode) -> String {
        var flags: [String] = []
        if node.isEnabled == false {
            flags.append("disabled")
        }
        if node.isFocused == true {
            flags.append("focused")
        }
        if node.isSelected == true {
            flags.append("selected")
        }
        if flags.isEmpty { return "" }
        return "(\(flags.joined(separator: ", ")))"
    }

    private static func collectClickable(_ node: AXNode, roles: Set<String>, items: inout [ClickableItem]) {
        if roles.contains(node.role),
           let position = node.position,
           let size = node.size,
           let px = position["x"], let py = position["y"],
           let sw = size["width"], let sh = size["height"] {
            let cx = Int((px + sw / 2).rounded())
            let cy = Int((py + sh / 2).rounded())
            let state: String
            if node.isEnabled == false {
                state = "disabled"
            } else if node.isFocused == true {
                state = "focused"
            } else if node.isSelected == true {
                state = "selected"
            } else {
                state = "enabled"
            }
            let label = buildLabel(node)
            items.append(ClickableItem(role: node.role, label: label, x: cx, y: cy, state: state))
        }
        for child in node.children {
            collectClickable(child, roles: roles, items: &items)
        }
    }
}

// MARK: - ClickableItem

private struct ClickableItem: Codable {
    let role: String
    let label: String
    let x: Int
    let y: Int
    let state: String
}
