# Pulse for Claude Code

A macOS menu bar app that brings **Dynamic Island-inspired** real-time monitoring to your Claude Code sessions.

<video src="https://github.com/user-attachments/assets/placeholder" width="100%" autoplay loop muted></video>

> **Note:** Replace the video above — drag `docs/video.mp4` into this README on GitHub to auto-upload.

## Features

- **Dynamic Island Style** — A compact capsule UI floats above your screen, expanding on hover to show full session details
- **Real-time Session Tracking** — Monitor multiple Claude Code sessions simultaneously with working, waiting, or idle status
- **Elegant Animations** — Smooth expand/collapse, pulse effects on state changes, and frosted glass materials
- **Fully Local** — All data stays on localhost via Claude Code hooks. Nothing leaves your machine
- **Menu Bar Integration** — Quick controls from the system menu bar: show/hide, pin expanded view, adjust position
- **Zero Configuration** — Automatically sets up Claude Code hooks on first launch

## Session States

| State | Description |
|-------|-------------|
| **Working** | Claude is processing |
| **Waiting** | Waiting for user input or approval |
| **Idle** | Session is idle |
| **Stale** | No activity for over 10 minutes |

## Install

Download the latest DMG from [Releases](https://github.com/tzangms/ClaudePulse/releases/latest).

### Build from Source

```bash
git clone https://github.com/tzangms/ClaudePulse.git
cd ClaudePulse
swift build -c release
```

## Tech Stack

- Swift 5.10+ / SwiftUI / AppKit
- POSIX Sockets
- macOS 14+
- Swift Package Manager

## License

MIT

## Author

Built by [@tzangms](https://github.com/tzangms)
