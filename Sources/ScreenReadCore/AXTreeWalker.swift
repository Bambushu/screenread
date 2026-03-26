// Sources/ScreenReadCore/AXTreeWalker.swift
import Foundation
import ApplicationServices
import CoreGraphics

public final class AXTreeWalker: Sendable {
    private let maxDepth: Int // 0 = unlimited
    private let includeRoles: Set<String>?
    private let excludeRoles: Set<String>?
    private let truncateAt: Int
    private let timeoutSeconds: Double

    public init(maxDepth: Int, includeRoles: Set<String>?, excludeRoles: Set<String>?, truncateAt: Int, timeoutSeconds: Double = 5.0) {
        self.maxDepth = maxDepth
        self.includeRoles = includeRoles
        self.excludeRoles = excludeRoles
        self.truncateAt = truncateAt
        self.timeoutSeconds = timeoutSeconds
    }

    /// Walk the accessibility tree from the given element.
    /// Returns .tree with the root node, .timedOut if the walk was aborted, or .empty if no content.
    public func walk(_ element: AXUIElement) -> WalkResult {
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        var nodeCount = 0
        if let node = walkRecursive(element, depth: 0, deadline: deadline, nodeCount: &nodeCount) {
            return .tree(node)
        }
        // Distinguish timeout from genuinely empty tree
        if ContinuousClock.now >= deadline {
            return .timedOut
        }
        return .empty
    }

    private func walkRecursive(_ element: AXUIElement, depth: Int, deadline: ContinuousClock.Instant, nodeCount: inout Int) -> AXNode? {
        // Check timeout every 256 nodes to avoid excessive syscalls
        nodeCount += 1
        if nodeCount & 0xFF == 0 && ContinuousClock.now >= deadline {
            return nil
        }

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
            // Flatten: splice matching descendants directly, don't wrap in a phantom node
            let children = getChildren(element, depth: depth, deadline: deadline, nodeCount: &nodeCount)
            if children.isEmpty { return nil }
            // Return children count == 1? Unwrap single child to avoid needless nesting
            if children.count == 1 { return children[0] }
            // Multiple matching descendants: wrap in a transparent group
            return AXNode(role: role, children: children)
        }

        return buildNode(element, role: role, depth: depth, deadline: deadline, nodeCount: &nodeCount)
    }

    private func buildNode(_ element: AXUIElement, role: String, depth: Int, deadline: ContinuousClock.Instant, nodeCount: inout Int) -> AXNode {
        let subrole = getStringAttribute(element, kAXSubroleAttribute as CFString)
        let title = truncate(getStringAttribute(element, kAXTitleAttribute as CFString))
        let value = truncate(getStringAttribute(element, kAXValueAttribute as CFString))
        let roleDescription = getStringAttribute(element, kAXRoleDescriptionAttribute as CFString)
        let position = getPointAttribute(element, kAXPositionAttribute as CFString)
        let size = getSizeAttribute(element, kAXSizeAttribute as CFString)
        let children = getChildren(element, depth: depth, deadline: deadline, nodeCount: &nodeCount)

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

    private func getChildren(_ element: AXUIElement, depth: Int, deadline: ContinuousClock.Instant, nodeCount: inout Int) -> [AXNode] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let children = value as? [AXUIElement] else {
            return []
        }
        return children.compactMap { walkRecursive($0, depth: depth + 1, deadline: deadline, nodeCount: &nodeCount) }
    }

    // MARK: - Attribute Helpers

    private func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        axStringAttribute(element, attribute)
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
        guard result == .success, let rawValue = value else { return nil }
        guard CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
        let axValue = rawValue as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return ["x": Double(point.x), "y": Double(point.y)]
    }

    private func getSizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> [String: Double]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let rawValue = value else { return nil }
        guard CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
        let axValue = rawValue as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return ["width": Double(size.width), "height": Double(size.height)]
    }

    private func truncate(_ str: String?) -> String? {
        guard let str = str, truncateAt > 0 else { return str }
        let truncated = str.prefix(truncateAt)
        // Short-circuit: if there's anything left after the prefix, the string was truncated
        return str.dropFirst(truncateAt).isEmpty ? str : String(truncated) + "…"
    }
}
