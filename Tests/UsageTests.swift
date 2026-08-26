import XCTest
@testable import ccpulse

final class ContextUsageReaderTests: XCTestCase {

    private var file: URL!

    override func setUpWithError() throws {
        file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulse-transcript-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func assistantLine(input: Int, cacheCreation: Int, cacheRead: Int, model: String) -> String {
        """
        {"type":"assistant","message":{"model":"\(model)","usage":{"input_tokens":\(input),\
        "cache_creation_input_tokens":\(cacheCreation),"cache_read_input_tokens":\(cacheRead),\
        "output_tokens":100}}}
        """
    }

    /// Every request re-sends the conversation, so the newest assistant turn
    /// describes the window as it stands.
    func testUsesTheLastAssistantTurn() throws {
        let lines = [
            assistantLine(input: 5, cacheCreation: 0, cacheRead: 10_000, model: "claude-opus-5"),
            #"{"type":"user","message":{"content":"hi"}}"#,
            assistantLine(input: 2, cacheCreation: 440, cacheRead: 30_000, model: "claude-opus-5"),
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let window = ContextUsageReader.read(transcriptPath: file.path)
        XCTAssertEqual(window?.usedTokens, 2 + 440 + 30_000)
    }

    /// A compaction shrinks the context; the ring has to fall with it.
    func testFollowsUsageBackDownAfterCompaction() throws {
        let lines = [
            assistantLine(input: 1, cacheCreation: 0, cacheRead: 150_000, model: "claude-sonnet-4-5"),
            assistantLine(input: 1, cacheCreation: 0, cacheRead: 20_000, model: "claude-sonnet-4-5"),
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(ContextUsageReader.read(transcriptPath: file.path)?.usedTokens, 20_001)
    }

    /// Only the tail is read, so the first line of the window is usually a
    /// fragment and must not derail the scan.
    func testReadsTheTailOfALargeTranscript() throws {
        var text = ""
        let filler = String(repeating: "x", count: 4_000)
        for index in 0..<400 {
            text += #"{"type":"user","message":{"content":"\#(filler)-\#(index)"}}"# + "\n"
        }
        text += assistantLine(input: 3, cacheCreation: 0, cacheRead: 12_345, model: "claude-opus-5") + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)

        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
        XCTAssertGreaterThan(size ?? 0, ContextUsageReader.tailBytes)
        XCTAssertEqual(ContextUsageReader.read(transcriptPath: file.path)?.usedTokens, 12_348)
    }

    func testMissingTranscriptIsNotAnError() {
        XCTAssertNil(ContextUsageReader.read(transcriptPath: "/nope/missing.jsonl"))
    }

    func testWindowSizeFromModel() {
        XCTAssertEqual(ContextUsageReader.windowSize(model: "claude-opus-5", used: 1_000), 1_000_000)
        XCTAssertEqual(ContextUsageReader.windowSize(model: "claude-sonnet-4-5", used: 1_000), 200_000)
        XCTAssertEqual(ContextUsageReader.windowSize(model: nil, used: 1_000), 200_000)
    }

    /// A reading past the standard window proves the window is the larger one,
    /// whatever the model table says.
    func testUsageBeyondStandardWindowImpliesTheLargeWindow() {
        XCTAssertEqual(ContextUsageReader.windowSize(model: "some-future-model", used: 756_000), 1_000_000)
    }
}

final class ContextWindowTests: XCTestCase {

    func testFractionIsClampedAndSafe() {
        XCTAssertEqual(ContextWindow(usedTokens: 50, size: 200).fraction, 0.25)
        XCTAssertEqual(ContextWindow(usedTokens: 400, size: 200).fraction, 1)
        XCTAssertEqual(ContextWindow(usedTokens: 10, size: 0).fraction, 0)
    }

    func testAbbreviatesLikeClaudeCode() {
        XCTAssertEqual(ContextWindow.abbreviate(842), "842")
        XCTAssertEqual(ContextWindow.abbreviate(18_400), "18k")
        XCTAssertEqual(ContextWindow.abbreviate(756_057), "756k")
        XCTAssertEqual(ContextWindow.abbreviate(1_240_000), "1.2M")
    }

    func testSummaryReadsAsAFraction() {
        XCTAssertEqual(
            ContextWindow(usedTokens: 756_057, size: 1_000_000).summary,
            "756k / 1.0M (76%)"
        )
    }
}

final class StatusLinePayloadTests: XCTestCase {

    private func decode(_ json: String) throws -> StatusLinePayload {
        try JSONDecoder().decode(StatusLinePayload.self, from: Data(json.utf8))
    }

    func testReadsContextWindowAndRateLimits() throws {
        let payload = try decode("""
        {"session_id":"abc","context_window":{"total_input_tokens":756057,
        "context_window_size":1000000},
        "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1787664424},
        "seven_day":{"used_percentage":88.0,"resets_at":1787664424}}}
        """)

        XCTAssertEqual(payload.context, ContextWindow(usedTokens: 756_057, size: 1_000_000))
        XCTAssertEqual(payload.usage?.fiveHour?.usedPercentage, 42.5)
        XCTAssertEqual(payload.usage?.sevenDay?.usedPercentage, 88.0)
        XCTAssertNil(payload.usage?.sevenDayOpus)
    }

    /// Claude Code omits rate_limits entirely on plans without them.
    func testPayloadWithoutRateLimits() throws {
        let payload = try decode(#"{"session_id":"abc","context_window":{"total_input_tokens":10,"context_window_size":200000}}"#)

        XCTAssertNil(payload.usage)
        XCTAssertEqual(payload.context?.usedTokens, 10)
    }

    func testAcceptsSecondsMillisecondsAndISODates() throws {
        let seconds = try decode(#"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1787664424}}}"#)
        let millis = try decode(#"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1787664424000}}}"#)
        let iso = try decode(#"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":"2026-08-25T14:47:04Z"}}}"#)

        XCTAssertEqual(seconds.usage?.fiveHour?.resetsAt, millis.usage?.fiveHour?.resetsAt)
        XCTAssertNotNil(iso.usage?.fiveHour?.resetsAt)
    }

    func testGarbageIsIgnoredRatherThanCrashing() throws {
        let payload = try decode(#"{"rate_limits":{"five_hour":{"resets_at":null}}}"#)
        XCTAssertNil(payload.usage)
    }
}

final class RateLimitWindowTests: XCTestCase {

    func testResetTextCountsDown() {
        let now = Date()
        let window = RateLimitWindow(usedPercentage: 10, resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60))
        XCTAssertEqual(window.resetText(now: now), "resets in 2h 15m")
    }

    func testResetTextInThePastIsHidden() {
        let now = Date()
        let window = RateLimitWindow(usedPercentage: 10, resetsAt: now.addingTimeInterval(-60))
        XCTAssertNil(window.resetText(now: now))
    }

    func testMostUsedWindowWins() {
        let snapshot = UsageSnapshot(
            fiveHour: RateLimitWindow(usedPercentage: 20, resetsAt: nil),
            sevenDay: RateLimitWindow(usedPercentage: 91, resetsAt: nil),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            updatedAt: Date()
        )
        XCTAssertEqual(snapshot.mostUsed?.label, "week")
    }
}

final class PermissionVocabularyTests: XCTestCase {

    private func permission(tool: String, suggestions: [JSONValue] = [.string("rule")]) -> PendingPermission {
        PendingPermission(
            id: "1", sessionId: "s", toolName: tool, toolInput: nil,
            suggestions: suggestions, timeout: 60, responder: { _ in }
        )
    }

    /// Approving a plan is accepting it, and declining sends Claude back to
    /// planning rather than blocking a call.
    func testPlanApprovalUsesPlanWording() {
        let plan = permission(tool: "ExitPlanMode")
        XCTAssertEqual(plan.vocabulary.allow, "Accept")
        XCTAssertEqual(plan.vocabulary.deny, "Revise")
        XCTAssertFalse(plan.canAllowAlways, "\"Allow all\" is meaningless for a plan")
    }

    func testQuestionUsesQuestionWording() {
        let question = permission(tool: "AskUserQuestion")
        XCTAssertEqual(question.vocabulary.allow, "Ask me")
        XCTAssertEqual(question.vocabulary.deny, "Skip")
    }

    func testToolCallsKeepAllowAndDeny() {
        let bash = permission(tool: "Bash")
        XCTAssertEqual(bash.vocabulary.allow, "Allow")
        XCTAssertEqual(bash.vocabulary.deny, "Deny")
        XCTAssertTrue(bash.canAllowAlways)
    }

    func testAllowAlwaysStillNeedsSuggestions() {
        XCTAssertFalse(permission(tool: "Bash", suggestions: []).canAllowAlways)
    }
}

final class PlanUsageReaderTests: XCTestCase {

    private var file: URL!
    private var reader: PlanUsageReader!

    override func setUpWithError() throws {
        file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plan-usage-\(UUID().uuidString).json")
        reader = PlanUsageReader(path: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func write(samples: [(seconds: TimeInterval, values: [String: Double])]) throws {
        let encoded = samples.map { sample in
            ["t": sample.seconds * 1_000, "org": "org-1", "u": sample.values] as [String: Any]
        }
        let json: [String: Any] = ["version": 2, "samples": encoded]
        try JSONSerialization.data(withJSONObject: json).write(to: file)
    }

    /// The shape the desktop app actually writes: short keys, percentages.
    func testReadsTheNewestSample() throws {
        let now = Date()
        try write(samples: [
            (now.addingTimeInterval(-600).timeIntervalSince1970, ["fh": 12, "sd": 20]),
            (now.timeIntervalSince1970, ["fh": 57, "sd": 25]),
        ])

        let usage = try XCTUnwrap(reader.read(now: now))
        XCTAssertEqual(usage.fiveHour?.usedPercentage, 57)
        XCTAssertEqual(usage.sevenDay?.usedPercentage, 25)
        XCTAssertNil(usage.sevenDayOpus)
    }

    func testMapsPerModelWeeklyWindows() throws {
        let now = Date()
        try write(samples: [(now.timeIntervalSince1970, ["fh": 5, "so": 40, "sn": 60])])

        let usage = try XCTUnwrap(reader.read(now: now))
        XCTAssertEqual(usage.sevenDayOpus?.usedPercentage, 40)
        XCTAssertEqual(usage.sevenDaySonnet?.usedPercentage, 60)
    }

    /// Out-of-order samples must not produce an older reading.
    func testOrderInTheFileIsNotTrusted() throws {
        let now = Date()
        try write(samples: [
            (now.timeIntervalSince1970, ["fh": 57]),
            (now.addingTimeInterval(-900).timeIntervalSince1970, ["fh": 12]),
        ])

        XCTAssertEqual(try XCTUnwrap(reader.read(now: now)).fiveHour?.usedPercentage, 57)
    }

    /// The desktop app stops sampling when it quits; a stale reading would
    /// describe windows that have since rolled over.
    func testDropsReadingsPastTheAgeLimit() throws {
        let now = Date()
        try write(samples: [(now.addingTimeInterval(-7 * 3600).timeIntervalSince1970, ["fh": 57])])

        XCTAssertNil(reader.read(now: now))
    }

    func testTimestampBecomesTheReadingTime() throws {
        let now = Date()
        let sampledAt = now.addingTimeInterval(-600)
        try write(samples: [(sampledAt.timeIntervalSince1970, ["fh": 57])])

        let usage = try XCTUnwrap(reader.read(now: now))
        XCTAssertEqual(usage.updatedAt.timeIntervalSince1970, sampledAt.timeIntervalSince1970, accuracy: 1)
    }

    func testMissingOrEmptyFileIsNotAnError() throws {
        XCTAssertNil(reader.read())

        try JSONSerialization.data(withJSONObject: ["version": 2, "samples": []])
            .write(to: file)
        XCTAssertNil(reader.read())
    }

    func testSampleWithNoWindowsIsIgnored() throws {
        try write(samples: [(Date().timeIntervalSince1970, [:])])
        XCTAssertNil(reader.read())
    }
}
