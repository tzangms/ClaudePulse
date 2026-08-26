import XCTest
@testable import ccpulse

final class ClaudeDesktopSessionsTests: XCTestCase {

    private var store: URL!

    override func setUpWithError() throws {
        store = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulse-desktop-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: store.appendingPathComponent("account-1/org-1"), withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: store)
    }

    private func write(
        record name: String, cliSessionId: String,
        lastActivityAt: Double = 1_000, isArchived: Bool = false
    ) throws {
        let json = """
        {"sessionId":"\(name)","cliSessionId":"\(cliSessionId)","cwd":"/tmp",\
        "lastActivityAt":\(lastActivityAt),"isArchived":\(isArchived)}
        """
        try json.write(
            to: store.appendingPathComponent("account-1/org-1/\(name).json"),
            atomically: true, encoding: .utf8
        )
    }

    /// The live desktop session being named for the CLI session is what makes
    /// `resume` focus rather than copy.
    func testFocusableWhenTheLiveRecordIsNamedForTheCliSession() throws {
        let id = "7f8a8350-1145-4c37-a911-31afdcb9f7f0"
        try write(record: "local_\(id)", cliSessionId: id)

        XCTAssertEqual(ClaudeDesktopSessions.liveTwin(of: id, in: store), "local_\(id)")
    }

    /// The desktop id normally drifts from the CLI id, and is what the route
    /// has to be built from.
    func testResolvesTheDesktopIdWhenItDiffersFromTheCliId() throws {
        let cli = "5135fa21-925c-4d89-ae4b-28210aae2a88"
        try write(record: "local_b60f1563-0f27-45a0-80b3-d5515d699fb8", cliSessionId: cli)

        XCTAssertEqual(ClaudeDesktopSessions.liveTwin(of: cli, in: store),
                       "local_b60f1563-0f27-45a0-80b3-d5515d699fb8")
    }

    /// The case that shipped a stale transcript: an earlier import left a
    /// record named for the CLI session, but the session moved on to a desktop
    /// id of its own. The live one has to win.
    func testStaleImportDoesNotWinOverTheLiveSession() throws {
        let cli = "5135fa21-925c-4d89-ae4b-28210aae2a88"
        try write(record: "local_\(cli)", cliSessionId: cli, lastActivityAt: 1_000)
        try write(record: "local_b60f1563-0f27-45a0-80b3-d5515d699fb8",
                  cliSessionId: cli, lastActivityAt: 9_000)

        XCTAssertEqual(ClaudeDesktopSessions.liveTwin(of: cli, in: store),
                       "local_b60f1563-0f27-45a0-80b3-d5515d699fb8")
    }

    /// The same pair the other way round: the named record is the active one.
    func testLiveNamedRecordWinsOverAnOlderDriftedOne() throws {
        let cli = "372bddbf-606f-41ee-9211-65e819f3e1f1"
        try write(record: "local_\(cli)", cliSessionId: cli, lastActivityAt: 9_000)
        try write(record: "local_91b06dd4-e76d-4f8e-9d9e-9526516bc93d",
                  cliSessionId: cli, lastActivityAt: 1_000)

        XCTAssertEqual(ClaudeDesktopSessions.liveTwin(of: cli, in: store), "local_\(cli)")
    }

    /// An archived session is never the live one, however recent it looks.
    func testArchivedRecordNeverWins() throws {
        let cli = "5135fa21-925c-4d89-ae4b-28210aae2a88"
        try write(record: "local_\(cli)", cliSessionId: cli, lastActivityAt: 1_000)
        try write(record: "local_b60f1563-0f27-45a0-80b3-d5515d699fb8",
                  cliSessionId: cli, lastActivityAt: 9_000, isArchived: true)

        XCTAssertEqual(ClaudeDesktopSessions.liveTwin(of: cli, in: store), "local_\(cli)")
    }

    /// A record named for the session that no longer claims it is a leftover,
    /// not a twin.
    func testFilenameAloneDoesNotMakeATwin() throws {
        let cli = "7f8a8350-1145-4c37-a911-31afdcb9f7f0"
        try write(record: "local_\(cli)", cliSessionId: "99999999-9999-4999-8999-999999999999")

        XCTAssertNil(ClaudeDesktopSessions.liveTwin(of: cli, in: store))
    }

    /// Desktop ids come off disk and go into a URL path.
    func testRejectsDesktopIdsThatCannotGoInARoute() throws {
        let cli = "7f8a8350-1145-4c37-a911-31afdcb9f7f0"
        try write(record: "local_..%2f..%2fetc", cliSessionId: cli)

        XCTAssertNil(ClaudeDesktopSessions.liveTwin(of: cli, in: store))
    }

    func testUnknownSessionHasNoTwin() throws {
        try write(record: "local_7f8a8350-1145-4c37-a911-31afdcb9f7f0",
                  cliSessionId: "7f8a8350-1145-4c37-a911-31afdcb9f7f0")

        XCTAssertNil(ClaudeDesktopSessions.liveTwin(of: "00000000-0000-4000-8000-000000000000", in: store))
    }

    /// Ids arrive from hook payloads and must never be spliced into a path.
    func testRejectsNonUUIDSessionIds() {
        XCTAssertNil(ClaudeDesktopSessions.liveTwin(of: "../../etc/passwd", in: store))
        XCTAssertNil(ClaudeDesktopSessions.liveTwin(of: "", in: store))
    }
}
