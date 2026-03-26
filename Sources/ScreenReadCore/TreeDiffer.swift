// Sources/ScreenReadCore/TreeDiffer.swift
import Foundation

// MARK: - TreeChange

public enum TreeChange: Sendable {
    case added(path: String, node: AXNode)
    case removed(path: String, node: AXNode)
    case changed(path: String, old: AXNode, new: AXNode, field: String)
}

// MARK: - TreeDiffer

public enum TreeDiffer {

    /// Diff two accessibility trees and return a list of semantic changes.
    /// Position and size changes are ignored.
    public static func diff(old: AXNode, new: AXNode, path: String = "") -> [TreeChange] {
        var changes: [TreeChange] = []
        let currentPath = path.isEmpty ? nodeKey(old) : path

        // Compare fields on these two matched nodes
        changes.append(contentsOf: compareFields(old: old, new: new, path: currentPath))

        // Match children by key + sibling index
        let oldKeyed = keyedChildren(old.children)
        let newKeyed = keyedChildren(new.children)

        let allKeys = Set(oldKeyed.keys).union(newKeyed.keys)

        for key in allKeys {
            let childPath = "\(currentPath)/\(key)"
            if let oldChild = oldKeyed[key], let newChild = newKeyed[key] {
                // Recurse into matched pair
                changes.append(contentsOf: diff(old: oldChild, new: newChild, path: childPath))
            } else if let oldChild = oldKeyed[key] {
                changes.append(.removed(path: childPath, node: oldChild))
            } else if let newChild = newKeyed[key] {
                changes.append(.added(path: childPath, node: newChild))
            }
        }

        return changes
    }

    // MARK: - Field Comparison

    private static func compareFields(old: AXNode, new: AXNode, path: String) -> [TreeChange] {
        var changes: [TreeChange] = []

        if old.title != new.title {
            changes.append(.changed(path: path, old: old, new: new, field: "title"))
        }
        if old.value != new.value {
            changes.append(.changed(path: path, old: old, new: new, field: "value"))
        }
        if old.isEnabled != new.isEnabled {
            changes.append(.changed(path: path, old: old, new: new, field: "isEnabled"))
        }
        if old.isFocused != new.isFocused {
            changes.append(.changed(path: path, old: old, new: new, field: "isFocused"))
        }
        if old.isSelected != new.isSelected {
            changes.append(.changed(path: path, old: old, new: new, field: "isSelected"))
        }

        return changes
    }

    // MARK: - Child Keying

    /// Builds a dictionary mapping `"role:title[index]"` → AXNode.
    /// Sibling index is per unique base key, so two "AXButton:OK" nodes
    /// get keys "AXButton:OK[0]" and "AXButton:OK[1]".
    static func keyedChildren(_ children: [AXNode]) -> [String: AXNode] {
        var counts: [String: Int] = [:]
        var result: [String: AXNode] = [:]
        for child in children {
            let base = nodeKey(child)
            let idx = counts[base, default: 0]
            counts[base] = idx + 1
            let key = "\(base)[\(idx)]"
            result[key] = child
        }
        return result
    }

    /// Returns `"role:title"` if the node has a title, otherwise just `"role"`.
    static func nodeKey(_ node: AXNode) -> String {
        if let title = node.title, !title.isEmpty {
            return "\(node.role):\(title)"
        }
        return node.role
    }
}

// MARK: - TreeChange Formatting

public extension TreeChange {

    var formatted: String {
        switch self {
        case .added(_, let node):
            let role = cleanRole(node.role)
            let label = nodeLabel(node)
            return label.isEmpty ? "+ [\(role)]" : "+ [\(role)] \(label)"

        case .removed(_, let node):
            let role = cleanRole(node.role)
            let label = nodeLabel(node)
            return label.isEmpty ? "- [\(role)]" : "- [\(role)] \(label)"

        case .changed(_, let old, let new, let field):
            let role = cleanRole(old.role)
            let label = nodeLabel(old)
            let oldVal = fieldValue(old, field: field)
            let newVal = fieldValue(new, field: field)
            let prefix = label.isEmpty ? "~ [\(role)]" : "~ [\(role)] \(label)"
            return "\(prefix): \(field) \(oldVal) → \(newVal)"
        }
    }

    // MARK: - Helpers

    private func cleanRole(_ role: String) -> String {
        var cleaned = role
        if cleaned.hasPrefix("AX") {
            cleaned = String(cleaned.dropFirst(2))
        }
        return cleaned.lowercased()
    }

    private func nodeLabel(_ node: AXNode) -> String {
        if let title = node.title, !title.isEmpty { return title }
        if let value = node.value, !value.isEmpty { return value }
        return ""
    }

    private func fieldValue(_ node: AXNode, field: String) -> String {
        switch field {
        case "title":
            return node.title.map { "\"\($0)\"" } ?? "nil"
        case "value":
            return node.value.map { "\"\($0)\"" } ?? "nil"
        case "isEnabled":
            return node.isEnabled.map { $0 ? "enabled" : "disabled" } ?? "nil"
        case "isFocused":
            return node.isFocused.map { $0 ? "focused" : "unfocused" } ?? "nil"
        case "isSelected":
            return node.isSelected.map { $0 ? "selected" : "unselected" } ?? "nil"
        default:
            return "?"
        }
    }
}
