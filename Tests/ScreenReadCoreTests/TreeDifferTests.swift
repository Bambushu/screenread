// Tests/ScreenReadCoreTests/TreeDifferTests.swift
import Testing
@testable import ScreenReadCore

@Suite("TreeDiffer Tests")
struct TreeDifferTests {

    let baseTree = AXNode(
        role: "AXWindow", title: "App",
        children: [
            AXNode(role: "AXButton", title: "OK", isEnabled: true),
            AXNode(role: "AXButton", title: "Cancel", isEnabled: true),
            AXNode(role: "AXStaticText", value: "Hello"),
        ]
    )

    // Test 1: Identical trees → empty diff
    @Test("Identical trees produce no changes")
    func identicalTrees() {
        let changes = TreeDiffer.diff(old: baseTree, new: baseTree)
        #expect(changes.isEmpty)
    }

    // Test 2: Added node (append AXLink to children) → 1 added
    @Test("Added node is detected")
    func addedNode() {
        var newTree = baseTree
        newTree.children.append(AXNode(role: "AXLink", title: "More"))
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        #expect(changes.count == 1)
        if case .added(_, let node) = changes[0] {
            #expect(node.role == "AXLink")
        } else {
            Issue.record("Expected .added change")
        }
    }

    // Test 3: Removed node (removeLast) → 1 removed
    @Test("Removed node is detected")
    func removedNode() {
        var newTree = baseTree
        newTree.children.removeLast()
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        #expect(changes.count == 1)
        if case .removed(_, let node) = changes[0] {
            #expect(node.role == "AXStaticText")
        } else {
            Issue.record("Expected .removed change")
        }
    }

    // Test 4: Changed value (change "Hello" to "World") → 1 changed with field "value"
    @Test("Changed value is detected")
    func changedValue() {
        var newTree = baseTree
        newTree.children[2] = AXNode(role: "AXStaticText", value: "World")
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        #expect(changes.count == 1)
        if case .changed(_, _, _, let field) = changes[0] {
            #expect(field == "value")
        } else {
            Issue.record("Expected .changed change")
        }
    }

    // Test 5: Changed state (OK enabled→disabled) → 1 changed with field "isEnabled"
    @Test("Changed isEnabled state is detected")
    func changedState() {
        var newTree = baseTree
        newTree.children[0] = AXNode(role: "AXButton", title: "OK", isEnabled: false)
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        #expect(changes.count == 1)
        if case .changed(_, _, _, let field) = changes[0] {
            #expect(field == "isEnabled")
        } else {
            Issue.record("Expected .changed change")
        }
    }

    // Test 6: Position-only change → empty diff (ignored)
    @Test("Position-only changes are ignored")
    func positionOnlyChange() {
        var newTree = baseTree
        newTree.children[0] = AXNode(
            role: "AXButton", title: "OK",
            position: ["x": 999, "y": 999],
            size: ["width": 999, "height": 999],
            isEnabled: true
        )
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        #expect(changes.isEmpty)
    }

    // Test 7: Duplicate siblings (two "OK" buttons, change second) → 1 changed, path contains "[1]"
    @Test("Duplicate siblings are disambiguated by index")
    func duplicateSiblings() {
        let treeWithDupes = AXNode(
            role: "AXWindow", title: "App",
            children: [
                AXNode(role: "AXButton", title: "OK", isEnabled: true),
                AXNode(role: "AXButton", title: "OK", isEnabled: true),
            ]
        )
        var newTree = treeWithDupes
        newTree.children[1] = AXNode(role: "AXButton", title: "OK", isEnabled: false)
        let changes = TreeDiffer.diff(old: treeWithDupes, new: newTree)
        #expect(changes.count == 1)
        if case .changed(let path, _, _, let field) = changes[0] {
            #expect(field == "isEnabled")
            #expect(path.contains("[1]"))
        } else {
            Issue.record("Expected .changed change")
        }
    }
}
