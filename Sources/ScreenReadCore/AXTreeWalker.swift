// Sources/ScreenReadCore/AXTreeWalker.swift
import Foundation
import ApplicationServices
import CoreGraphics

public final class AXTreeWalker: Sendable {
    private let maxDepth: Int // 0 = unlimited
    private let includeRoles: Set<String>?
    private let excludeRoles: Set<String>?
    private let truncateAt: Int

    public init(maxDepth: Int, includeRoles: Set<String>?, excludeRoles: Set<String>?, truncateAt: Int) {
        self.maxDepth = maxDepth
        self.includeRoles = includeRoles
        self.excludeRoles = excludeRoles
        self.truncateAt = truncateAt
    }

    public func walk(_ element: AXUIElement) -> AXNode? {
        return walkRecursive(element, depth: 0)
    }

    private func walkRecursive(_ element: AXUIElement, depth: Int) -> AXNode? {
        // Check depth limit (0 = unlimited)
        if maxDepth > 0 && depth > maxDepth {
            return nil
        }

        // Skip hidden elements
        if getBoolAttribute(element, kAXHiddenAttribute as CFString) == true {
            return nil
        }

        let role = getStringAttribute(element, kAXRoleAttribute as CFString) ?? "AXUnknown"

        // Apply role filters
        if let excludeRoles = excludeRoles, excludeRoles.contains(role) {
            return nil
        }
        if let includeRoles = includeRoles, !includeRoles.contains(role) {
            // Still walk children to find matching descendants
            return walkChildrenOnly(element, role: role, depth: depth)
        }

        let node = buildNode(element, role: role, depth: depth)
        return node
    }

    private func walkChildrenOnly(_ element: AXUIElement, role: String, depth: Int) -> AXNode? {
        let children = getChildren(element, depth: depth)
        if children.isEmpty { return nil }
        // Return a transparent pass-through: don't include this node, just its children
        return nil
    }

    private func buildNode(_ element: AXUIElement, role: String, depth: Int) -> AXNode {
        let subrole = getStringAttribute(element, kAXSubroleAttribute as CFString)
        let title = truncate(getStringAttribute(element, kAXTitleAttribute as CFString))
        let value = truncate(getStringAttribute(element, kAXValueAttribute as CFString))
        let roleDescription = getStringAttribute(element, kAXRoleDescriptionAttribute as CFString)
        let position = getPointAttribute(element, kAXPositionAttribute as CFString)
        let size = getSizeAttribute(element, kAXSizeAttribute as CFString)
        let children = getChildren(element, depth: depth)

        return AXNode(
            role: role,
            subrole: subrole,
            title: title,
            value: value,
            roleDescription: roleDescription,
            position: position,
            size: size,
            children: children
        )
    }

    private func getChildren(_ element: AXUIElement, depth: Int) -> [AXNode] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let children = value as? [AXUIElement] else {
            return []
        }
        return children.compactMap { walkRecursive($0, depth: depth + 1) }
    }

    // MARK: - Attribute Helpers

    private func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    private func getBoolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }

    private func getPointAttribute(_ element: AXUIElement, _ attribute: CFString) -> [String: Double]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let axValue = value else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return ["x": Double(point.x), "y": Double(point.y)]
    }

    private func getSizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> [String: Double]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let axValue = value else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return ["width": Double(size.width), "height": Double(size.height)]
    }

    private func truncate(_ str: String?) -> String? {
        guard let str = str else { return nil }
        if truncateAt > 0 && str.count > truncateAt {
            return String(str.prefix(truncateAt)) + "…"
        }
        return str
    }
}
