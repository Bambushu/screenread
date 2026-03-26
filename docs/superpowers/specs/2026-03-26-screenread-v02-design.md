# ScreenRead v0.2 Design Spec — Watch, State, Clickable, Stream

**Date:** 2026-03-26
**Status:** Approved
**Scope:** 4 new features for open-source launch

---

## Overview

ScreenRead v0.1 reads the macOS accessibility tree. v0.2 makes it actionable: detect changes over time, expose element state, output click coordinates, and stream results for piping.

## Feature 5: Watch Mode (poll-based)

### CLI

```bash
screenread --watch --app Safari                  # default: 2s interval
screenread --watch --app Safari --interval 5     # custom interval
screenread --watch --text-only --interval 1      # text-only, 1s polls
```

- First read: outputs the full tree (respects --text-only, --json, --depth, etc.)
- Subsequent reads: compares against previous snapshot
- Only outputs when something changes — prints a timestamp header + changes
- Ctrl+C to stop
- Change output format:
  ```
  --- 2026-03-26T14:32:05 ---
  + [button] Submit (new)
  - [statictext] Loading... (removed)
  ~ [textfield] Search: "" → "hello" (changed)
  ```

### MCP: `screenread_watch`

| Parameter  | Type    | Description                                    |
|-----------|---------|------------------------------------------------|
| `app`     | string  | App name (same targeting as snapshot)           |
| `window`  | string  | Fuzzy match on window title                    |
| `pid`     | integer | Target by process ID                           |
| `duration`| integer | How long to watch in seconds (default: 10, max: 60) |
| `interval`| integer | Poll interval in seconds (default: 2, min: 1)  |
| `textOnly`| boolean | Compare text content only (default: false)      |

Returns a summary of all changes detected during the watch period. Does NOT stream — collects changes and returns them all at once when duration expires.

Response format:
```
Watched Safari for 10s (5 polls, 2 changes detected)

--- +2s ---
+ [button] Submit
~ [textfield] Search: "" → "hello"

--- +6s ---
- [statictext] Loading...
+ [statictext] Results: 42 items
```

If no changes detected: `"No changes detected in Safari over 10s (5 polls)"`

### Core: TreeDiffer

New file: `Sources/ScreenReadCore/TreeDiffer.swift`

```swift
public enum TreeChange: Sendable {
    case added(path: String, node: AXNode)
    case removed(path: String, node: AXNode)
    case changed(path: String, old: AXNode, new: AXNode, field: String)
}

public enum TreeDiffer {
    public static func diff(old: AXNode, new: AXNode) -> [TreeChange]
}
```

Comparison strategy:
- Match nodes by `role + title + sibling index` path from root (e.g., `AXWindow/AXGroup:Navigation/AXButton:Home[0]`)
- Sibling index disambiguates when multiple siblings share the same role+title (e.g., two "OK" buttons)
- If a path exists in old but not new: `removed`
- If a path exists in new but not old: `added`
- If a path exists in both but title, value, isEnabled, isFocused, or isSelected changed: `changed`
- Ignore position/size changes (layout shifts are noisy and rarely meaningful)

---

## Feature 6: Element State Metadata

### New AXNode fields

```swift
public struct AXNode: Sendable, Codable {
    // ... existing fields ...
    public let isEnabled: Bool?
    public let isFocused: Bool?
    public let isSelected: Bool?
}
```

### AX API sources

| Field       | AX Attribute            |
|------------|-------------------------|
| isEnabled  | `kAXEnabledAttribute`   |
| isFocused  | `kAXFocusedAttribute`   |
| isSelected | `kAXSelectedAttribute`  |

Collected via `getBoolAttribute` (already exists in AXTreeWalker). Added to `buildNode`.

### Output changes

**Text tree** — state flags appended in parentheses:
```
[button] Submit (disabled)
[textfield] Search (focused)
[checkbox] Remember me (selected)
[button] Cancel
```
Only non-default states shown: `disabled`, `focused`, `selected`. Enabled + unfocused + unselected = no annotation.

**JSON** — three new optional fields in the node object. Null when not applicable (e.g., a static text element has no `isEnabled`).

**Text-only** — no change. State isn't readable text content.

### Always collected

The 3 extra `AXUIElementCopyAttributeValue` calls per node add negligible overhead (~10%). The data is valuable for TreeDiffer (watch mode detects state changes) and for clickable output.

---

## Feature 7: Clickable Coordinates

### CLI

```bash
screenread --clickable --app Safari
screenread --clickable --window "inbox"
screenread --clickable --app Finder --json    # JSON array output
```

### Output format (default: TSV-style table)

```
ROLE          LABEL              X,Y        STATE
AXButton      Submit             450,320    enabled
AXLink        Home               120,85     enabled
AXTextField   Search             300,45     focused
AXButton      Delete             680,320    disabled
AXCheckBox    Remember me        140,400    selected
```

- Coordinates are **center-point**: `position.x + size.width/2`, `position.y + size.height/2`
- Rounded to integers
- Only interactive elements included

### JSON output (with `--json`)

```json
[
  {"role": "AXButton", "label": "Submit", "x": 450, "y": 320, "state": "enabled"},
  {"role": "AXLink", "label": "Home", "x": 120, "y": 85, "state": "enabled"}
]
```

### Interactive role filter

Default interactive roles:
```
AXButton, AXLink, AXTextField, AXTextArea, AXCheckBox,
AXRadioButton, AXPopUpButton, AXSlider, AXMenuItem,
AXTab, AXComboBox, AXIncrementor
```

Overridable with `--roles AXButton,AXLink` (same flag as existing role filter).

### MCP: `screenread_clickable`

| Parameter | Type    | Description                                    |
|----------|---------|------------------------------------------------|
| `app`    | string  | App name                                       |
| `window` | string  | Fuzzy match on window title                    |
| `pid`    | integer | Target by process ID                           |
| `roles`  | string  | Override interactive role filter                |

Returns the TSV table as text content. Agents can parse the coordinates directly.

### Core: Formatter addition

```swift
public static func formatClickable(_ node: AXNode) -> String
public static func formatClickableJSON(_ node: AXNode) -> String
```

Walks the tree, collects nodes matching interactive roles that have position+size, calculates center coordinates, formats as table or JSON array.

---

## Feature 8: CLI Streaming (JSONL)

### CLI

```bash
screenread --stream --app Safari
screenread --stream --app Safari | jq 'select(.role == "AXButton")'
screenread --stream --window "inbox" | grep "error"
```

### Output format: JSON Lines

One JSON object per node, one per line, emitted as the tree is walked:

```jsonl
{"role":"AXWindow","title":"Safari","depth":0}
{"role":"AXGroup","title":"Navigation","depth":1}
{"role":"AXButton","title":"Back","depth":2,"x":45,"y":12,"isEnabled":true}
{"role":"AXLink","title":"Home","depth":2,"x":120,"y":12,"isEnabled":true}
{"role":"AXStaticText","value":"Welcome","depth":2}
```

Fields per line:
- `role` (always)
- `title`, `value`, `subrole`, `roleDescription` (when non-null)
- `depth` (integer, tree depth from root — allows consumers to reconstruct hierarchy)
- `x`, `y`, `width`, `height` (when position+size available, as integers)
- `isEnabled`, `isFocused`, `isSelected` (when applicable)

### Implementation: onNode callback

Add an optional callback to AXTreeWalker:

```swift
public typealias NodeCallback = (AXNode, Int) -> Void  // node, depth

public func walk(_ element: AXUIElement, onNode: NodeCallback? = nil) -> WalkResult
```

When `onNode` is provided:
- Called for each node as it's visited (before walking children)
- The tree is still built and returned as normal
- The CLI's `--stream` mode sets `onNode` to a closure that JSON-encodes and prints each node

This keeps the walker's core logic unchanged — streaming is an additive behavior.

### MCP: Not applicable

MCP stays request/response. Streaming is CLI-only. The existing snapshot/clickable tools serve MCP clients.

---

## Architecture Changes

### New files

| File | Purpose |
|------|---------|
| `Sources/ScreenReadCore/TreeDiffer.swift` | Diff two AXNode trees, return list of changes |
| `Sources/ScreenReadCore/StreamFormatter.swift` | JSONL single-node encoder |

### Modified files

| File | Changes |
|------|---------|
| `Types.swift` | AXNode gets `isEnabled`, `isFocused`, `isSelected` |
| `AXTreeWalker.swift` | Collect state attrs in `buildNode`, add `onNode` callback to `walk()` |
| `Formatter.swift` | Add state flags to text tree, add `formatClickable`/`formatClickableJSON` |
| `ScreenRead.swift` (CLI) | Add `--watch`, `--clickable`, `--stream`, `--interval` flags |
| `main.swift` (MCP) | Add `screenread_watch` and `screenread_clickable` tools |

### Unchanged files

| File | Why unchanged |
|------|---------------|
| `AXHelpers.swift` | No new shared helpers needed |
| `TargetResolver.swift` | Targeting logic unchanged |

---

## Testing Plan

### TreeDiffer (unit, synthetic trees)
- Two identical trees → empty diff
- Node added → reports `added`
- Node removed → reports `removed`
- Title changed → reports `changed` with field "title"
- Value changed → reports `changed` with field "value"
- State changed (enabled→disabled) → reports `changed` with field "isEnabled"
- Position-only change → no diff (intentionally ignored)

### State Metadata (extends existing walker tests)
- Walk Finder → at least one node has isEnabled = true
- Walk frontmost → buttons have isEnabled field
- Text tree output contains "(disabled)" for disabled elements (if any found)

### Clickable (unit + integration)
- Unit: center-point calculation from position+size
- Unit: interactive role filtering (only expected roles pass)
- Integration: `--clickable --app Finder` returns at least one line with coordinates

### Stream (integration)
- `--stream --app Finder` outputs at least one line
- Each line is valid JSON
- Each line has `role` and `depth` fields
- Lines are emitted in depth-first order

### Watch (integration)
- MCP `screenread_watch` with 3s duration returns a response (even if no changes)
- CLI `--watch --interval 1` outputs at least the initial snapshot before Ctrl+C

---

## Version

These features ship as ScreenRead v0.2.0. Update version strings in:
- `ScreenRead.swift` (CLI `version:`)
- `main.swift` (MCP `serverInfo`)
