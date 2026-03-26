<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/logo.svg">
    <img alt="ScreenRead" src="assets/logo-dark.svg" width="400">
  </picture>
</p>

<p align="center">
  Read what's on screen without taking a screenshot.
</p>

ScreenRead gives AI agents access to the macOS accessibility tree — the same structured data that powers VoiceOver and other screen readers. Instead of capturing pixels and feeding them through vision models, your agent gets instant, structured text describing every UI element on screen.

**~100ms** instead of 1-3 seconds. **Zero hallucination** — it reads what the OS knows, not what a model thinks it sees.

## Why

Most AI agent tooling uses screenshots to "see" the screen:

1. Capture PNG (~200ms)
2. Base64 encode and transfer (~500KB-2MB)
3. Vision model processes pixels (expensive, slow)
4. Model describes what it *thinks* it sees (sometimes wrong)

But ~90% of agent tasks are text-based: "what does the error say?", "is this button visible?", "what's the page title?". Screenshots are overkill.

ScreenRead skips all of that. It asks macOS directly: "What UI elements exist in this window?" and returns structured text instantly.

## Install

### Build from source

```bash
git clone https://github.com/Bambushu/screenread.git
cd screenread
swift build -c release
cp .build/release/screenread ~/.local/bin/
cp .build/release/screenread-mcp ~/.local/bin/
```

### Requirements

- macOS 13+ (Ventura or later)
- Accessibility permission (System Settings > Privacy & Security > Accessibility)

## Usage

### CLI

```bash
# Read the frontmost app
screenread

# Read a specific app
screenread --app Safari

# Fuzzy match a window title
screenread --window "inbox"

# Text only (no structure)
screenread --app Warp --text-only

# Shallow read (depth 2)
screenread --app Finder --shallow

# Full text, no truncation
screenread --app Terminal --full

# JSON output
screenread --app Safari --json

# Search for text across all open windows
screenread --find "error"
screenread --find "Submit"

# List all open windows
screenread --list

# Filter by role
screenread --app Safari --role AXButton,AXLink

# Exclude roles
screenread --app Safari --ignore AXGroup,AXScrollArea

# List interactive elements with click coordinates
screenread --clickable --app Safari
screenread --clickable --app Finder --json

# Watch for UI changes (poll every 2s, Ctrl+C to stop)
screenread --watch --app Safari
screenread --watch --app Safari --interval 5

# Stream JSONL (one JSON object per node per line)
screenread --stream --app Safari
screenread --stream --app Safari | jq 'select(.role == "AXButton")'
```

### MCP Server

Add to your MCP config:

**Claude Code** (project-scoped `.mcp.json` in your project root):

```json
{
  "mcpServers": {
    "screenread": {
      "command": "screenread-mcp"
    }
  }
}
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "screenread": {
      "command": "/path/to/screenread-mcp"
    }
  }
}
```

This exposes five tools to any MCP-compatible client:

#### `screenread_snapshot`

Read the accessibility tree of a specific app or window. With no parameters, reads the frontmost (active) app.

| Parameter  | Type    | Description                              |
|-----------|---------|------------------------------------------|
| `app`     | string  | App name (e.g. `"Safari"`)               |
| `window`  | string  | Fuzzy match on window title              |
| `pid`     | integer | Target by process ID                     |
| `depth`   | integer | Max tree depth (default: 5). Use 0 for unlimited — may be slow on large apps. |
| `textOnly`| boolean | Text only, no structure                  |
| `roles`   | string  | Comma-separated AX roles to include (e.g. `"AXButton,AXLink"`) |
| `ignore`  | string  | Comma-separated AX roles to exclude (e.g. `"AXGroup,AXScrollArea"`) |

#### `screenread_list`

List all open windows. Returns one line per window in the format: `AppName [PID] — Window Title`. No parameters.

#### `screenread_find_text`

Search for visible text across all open windows. Plain substring match (no regex).

| Parameter       | Type    | Description                    |
|----------------|---------|--------------------------------|
| `query`        | string  | Plain text substring to search for (required) |
| `caseSensitive`| boolean | Case-sensitive (default: false) |

Results are capped at 100 matches. Use `screenread_snapshot` with a specific app for more targeted results.

#### `screenread_clickable`

List interactive elements (buttons, links, text fields) with their click coordinates.

| Parameter | Type    | Description                                    |
|----------|---------|------------------------------------------------|
| `app`    | string  | App name (e.g. `"Safari"`)                     |
| `window` | string  | Fuzzy match on window title                    |
| `pid`    | integer | Target by process ID                           |
| `roles`  | string  | Override default interactive roles (e.g. `"AXButton,AXLink"`) |

Returns a table with role, label, center x/y coordinates, and state (enabled/disabled/focused/selected).

#### `screenread_watch`

Watch an app for UI changes over a duration.

| Parameter  | Type    | Description                                    |
|-----------|---------|------------------------------------------------|
| `app`     | string  | App name (e.g. `"Safari"`)                     |
| `window`  | string  | Fuzzy match on window title                    |
| `pid`     | integer | Target by process ID                           |
| `duration`| integer | How long to watch in seconds (default: 10, max: 60) |
| `interval`| integer | Poll interval in seconds (default: 2, min: 1)  |
| `textOnly`| boolean | Compare text content only (default: false)      |

Polls the accessibility tree at the given interval and reports additions, removals, and value/state changes.

## Architecture

```
screenread/
├── Sources/
│   ├── ScreenReadCore/     # Shared library
│   │   ├── AXHelpers.swift       # Shared AX attribute accessors
│   │   ├── AXTreeWalker.swift    # Recursive accessibility tree traversal + streaming callback
│   │   ├── Formatter.swift       # Text tree, text-only, JSON, clickable output
│   │   ├── StreamFormatter.swift # JSONL single-node encoder
│   │   ├── TargetResolver.swift  # App/window/PID resolution with fuzzy matching
│   │   ├── TreeDiffer.swift      # Compare two tree snapshots for changes
│   │   └── Types.swift           # AXNode, WalkResult, WindowInfo, errors
│   ├── screenread/         # CLI (uses ArgumentParser)
│   └── screenread-mcp/     # MCP server (JSON-RPC over stdio)
└── Tests/
    └── ScreenReadCoreTests/  # 27 tests across 4 suites
```

The core library (`ScreenReadCore`) does all the work. Both the CLI and MCP server are thin wrappers around it.

## Screenshots vs ScreenRead

| | Screenshots | ScreenRead |
|---|---|---|
| **Speed** | 1-3 seconds | ~100ms |
| **Token cost** | High (vision model) | Low (text) |
| **Accuracy** | Can hallucinate text | Exact (reads from OS) |
| **Scope** | Web only (Playwright) or full screen | Any macOS app |
| **Good for** | Visual checks (layout, colors) | Content verification, UI state |

Use ScreenRead for the 90% of tasks that are about content and structure. Keep screenshots for the 10% that need pixels.

## Platform

macOS only. ScreenRead uses Apple's `AXUIElement` accessibility API, which has no equivalent on other platforms. Linux would need AT-SPI, Windows needs UI Automation — fundamentally different APIs.

## License

MIT
