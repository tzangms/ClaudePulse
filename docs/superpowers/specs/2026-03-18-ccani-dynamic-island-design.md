# ccani — Claude Code Dynamic Island for macOS

## Overview

A native macOS Swift app that displays a floating Dynamic Island-style capsule showing Claude Code's real-time status. The capsule hovers at the top of the screen, shows the current state and session duration, and expands on click to reveal more details. Supports monitoring multiple concurrent Claude Code sessions.

## Architecture

### Data Flow

```
Claude Code hooks → HTTP POST or command+curl → ccani HTTP server (localhost:19280) → UI update
```

Not all Claude Code hook events support HTTP type. Events that only support command hooks use a `curl` command to forward the JSON payload to the same HTTP endpoint.

### Components

1. **Embedded HTTP Server** — Listens on `localhost:19280`, receives all hook events via POST to `/hook`
2. **Session Manager** — Manages multiple session states keyed by `session_id`, each with an independent state machine
3. **Dynamic Island UI** — Floating capsule window (NSPanel, `.floating` level) at the top of the screen

### State Machine (per session)

```
idle → thinking → tool_executing → waiting_for_user → idle
         ↑              |
         └──────────────┘
```

| State              | Trigger                                                    |
|--------------------|------------------------------------------------------------|
| `idle`             | `Stop` event                                               |
| `thinking`         | `UserPromptSubmit` event                                   |
| `tool_executing`   | `PreToolUse` event                                         |
| `waiting_for_user` | `PermissionRequest` event                                  |

Transitions back to `thinking` occur on `PostToolUse` or `PostToolUseFailure` (Claude may chain multiple tool calls, and failed tools should not leave the UI stuck).

### Hook Events Monitored

| Event                | Hook Type | Action                             |
|----------------------|-----------|------------------------------------|
| `SessionStart`       | command   | Create new session, start timer    |
| `UserPromptSubmit`   | http      | State → `thinking`                 |
| `PreToolUse`         | http      | State → `tool_executing`           |
| `PostToolUse`        | http      | State → `thinking`                 |
| `PostToolUseFailure` | http      | State → `thinking`                 |
| `PermissionRequest`  | http      | State → `waiting_for_user`         |
| `Stop`               | http      | State → `idle`                     |
| `SessionEnd`         | command   | Remove session, stop timer         |

All events ultimately POST JSON to `http://localhost:19280/hook`. The app routes internally based on `hook_event_name` in the JSON payload.

### Session Routing

Each hook event payload contains a `session_id` field. The Session Manager uses this to route events to the correct session object. Unknown `session_id` values from non-`SessionStart` events create a new session implicitly (handles the case where the app starts after Claude Code is already running).

### Staleness Handling

If no event is received for a session within 10 minutes, the session is marked as `stale`. Stale sessions show a dimmed indicator in the UI. After 30 minutes of no events, stale sessions are automatically removed.

## UI Design

### Capsule (Collapsed)

- **Position:** Top-center of screen, below menu bar
- **Size:** ~200x36pt, pill-shaped with full corner radius
- **Content:** Status indicator dot (left) + status text + session timer (right)
- **Multi-session:** Shows the active session; small dots at edges indicate other sessions

### Status Indicator Colors

| State              | Color   | Animation          |
|--------------------|---------|--------------------|
| `idle`             | Gray    | None               |
| `thinking`         | Purple  | Breathing pulse    |
| `tool_executing`   | Blue    | Pulse animation    |
| `waiting_for_user` | Orange  | Blinking           |
| `stale`            | Gray    | None (dimmed)      |

### Expanded State (Click to expand)

- Capsule expands downward to rounded card (dynamic height based on content)
- Shows:
  - Current state (larger font)
  - Session timer (live-updating)
  - Session list (if multiple sessions), clickable to switch; scrollable if many sessions
- Collapse: click outside or click capsule again
- Animation: SwiftUI spring animation

### Visual Style

- Always dark background (matching iPhone Dynamic Island metaphor)
- NSVisualEffectView with `.dark` appearance and vibrancy material
- White text
- Does not change with system light/dark mode

## Technical Implementation

### Swift Stack

- **UI:** SwiftUI + NSPanel
- **HTTP Server:** Swift NIO or Apple's `NWListener` (fully native, no third-party dependency)
- **Minimum OS:** macOS 14 (Sonoma)

### NSPanel Configuration

```swift
panel.styleMask = [.nonactivatingPanel]
panel.isMovableByWindowBackground = true
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.level = .floating
```

Key behaviors:
- Does not steal focus from other apps
- Draggable by background
- Visible on all desktops/spaces
- Stays visible when app is not frontmost

### Port Binding

The app binds to `localhost:19280`. On startup:
1. Attempt to bind to port 19280
2. If port is in use, check if another ccani instance is running — if so, bring it to front and exit
3. If port is occupied by something else, try ports 19281–19289
4. Store the active port in `~/.ccani/port` so hooks scripts can read it

### Hooks Auto-Configuration

On first launch, the app checks `~/.claude/settings.json`. If ccani hooks are not present, it prompts the user with a one-click setup.

**Hook types by event support:**

- Events supporting HTTP: use `"type": "http"` directly
- Events supporting only command: use `"type": "command"` with curl

```json
{
  "hooks": {
    "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "curl -sf -X POST -H 'Content-Type: application/json' -d \"$(cat)\" http://localhost:$(cat ~/.ccani/port 2>/dev/null || echo 19280)/hook || true"}]}],
    "SessionEnd": [{"matcher": "", "hooks": [{"type": "command", "command": "curl -sf -X POST -H 'Content-Type: application/json' -d \"$(cat)\" http://localhost:$(cat ~/.ccani/port 2>/dev/null || echo 19280)/hook || true"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "http", "url": "http://localhost:19280/hook"}]}],
    "PreToolUse": [{"matcher": "", "hooks": [{"type": "http", "url": "http://localhost:19280/hook"}]}],
    "PostToolUse": [{"matcher": "", "hooks": [{"type": "http", "url": "http://localhost:19280/hook"}]}],
    "PostToolUseFailure": [{"matcher": "", "hooks": [{"type": "http", "url": "http://localhost:19280/hook"}]}],
    "PermissionRequest": [{"matcher": "", "hooks": [{"type": "http", "url": "http://localhost:19280/hook"}]}],
    "Stop": [{"matcher": "", "hooks": [{"type": "http", "url": "http://localhost:19280/hook"}]}]
  }
}
```

**Merge strategy:**
1. Read existing `~/.claude/settings.json` (create if not exists)
2. Parse as JSON (fail gracefully if malformed, ask user to fix manually)
3. For each hook event, append ccani's hook entry to the existing array (do not replace)
4. Before appending, check if a ccani hook already exists (match by URL containing `19280`) to avoid duplicates
5. Write back with pretty-print formatting

### Session Timer

- Starts on `SessionStart` event (or on first event if session was created implicitly)
- UI updates every second via SwiftUI `TimelineView`
- Stops on `SessionEnd`
- Format: `MM:SS` (or `H:MM:SS` if over an hour)

## Project Structure

```
ccani/
├── ccani.xcodeproj
├── ccani/
│   ├── ccaniApp.swift              # App entry point
│   ├── Server/
│   │   └── HookServer.swift        # Embedded HTTP server (NWListener)
│   ├── Models/
│   │   ├── Session.swift           # Session model & state machine
│   │   └── HookEvent.swift         # Hook event parsing
│   ├── Managers/
│   │   └── SessionManager.swift    # Multi-session management, staleness
│   ├── Views/
│   │   ├── DynamicIslandPanel.swift # NSPanel wrapper
│   │   ├── CapsuleView.swift       # Collapsed capsule UI
│   │   └── ExpandedView.swift      # Expanded card UI
│   └── Setup/
│       └── HooksConfigurator.swift  # Auto-configure Claude Code hooks
└── ccani.entitlements               # Network server entitlement
```

## Out of Scope (for MVP)

- Tool name / parameter display
- Token usage / cost tracking
- Operation history
- Menu bar icon (may add later)
- Preferences window (may add later)
- Launch at login (may add later)
- Accessibility (VoiceOver, keyboard nav) — will add post-MVP
