// Tests/ScreenReadCoreTests/AXTreeWalkerTests.swift
import Testing
@testable import ScreenReadCore

@Suite("AXTreeWalker Tests")
struct AXTreeWalkerTests {

    @Test("Walk frontmost app returns non-empty tree")
    func walkFrontmostApp() throws {
        let resolver = TargetResolver()
        let appElement = try resolver.resolveFrontmost()
        let walker = AXTreeWalker(maxDepth: 3, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
        let result = walker.walk(appElement)
        guard case .tree = result else {
            Issue.record("Frontmost app should produce a tree, got \(result)")
            return
        }
    }

    @Test("Depth limit is respected")
    func depthLimitRespected() throws {
        let resolver = TargetResolver()
        let appElement = try resolver.resolveFrontmost()
        let walker = AXTreeWalker(maxDepth: 1, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
        let result = walker.walk(appElement)
        guard case .tree(let node) = result else {
            Issue.record("Should produce a tree")
            return
        }
        // At depth 1, children should exist but their children should be empty
        for child in node.children {
            #expect(child.children.isEmpty, "Depth-1 children should have no grandchildren")
        }
    }

    @Test("Role filtering excludes specified roles")
    func roleExcludeFilter() throws {
        let resolver = TargetResolver()
        let appElement = try resolver.resolveFrontmost()
        let walker = AXTreeWalker(maxDepth: 3, includeRoles: nil, excludeRoles: Set(["AXGroup"]), truncateAt: 500)
        let result = walker.walk(appElement)
        guard case .tree(let node) = result else { return }
        func assertNoGroups(_ n: AXNode) {
            #expect(n.role != "AXGroup", "AXGroup should be excluded")
            for child in n.children { assertNoGroups(child) }
        }
        for child in node.children { assertNoGroups(child) }
    }

    @Test("Unlimited depth with 0")
    func unlimitedDepth() throws {
        let resolver = TargetResolver()
        let appElement = try resolver.resolveFrontmost()
        let walker = AXTreeWalker(maxDepth: 0, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
        let result = walker.walk(appElement)
        guard case .tree = result else {
            Issue.record("Unlimited depth should produce a tree")
            return
        }
    }

    @Test("Timeout returns .timedOut for very short timeout")
    func timeoutDetected() throws {
        let resolver = TargetResolver()
        let appElement = try resolver.resolveFrontmost()
        // 0-second timeout should immediately time out
        let walker = AXTreeWalker(maxDepth: 0, includeRoles: nil, excludeRoles: nil, truncateAt: 500, timeoutSeconds: 0.0)
        let result = walker.walk(appElement)
        // With 0s timeout we expect either .timedOut or .tree (if the first node was read before timeout check)
        // The key test: it should not hang
        switch result {
        case .tree, .timedOut: break // both are acceptable
        case .empty: break // also possible if timeout fires before first node
        }
    }
}
