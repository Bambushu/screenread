# ScreenRead v0.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add watch mode, element state metadata, clickable coordinates, and JSONL streaming to ScreenRead.

**Architecture:** Four features layered bottom-up. State metadata (isEnabled/isFocused/isSelected) on AXNode is the foundation — it feeds into the formatter, TreeDiffer, clickable output, and streaming. TreeDiffer enables watch mode. Each feature adds to the core library first, then CLI, then MCP.

**Tech Stack:** Swift 6, macOS Accessibility API (AXUIElement), ArgumentParser, JSON-RPC stdio MCP

**Build command:** `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift build`
**Test command:** `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test`

---

### Task 1: Add state metadata to AXNode

**Files:**
- Modify: `Sources/ScreenReadCore/Types.swift`
- Modify: `Sources/ScreenReadCore/AXTreeWalker.swift`
- Modify: `Tests/ScreenReadCoreTests/AXTreeWalkerTests.swift`

- [ ] **Step 1: Write failing test for state metadata**

Add to `Tests/ScreenReadCoreTests/AXTreeWalkerTests.swift`:

```swift
@Test("Walk collects isEnabled state on nodes")
func walkCollectsState() throws {
    let resolver = TargetResolver()
    let appElement = try resolver.resolveFrontmost()
    let walker = AXTreeWalker(maxDepth: 3, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
    let result = walker.walk(appElement)
    guard case .tree(let node) = result else {
        Issue.record("Should produce a tree")
        return
    }
    // At least the root application node should have isEnabled
    func findNodeWithEnabled(_ n: AXNode) -> Bool {
        if n.isEnabled != nil { return true }
        return n.children.contains { findNodeWithEnabled($0) }
    }
    #expect(findNodeWithEnabled(node), "At least one node should have isEnabled set")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test 2>&1 | grep -E "walkCollectsState|error"`
Expected: Compilation error — `AXNode` has no member `isEnabled`

- [ ] **Step 3: Add state fields to AXNode**

In `Sources/ScreenReadCore/Types.swift`, update the AXNode struct. Add the three state fields after `children`:

```swift
public struct AXNode: Sendable, Codable {
    public let role: String
    public let subrole: String?
    public let title: String?
    public let value: String?
    public let roleDescription: String?
    public let position: [String: Double]?
    public let size: [String: Double]?
    public var children: [AXNode]
    public let isEnabled: Bool?
    public let isFocused: Bool?
    public let isSelected: Bool?

    public init(
        role: String,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        roleDescription: String? = nil,
        position: [String: Double]? = nil,
        size: [String: Double]? = nil,
        children: [AXNode] = [],
        isEnabled: Bool? = nil,
        isFocused: Bool? = nil,
        isSelected: Bool? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.roleDescription = roleDescription
        self.position = position
        self.size = size
        self.children = children
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.isSelected = isSelected
    }
}
```

- [ ] **Step 4: Collect state in AXTreeWalker.buildNode**

In `Sources/ScreenReadCore/AXTreeWalker.swift`, update `buildNode` to read the three state attributes:

```swift
private func buildNode(_ element: AXUIElement, role: String, depth: Int, deadline: ContinuousClock.Instant, nodeCount: inout Int) -> AXNode {
    let subrole = getStringAttribute(element, kAXSubroleAttribute as CFString)
    let title = truncate(getStringAttribute(element, kAXTitleAttribute as CFString))
    let value = truncate(getStringAttribute(element, kAXValueAttribute as CFString))
    let roleDescription = getStringAttribute(element, kAXRoleDescriptionAttribute as CFString)
    let position = getPointAttribute(element, kAXPositionAttribute as CFString)
    let size = getSizeAttribute(element, kAXSizeAttribute as CFString)
    let children = getChildren(element, depth: depth, deadline: deadline, nodeCount: &nodeCount)
    let isEnabled = getBoolAttribute(element, kAXEnabledAttribute as CFString)
    let isFocused = getBoolAttribute(element, kAXFocusedAttribute as CFString)
    let isSelected = getBoolAttribute(element, kAXSelectedAttribute as CFString)

    return AXNode(
        role: role,
        subrole: subrole,
        title: title,
        value: value,
        roleDescription: roleDescription,
        position: position,
        size: size,
        children: children,
        isEnabled: isEnabled,
        isFocused: isFocused,
        isSelected: isSelected
    )
}
```

- [ ] **Step 5: Run tests**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test`
Expected: All 16 tests pass (15 existing + 1 new)

- [ ] **Step 6: Commit**

```bash
git add Sources/ScreenReadCore/Types.swift Sources/ScreenReadCore/AXTreeWalker.swift Tests/ScreenReadCoreTests/AXTreeWalkerTests.swift
git commit -m "feat: add isEnabled, isFocused, isSelected state to AXNode"
```

---

### Task 2: Update Formatter with state flags and clickable output

**Files:**
- Modify: `Sources/ScreenReadCore/Formatter.swift`
- Modify: `Tests/ScreenReadCoreTests/FormatterTests.swift`

- [ ] **Step 1: Write failing tests for state flags and clickable format**

Add to `Tests/ScreenReadCoreTests/FormatterTests.swift`:

```swift
let disabledButton = AXNode(
    role: "AXButton",
    title: "Delete",
    position: ["x": 400, "y": 300],
    size: ["width": 80, "height": 40],
    isEnabled: false
)

let focusedField = AXNode(
    role: "AXTextField",
    title: "Search",
    value: "hello",
    position: ["x": 200, "y": 50],
    size: ["width": 200, "height": 30],
    isEnabled: true,
    isFocused: true
)

let enabledButton = AXNode(
    role: "AXButton",
    title: "Submit",
    position: ["x": 440, "y": 310],
    size: ["width": 80, "height": 40],
    isEnabled: true
)

let interactiveTree = AXNode(
    role: "AXWindow",
    title: "Test",
    children: [disabledButton, focusedField, enabledButton,
               AXNode(role: "AXStaticText", value: "Just text")]
)

@Test("Text tree shows state flags for non-default states")
func textTreeStateFlags() {
    let output = Formatter.formatTextTree(interactiveTree)
    #expect(output.contains("(disabled)"))
    #expect(output.contains("(focused)"))
    #expect(!output.contains("Submit (enabled)"))  // enabled is default, not shown
}

@Test("Clickable format outputs only interactive elements with center coordinates")
func clickableFormat() {
    let output = Formatter.formatClickable(interactiveTree)
    #expect(output.contains("480,330"))   // Submit center: 440+80/2=480, 310+40/2=330
    #expect(output.contains("300,65"))    // Search center: 200+200/2=300, 50+30/2=65
    #expect(output.contains("disabled"))
    #expect(!output.contains("Just text")) // static text excluded
}

@Test("Clickable JSON format is valid JSON array")
func clickableJSONFormat() {
    let output = Formatter.formatClickableJSON(interactiveTree)
    #expect(output.hasPrefix("["))
    #expect(output.hasSuffix("]"))
    #expect(output.contains("\"x\":480"))    // Submit: 440+80/2=480
    #expect(output.contains("\"x\":300"))    // Search: 200+200/2=300
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test 2>&1 | grep -E "error|FAIL"`
Expected: Compilation errors — `formatClickable` and `formatClickableJSON` don't exist, state flags not shown

- [ ] **Step 3: Add state flags to text tree formatter**

In `Sources/ScreenReadCore/Formatter.swift`, update `appendTextTree`:

```swift
private static func appendTextTree(_ node: AXNode, indent: Int, lines: inout [String]) {
    let prefix = String(repeating: "  ", count: indent)
    let role = cleanRole(node.role)
    let label = buildLabel(node)
    let state = buildStateFlags(node)
    var line = label.isEmpty ? "\(prefix)[\(role)]" : "\(prefix)[\(role)] \(label)"
    if !state.isEmpty { line += " (\(state))" }
    lines.append(line)
    for child in node.children {
        appendTextTree(child, indent: indent + 1, lines: &lines)
    }
}
```

Add the `buildStateFlags` helper:

```swift
private static func buildStateFlags(_ node: AXNode) -> String {
    var flags: [String] = []
    if node.isEnabled == false { flags.append("disabled") }
    if node.isFocused == true { flags.append("focused") }
    if node.isSelected == true { flags.append("selected") }
    return flags.joined(separator: ", ")
}
```

- [ ] **Step 4: Add clickable formatters**

Add to `Sources/ScreenReadCore/Formatter.swift`:

```swift
// MARK: - Clickable

public static let defaultInteractiveRoles: Set<String> = [
    "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox",
    "AXRadioButton", "AXPopUpButton", "AXSlider", "AXMenuItem",
    "AXTab", "AXComboBox", "AXIncrementor"
]

public static func formatClickable(_ node: AXNode, roles: Set<String>? = nil) -> String {
    let items = collectClickable(node, roles: roles ?? defaultInteractiveRoles)
    if items.isEmpty { return "No interactive elements found." }
    var lines = ["ROLE\tLABEL\tX,Y\tSTATE"]
    for item in items {
        lines.append("\(cleanRole(item.role))\t\(item.label)\t\(item.x),\(item.y)\t\(item.state)")
    }
    return lines.joined(separator: "\n")
}

public static func formatClickableJSON(_ node: AXNode, roles: Set<String>? = nil) -> String {
    let items = collectClickable(node, roles: roles ?? defaultInteractiveRoles)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(items),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}

private struct ClickableItem: Codable {
    let role: String
    let label: String
    let x: Int
    let y: Int
    let state: String
}

private static func collectClickable(_ node: AXNode, roles: Set<String>) -> [ClickableItem] {
    var items: [ClickableItem] = []
    collectClickableRecursive(node, roles: roles, items: &items)
    return items
}

private static func collectClickableRecursive(_ node: AXNode, roles: Set<String>, items: inout [ClickableItem]) {
    if roles.contains(node.role),
       let pos = node.position, let sz = node.size,
       let px = pos["x"], let py = pos["y"],
       let sw = sz["width"], let sh = sz["height"] {
        let label = buildLabel(node)
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
        items.append(ClickableItem(
            role: node.role,
            label: label,
            x: Int(px + sw / 2),
            y: Int(py + sh / 2),
            state: state
        ))
    }
    for child in node.children {
        collectClickableRecursive(child, roles: roles, items: &items)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test`
Expected: All tests pass (including the 3 new ones)

- [ ] **Step 6: Commit**

```bash
git add Sources/ScreenReadCore/Formatter.swift Tests/ScreenReadCoreTests/FormatterTests.swift
git commit -m "feat: add state flags to text tree, add clickable/clickableJSON formatters"
```

---

### Task 3: Implement TreeDiffer

**Files:**
- Create: `Sources/ScreenReadCore/TreeDiffer.swift`
- Create: `Tests/ScreenReadCoreTests/TreeDifferTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/ScreenReadCoreTests/TreeDifferTests.swift`:

```swift
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

    @Test("Identical trees produce empty diff")
    func identicalTrees() {
        let changes = TreeDiffer.diff(old: baseTree, new: baseTree)
        #expect(changes.isEmpty)
    }

    @Test("Added node is detected")
    func addedNode() {
        var newTree = baseTree
        newTree.children.append(AXNode(role: "AXLink", title: "Help"))
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        let added = changes.filter { if case .added = $0 { return true }; return false }
        #expect(added.count == 1)
    }

    @Test("Removed node is detected")
    func removedNode() {
        var newTree = baseTree
        newTree.children.removeLast() // remove StaticText
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        let removed = changes.filter { if case .removed = $0 { return true }; return false }
        #expect(removed.count == 1)
    }

    @Test("Changed value is detected")
    func changedValue() {
        var newTree = baseTree
        newTree.children[2] = AXNode(role: "AXStaticText", value: "World")
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        let changed = changes.filter { if case .changed = $0 { return true }; return false }
        #expect(changed.count >= 1)
    }

    @Test("Changed state is detected")
    func changedState() {
        var newTree = baseTree
        newTree.children[0] = AXNode(role: "AXButton", title: "OK", isEnabled: false)
        let changes = TreeDiffer.diff(old: baseTree, new: newTree)
        let changed = changes.filter { if case .changed(_, _, _, let field) = $0 { return field == "isEnabled" }; return false }
        #expect(changed.count == 1)
    }

    @Test("Position-only change produces no diff")
    func positionIgnored() {
        let oldNode = AXNode(role: "AXButton", title: "OK", position: ["x": 10, "y": 20])
        let newNode = AXNode(role: "AXButton", title: "OK", position: ["x": 30, "y": 40])
        let oldTree = AXNode(role: "AXWindow", children: [oldNode])
        let newTree = AXNode(role: "AXWindow", children: [newNode])
        let changes = TreeDiffer.diff(old: oldTree, new: newTree)
        #expect(changes.isEmpty)
    }

    @Test("Duplicate role+title siblings disambiguated by index")
    func duplicateSiblings() {
        let old = AXNode(role: "AXWindow", children: [
            AXNode(role: "AXButton", title: "OK", value: "first"),
            AXNode(role: "AXButton", title: "OK", value: "second"),
        ])
        var new = old
        new.children[1] = AXNode(role: "AXButton", title: "OK", value: "changed")
        let changes = TreeDiffer.diff(old: old, new: new)
        // Only the second OK button changed, not the first
        #expect(changes.count == 1)
        if case .changed(let path, _, _, _) = changes.first {
            #expect(path.contains("[1]"))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test 2>&1 | grep -E "error|TreeDiffer"`
Expected: Compilation error — `TreeDiffer` not found

- [ ] **Step 3: Implement TreeDiffer**

Create `Sources/ScreenReadCore/TreeDiffer.swift`:

```swift
// Sources/ScreenReadCore/TreeDiffer.swift
import Foundation

public enum TreeChange: Sendable {
    case added(path: String, node: AXNode)
    case removed(path: String, node: AXNode)
    case changed(path: String, old: AXNode, new: AXNode, field: String)
}

public enum TreeDiffer {

    public static func diff(old: AXNode, new: AXNode) -> [TreeChange] {
        var changes: [TreeChange] = []
        diffRecursive(old: old, new: new, path: nodeKey(old), changes: &changes)
        return changes
    }

    private static func diffRecursive(old: AXNode, new: AXNode, path: String, changes: inout [TreeChange]) {
        // Compare fields (ignoring position/size)
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

        // Build keyed child maps with sibling index for disambiguation
        let oldKeyed = keyedChildren(old.children)
        let newKeyed = keyedChildren(new.children)

        let oldKeys = Set(oldKeyed.keys)
        let newKeys = Set(newKeyed.keys)

        // Removed children
        for key in oldKeys.subtracting(newKeys) {
            if let child = oldKeyed[key] {
                changes.append(.removed(path: "\(path)/\(key)", node: child))
            }
        }

        // Added children
        for key in newKeys.subtracting(oldKeys) {
            if let child = newKeyed[key] {
                changes.append(.added(path: "\(path)/\(key)", node: child))
            }
        }

        // Recurse into matched children
        for key in oldKeys.intersection(newKeys) {
            if let oldChild = oldKeyed[key], let newChild = newKeyed[key] {
                diffRecursive(old: oldChild, new: newChild, path: "\(path)/\(key)", changes: &changes)
            }
        }
    }

    private static func keyedChildren(_ children: [AXNode]) -> [String: AXNode] {
        var counts: [String: Int] = [:]
        var result: [String: AXNode] = [:]
        for child in children {
            let base = nodeKey(child)
            let index = counts[base, default: 0]
            counts[base] = index + 1
            result["\(base)[\(index)]"] = child
        }
        return result
    }

    private static func nodeKey(_ node: AXNode) -> String {
        let label = node.title ?? node.value ?? ""
        return label.isEmpty ? node.role : "\(node.role):\(label)"
    }
}

// MARK: - Formatting

extension TreeChange {
    public var formatted: String {
        switch self {
        case .added(_, let node):
            let label = node.title ?? node.value ?? node.role
            return "+ [\(cleanRole(node.role))] \(label)"
        case .removed(_, let node):
            let label = node.title ?? node.value ?? node.role
            return "- [\(cleanRole(node.role))] \(label)"
        case .changed(_, let old, let new, let field):
            let oldVal = fieldValue(old, field)
            let newVal = fieldValue(new, field)
            let label = new.title ?? new.value ?? new.role
            return "~ [\(cleanRole(new.role))] \(label): \(field) \(oldVal) → \(newVal)"
        }
    }

    private func cleanRole(_ role: String) -> String {
        var cleaned = role
        if cleaned.hasPrefix("AX") { cleaned = String(cleaned.dropFirst(2)) }
        return cleaned.lowercased()
    }

    private func fieldValue(_ node: AXNode, _ field: String) -> String {
        switch field {
        case "title": return "\"\(node.title ?? "")\""
        case "value": return "\"\(node.value ?? "")\""
        case "isEnabled": return node.isEnabled == true ? "enabled" : "disabled"
        case "isFocused": return node.isFocused == true ? "focused" : "unfocused"
        case "isSelected": return node.isSelected == true ? "selected" : "unselected"
        default: return "?"
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test`
Expected: All tests pass (including the 7 new TreeDiffer tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenReadCore/TreeDiffer.swift Tests/ScreenReadCoreTests/TreeDifferTests.swift
git commit -m "feat: add TreeDiffer for comparing accessibility tree snapshots"
```

---

### Task 4: Add onNode streaming callback to AXTreeWalker

**Files:**
- Modify: `Sources/ScreenReadCore/AXTreeWalker.swift`
- Create: `Sources/ScreenReadCore/StreamFormatter.swift`
- Modify: `Tests/ScreenReadCoreTests/AXTreeWalkerTests.swift`

- [ ] **Step 1: Write failing test for onNode callback**

Add to `Tests/ScreenReadCoreTests/AXTreeWalkerTests.swift`:

```swift
@Test("onNode callback receives nodes during walk")
func onNodeCallback() throws {
    let resolver = TargetResolver()
    let appElement = try resolver.resolveFrontmost()
    let walker = AXTreeWalker(maxDepth: 2, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
    var visitedNodes: [(String, Int)] = [] // (role, depth)
    let result = walker.walk(appElement) { node, depth in
        visitedNodes.append((node.role, depth))
    }
    guard case .tree = result else {
        Issue.record("Should produce a tree")
        return
    }
    #expect(!visitedNodes.isEmpty, "Callback should have been called at least once")
    #expect(visitedNodes[0].1 == 0, "First callback should be at depth 0")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test 2>&1 | grep -E "error|onNodeCallback"`
Expected: Compilation error — `walk` doesn't accept a closure

- [ ] **Step 3: Add onNode callback to walk()**

In `Sources/ScreenReadCore/AXTreeWalker.swift`, add the callback typealias and update `walk()`:

```swift
public typealias NodeCallback = (AXNode, Int) -> Void

public func walk(_ element: AXUIElement, onNode: NodeCallback? = nil) -> WalkResult {
    let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
    var nodeCount = 0
    if let node = walkRecursive(element, depth: 0, deadline: deadline, nodeCount: &nodeCount, onNode: onNode) {
        return .tree(node)
    }
    if ContinuousClock.now >= deadline {
        return .timedOut
    }
    return .empty
}
```

Update `walkRecursive` signature to pass `onNode` through, and call it after building a node:

```swift
private func walkRecursive(_ element: AXUIElement, depth: Int, deadline: ContinuousClock.Instant, nodeCount: inout Int, onNode: NodeCallback?) -> AXNode? {
    // ... existing timeout and depth checks unchanged ...

    // ... existing role filter logic unchanged, but pass onNode to getChildren ...

    return buildNode(element, role: role, depth: depth, deadline: deadline, nodeCount: &nodeCount, onNode: onNode)
}
```

Update `buildNode` to call the callback:

```swift
private func buildNode(_ element: AXUIElement, role: String, depth: Int, deadline: ContinuousClock.Instant, nodeCount: inout Int, onNode: NodeCallback?) -> AXNode {
    // ... existing attribute collection unchanged ...
    let children = getChildren(element, depth: depth, deadline: deadline, nodeCount: &nodeCount, onNode: onNode)

    let node = AXNode(
        role: role, subrole: subrole, title: title, value: value,
        roleDescription: roleDescription, position: position, size: size,
        children: children, isEnabled: isEnabled, isFocused: isFocused, isSelected: isSelected
    )
    onNode?(node, depth)
    return node
}
```

Update `getChildren` to pass `onNode`:

```swift
private func getChildren(_ element: AXUIElement, depth: Int, deadline: ContinuousClock.Instant, nodeCount: inout Int, onNode: NodeCallback?) -> [AXNode] {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard result == .success, let children = value as? [AXUIElement] else { return [] }
    return children.compactMap { walkRecursive($0, depth: depth + 1, deadline: deadline, nodeCount: &nodeCount, onNode: onNode) }
}
```

Also update the include-roles branch in `walkRecursive` to pass `onNode` to `getChildren`.

- [ ] **Step 4: Create StreamFormatter**

Create `Sources/ScreenReadCore/StreamFormatter.swift`:

```swift
// Sources/ScreenReadCore/StreamFormatter.swift
import Foundation

public enum StreamFormatter {

    public static func formatNodeAsJSONL(_ node: AXNode, depth: Int) -> String {
        var dict: [String: Any] = ["role": node.role, "depth": depth]
        if let t = node.title { dict["title"] = t }
        if let v = node.value { dict["value"] = v }
        if let s = node.subrole { dict["subrole"] = s }
        if let r = node.roleDescription { dict["roleDescription"] = r }
        if let pos = node.position, let x = pos["x"], let y = pos["y"] {
            dict["x"] = Int(x)
            dict["y"] = Int(y)
        }
        if let sz = node.size, let w = sz["width"], let h = sz["height"] {
            dict["width"] = Int(w)
            dict["height"] = Int(h)
        }
        if let e = node.isEnabled { dict["isEnabled"] = e }
        if let f = node.isFocused { dict["isFocused"] = f }
        if let s = node.isSelected { dict["isSelected"] = s }

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
```

- [ ] **Step 5: Run tests**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/ScreenReadCore/AXTreeWalker.swift Sources/ScreenReadCore/StreamFormatter.swift Tests/ScreenReadCoreTests/AXTreeWalkerTests.swift
git commit -m "feat: add onNode streaming callback and JSONL StreamFormatter"
```

---

### Task 5: Add --clickable and --stream to CLI

**Files:**
- Modify: `Sources/screenread/ScreenRead.swift`

- [ ] **Step 1: Add new CLI flags**

In `Sources/screenread/ScreenRead.swift`, add the new flags after the existing filtering section:

```swift
// Modes
@Flag(name: .long, help: "Output interactive elements with click coordinates")
var clickable = false

@Flag(name: .long, help: "Stream JSONL output (one JSON object per node per line)")
var stream = false

@Flag(name: .long, help: "Watch for changes (poll-based, Ctrl+C to stop)")
var watch = false

@Option(name: .long, help: "Poll interval in seconds for --watch (default: 2)")
var interval: Int = 2
```

- [ ] **Step 2: Update run() to handle --clickable**

Add before the existing walker section, after target resolution:

```swift
// Handle --clickable
if clickable {
    let walker = AXTreeWalker(maxDepth: effectiveDepth, includeRoles: nil, excludeRoles: nil, truncateAt: full ? 0 : 500)
    let result = walker.walk(target)
    switch result {
    case .tree(let tree):
        let roles = includeRoles ?? Formatter.defaultInteractiveRoles
        if json {
            print(Formatter.formatClickableJSON(tree, roles: roles))
        } else {
            print(Formatter.formatClickable(tree, roles: roles))
        }
    case .timedOut:
        throw ScreenReadError.timeout(app ?? window ?? "app")
    case .empty:
        throw ScreenReadError.emptyTree
    }
    return
}
```

- [ ] **Step 3: Update run() to handle --stream**

Add after the --clickable section:

```swift
// Handle --stream
if stream {
    let walker = AXTreeWalker(
        maxDepth: effectiveDepth,
        includeRoles: includeRoles,
        excludeRoles: excludeRoles,
        truncateAt: full ? 0 : 500
    )
    let result = walker.walk(target) { node, depth in
        print(StreamFormatter.formatNodeAsJSONL(node, depth: depth))
        fflush(stdout)
    }
    switch result {
    case .tree: break // nodes already streamed via callback
    case .timedOut:
        fputs("error: timed out\n", stderr)
    case .empty:
        fputs("error: empty tree\n", stderr)
    }
    return
}
```

- [ ] **Step 4: Update run() to handle --watch**

Add after the --stream section:

```swift
// Handle --watch
if watch {
    let walker = AXTreeWalker(
        maxDepth: effectiveDepth,
        includeRoles: includeRoles,
        excludeRoles: excludeRoles,
        truncateAt: full ? 0 : 500
    )
    guard case .tree(var previousTree) = walker.walk(target) else {
        throw ScreenReadError.emptyTree
    }

    // Print initial snapshot
    if textOnly {
        print(Formatter.formatTextOnly(previousTree))
    } else {
        print(Formatter.formatTextTree(previousTree))
    }
    fflush(stdout)

    // Poll loop
    while true {
        Thread.sleep(forTimeInterval: Double(interval))
        let freshWalker = AXTreeWalker(
            maxDepth: effectiveDepth,
            includeRoles: includeRoles,
            excludeRoles: excludeRoles,
            truncateAt: full ? 0 : 500
        )
        guard case .tree(let newTree) = freshWalker.walk(target) else { continue }
        let changes = TreeDiffer.diff(old: previousTree, new: newTree)
        if !changes.isEmpty {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            print("\n--- \(timestamp) ---")
            for change in changes {
                print(change.formatted)
            }
            fflush(stdout)
        }
        previousTree = newTree
    }
}
```

- [ ] **Step 5: Build and test manually**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift build`
Expected: Build succeeds

Test clickable: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift run screenread --clickable --app Finder`
Expected: Table with interactive elements

Test stream: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift run screenread --stream --app Finder --depth 2`
Expected: JSONL lines to stdout

- [ ] **Step 6: Commit**

```bash
git add Sources/screenread/ScreenRead.swift
git commit -m "feat: add --clickable, --stream, --watch CLI modes"
```

---

### Task 6: Add screenread_watch and screenread_clickable MCP tools

**Files:**
- Modify: `Sources/screenread-mcp/main.swift`

- [ ] **Step 1: Add tool definitions**

In the `tools` array in `Sources/screenread-mcp/main.swift`, add after the `screenread_find_text` entry:

```swift
[
    "name": "screenread_clickable",
    "description": "List interactive elements (buttons, links, text fields) with their click coordinates. Returns a table with role, label, center x/y, and state.",
    "inputSchema": [
        "type": "object",
        "properties": [
            "app": ["type": "string", "description": "App name to read (e.g. 'Safari')"],
            "window": ["type": "string", "description": "Fuzzy match on window title"],
            "pid": ["type": "integer", "description": "Target by process ID"],
            "roles": ["type": "string", "description": "Override default interactive roles (e.g. 'AXButton,AXLink')"],
        ] as [String: Any],
        "additionalProperties": false,
    ] as [String: Any],
],
[
    "name": "screenread_watch",
    "description": "Watch an app for UI changes over a duration. Polls the accessibility tree at an interval and reports additions, removals, and value/state changes.",
    "inputSchema": [
        "type": "object",
        "properties": [
            "app": ["type": "string", "description": "App name to watch (e.g. 'Safari')"],
            "window": ["type": "string", "description": "Fuzzy match on window title"],
            "pid": ["type": "integer", "description": "Target by process ID"],
            "duration": ["type": "integer", "description": "How long to watch in seconds (default: 10, max: 60)"],
            "interval": ["type": "integer", "description": "Poll interval in seconds (default: 2, min: 1)"],
            "textOnly": ["type": "boolean", "description": "Compare text content only (default: false)"],
        ] as [String: Any],
        "additionalProperties": false,
    ] as [String: Any],
],
```

- [ ] **Step 2: Add executeClickable function**

```swift
func executeClickable(_ params: [String: AnyCodable]?) -> ToolResult {
    let resolver = TargetResolver()

    do {
        let target: AXUIElement
        if let pid = params?["pid"]?.intValue {
            guard let pid32 = Int32(exactly: pid) else {
                return ToolResult(text: "Invalid PID: \(pid)", isError: true)
            }
            target = try resolver.resolvePID(pid32)
        } else if let windowTitle = params?["window"]?.stringValue {
            target = try resolver.resolveWindow(windowTitle)
        } else if let appName = params?["app"]?.stringValue {
            target = try resolver.resolveApp(appName)
        } else {
            target = try resolver.resolveFrontmost()
        }

        let roles: Set<String>? = params?["roles"]?.stringValue.map { Set($0.split(separator: ",").map(String.init)) }

        let walker = AXTreeWalker(maxDepth: 5, includeRoles: nil, excludeRoles: nil, truncateAt: 500)
        let result = walker.walk(target)

        switch result {
        case .tree(let tree):
            return ToolResult(text: Formatter.formatClickable(tree, roles: roles), isError: false)
        case .timedOut:
            return ToolResult(text: "Timed out reading accessibility tree.", isError: true)
        case .empty:
            return ToolResult(text: "Accessibility tree is empty.", isError: true)
        }
    } catch {
        return ToolResult(text: "Error: \(error)", isError: true)
    }
}
```

- [ ] **Step 3: Add executeWatch function**

```swift
func executeWatch(_ params: [String: AnyCodable]?) -> ToolResult {
    let resolver = TargetResolver()
    let duration = min(params?["duration"]?.intValue ?? 10, 60)
    let interval = max(params?["interval"]?.intValue ?? 2, 1)
    let textOnly = params?["textOnly"]?.boolValue ?? false

    do {
        let target: AXUIElement
        let appName: String
        if let pid = params?["pid"]?.intValue {
            guard let pid32 = Int32(exactly: pid) else {
                return ToolResult(text: "Invalid PID: \(pid)", isError: true)
            }
            target = try resolver.resolvePID(pid32)
            appName = "PID \(pid)"
        } else if let windowTitle = params?["window"]?.stringValue {
            target = try resolver.resolveWindow(windowTitle)
            appName = windowTitle
        } else if let name = params?["app"]?.stringValue {
            target = try resolver.resolveApp(name)
            appName = name
        } else {
            target = try resolver.resolveFrontmost()
            appName = "frontmost"
        }

        let makeWalker = {
            AXTreeWalker(maxDepth: 5, includeRoles: nil, excludeRoles: nil, truncateAt: textOnly ? 0 : 500)
        }

        guard case .tree(var previousTree) = makeWalker().walk(target) else {
            return ToolResult(text: "Could not read initial tree.", isError: true)
        }

        var allChanges: [(Int, [TreeChange])] = []
        let startTime = ContinuousClock.now
        var polls = 0

        while true {
            Thread.sleep(forTimeInterval: Double(interval))
            polls += 1
            let elapsed = Int((ContinuousClock.now - startTime) / .seconds(1))
            if elapsed >= duration { break }

            guard case .tree(let newTree) = makeWalker().walk(target) else { continue }
            let changes = TreeDiffer.diff(old: previousTree, new: newTree)
            if !changes.isEmpty {
                allChanges.append((elapsed, changes))
            }
            previousTree = newTree
        }

        if allChanges.isEmpty {
            return ToolResult(text: "No changes detected in \(appName) over \(duration)s (\(polls) polls)", isError: false)
        }

        var lines = ["Watched \(appName) for \(duration)s (\(polls) polls, \(allChanges.count) change(s) detected)", ""]
        for (elapsed, changes) in allChanges {
            lines.append("--- +\(elapsed)s ---")
            for change in changes {
                lines.append(change.formatted)
            }
            lines.append("")
        }
        return ToolResult(text: lines.joined(separator: "\n"), isError: false)
    } catch {
        return ToolResult(text: "Error: \(error)", isError: true)
    }
}
```

- [ ] **Step 4: Add dispatch cases**

In the `tools/call` switch statement, add:

```swift
case "screenread_clickable":
    let result = executeClickable(argsDict)
    sendToolResult(request.id, text: result.text, isError: result.isError)
case "screenread_watch":
    let result = executeWatch(argsDict)
    sendToolResult(request.id, text: result.text, isError: result.isError)
```

- [ ] **Step 5: Build**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift build`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/screenread-mcp/main.swift
git commit -m "feat: add screenread_clickable and screenread_watch MCP tools"
```

---

### Task 7: Version bump and README update

**Files:**
- Modify: `Sources/screenread/ScreenRead.swift`
- Modify: `Sources/screenread-mcp/main.swift`
- Modify: `README.md`

- [ ] **Step 1: Bump version strings**

In `Sources/screenread/ScreenRead.swift`, change `version: "0.1.0"` to `version: "0.2.0"`.

In `Sources/screenread-mcp/main.swift`, in the `initialize` response, change `"version": "0.1.0"` to `"version": "0.2.0"`.

- [ ] **Step 2: Update README with new features**

Add the following sections to `README.md` in the CLI usage section, after the existing examples:

```markdown
# Watch for UI changes (poll every 2s, Ctrl+C to stop)
screenread --watch --app Safari
screenread --watch --app Safari --interval 5

# List interactive elements with click coordinates
screenread --clickable --app Safari
screenread --clickable --app Finder --json

# Stream JSONL (one JSON object per node per line)
screenread --stream --app Safari
screenread --stream --app Safari | jq 'select(.role == "AXButton")'
```

Add `screenread_clickable` and `screenread_watch` to the MCP tools section with their parameter tables matching the spec.

Update the architecture tree to include the new files:
```
│   │   ├── TreeDiffer.swift          # Compare two tree snapshots
│   │   ├── StreamFormatter.swift     # JSONL single-node encoder
```

Update test count from 14 to the new total.

- [ ] **Step 3: Build and run full test suite**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/screenread/ScreenRead.swift Sources/screenread-mcp/main.swift README.md
git commit -m "chore: bump version to 0.2.0, update README with new features"
```

---

### Task 8: Final integration test

**Files:** None (manual testing only)

- [ ] **Step 1: Test clickable via CLI**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift run screenread --clickable --app Finder`
Expected: TSV table with buttons/menus and coordinates

- [ ] **Step 2: Test stream via CLI**

Run: `SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift run screenread --stream --app Finder --depth 2 | head -10`
Expected: JSONL lines with role, depth, and other fields

- [ ] **Step 3: Test watch briefly**

Run: `timeout 5 swift run screenread --watch --app Finder --interval 1 2>&1 || true`
Expected: Initial tree snapshot printed, then exits after 5s

- [ ] **Step 4: Install updated binaries**

```bash
SWIFT_EXEC="$HOME/.swift-sdk-patch-6.2.4/swiftc-wrapper.sh" swift build -c release
cp .build/release/screenread ~/.local/bin/
cp .build/release/screenread-mcp ~/.local/bin/
```

- [ ] **Step 5: Verify MCP tools load**

Restart Claude Code or the MCP client. Verify `screenread_clickable` and `screenread_watch` appear in the tool list.
