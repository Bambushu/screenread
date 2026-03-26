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
        let node = walker.walk(appElement)
        #expect(node != nil, "Frontmost app should produce a tree")
    }

    @Test("Depth limit is respected")
    func depthLimitRespected() throws {
        let resolver = TargetResolver()
        let appElement = try resolver.resolveFrontmost()
        let walker = AXTreeWalker(maxDepth: 1, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
        let node = walker.walk(appElement)
        guard let node = node else {
            Issue.record("Should produce a node")
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
        let node = walker.walk(appElement)
        guard let node = node else { return }
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
        let node = walker.walk(appElement)
        #expect(node != nil)
    }
}
