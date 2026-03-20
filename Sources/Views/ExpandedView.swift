import SwiftUI

struct ExpandedDetailView: View {
    let session: Session?
    let sessions: [Session]
    let onSelectSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sessions) { s in
                SessionRow(session: s, isSelected: s.id == session?.id)
                    .onTapGesture { onSelectSession(s.id) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 280)
    }
}

struct SessionRow: View {
    let session: Session
    var isSelected: Bool = false

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(rowStateColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(session.projectName)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.6))
                        .lineLimit(1)
                    if !rowStateLabel.isEmpty {
                        Text(rowStateLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(rowStateColor.opacity(0.7))
                    }
                }
                if let prompt = session.lastPrompt {
                    Text(prompt)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            if session.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(session.formattedTime)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            isSelected ? .white.opacity(0.08) : (isHovered ? .white.opacity(0.05) : .clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var rowStateColor: Color {
        switch session.state {
        case .idle: return .gray
        case .working: return Color(red: 0.7, green: 0.4, blue: 1.0)
        case .waitingForUser: return .orange
        case .stale: return .gray.opacity(0.5)
        }
    }

    private var rowStateLabel: String {
        switch session.state {
        case .idle: return ""
        case .working: return "working"
        case .waitingForUser: return "waiting"
        case .stale: return "stale"
        }
    }
}
