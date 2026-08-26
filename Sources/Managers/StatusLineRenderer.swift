import Foundation

/// Builds the text Claude Code prints as the status line.
///
/// Pulse owns the status line slot, so it has to put something useful there.
/// The line is rendered here rather than in the installed shell script: the
/// script only forwards the payload and prints the reply, which keeps the
/// formatting in Swift where it can be changed and tested.
enum StatusLineRenderer {

    static func render(_ payload: StatusLinePayload) -> String {
        var parts: [String] = []

        if let model = payload.model?.displayName, !model.isEmpty {
            parts.append(model)
        }
        if let context = payload.context {
            parts.append("\(context.percentText) ctx")
        }
        if let usage = payload.usage {
            if let five = usage.fiveHour { parts.append("5h \(five.percentText)") }
            if let week = usage.sevenDay { parts.append("wk \(week.percentText)") }
        }
        return parts.joined(separator: " · ")
    }
}
