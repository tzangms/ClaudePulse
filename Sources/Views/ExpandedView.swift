import SwiftUI

struct ExpandedView: View {
    let session: Session?
    let sessions: [Session]
    let onSelectSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if let session = session {
                HStack {
                    Text("Session")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(session.formattedTime)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }

                if let cwd = session.cwd {
                    Text(shortPath(cwd))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            if sessions.count > 1 {
                Divider().background(.white.opacity(0.2))

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(sessions) { s in
                            SessionRow(session: s, isActive: s.id == session?.id)
                                .onTapGesture { onSelectSession(s.id) }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(16)
        .frame(width: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
    }

    private var statusColor: Color {
        switch session?.state ?? .idle {
        case .idle: return .gray
        case .thinking: return .purple
        case .toolExecuting: return .blue
        case .waitingForUser: return .orange
        case .stale: return .gray.opacity(0.5)
        }
    }

    private var statusText: String {
        switch session?.state ?? .idle {
        case .idle: return "Idle"
        case .thinking: return "Thinking..."
        case .toolExecuting: return "Executing..."
        case .waitingForUser: return "Waiting for Input"
        case .stale: return "Stale"
        }
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

struct SessionRow: View {
    let session: Session
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? .white : .white.opacity(0.3))
                .frame(width: 5, height: 5)
            Text(session.cwd.map { ($0 as NSString).lastPathComponent } ?? String(session.id.prefix(8)))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.6))
                .lineLimit(1)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(session.formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 2)
    }
}
