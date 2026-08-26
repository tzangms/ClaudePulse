import XCTest
@testable import ccpulse

final class SessionTitleReaderTests: XCTestCase {

    private var file: URL!

    override func setUpWithError() throws {
        file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulse-title-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func write(_ lines: [String]) throws {
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Claude Code rewrites the record as the title changes, so the last one is
    /// the session's current name.
    func testReadsTheLatestCustomTitle() throws {
        try write([
            #"{"type":"custom-title","customTitle":"First guess","sessionId":"s"}"#,
            #"{"type":"user","message":{"content":"hi"}}"#,
            #"{"type":"custom-title","customTitle":"Panel width and glyphs","sessionId":"s"}"#,
        ])
        XCTAssertEqual(SessionTitleReader.read(transcriptPath: file.path), "Panel width and glyphs")
    }

    /// Older transcripts name the session with a summary record instead.
    func testFallsBackToSummaryRecords() throws {
        try write([
            #"{"type":"summary","summary":"Fix the hover race"}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-5","usage":{"input_tokens":1}}}"#,
        ])
        XCTAssertEqual(SessionTitleReader.read(transcriptPath: file.path), "Fix the hover race")
    }

    func testReturnsNilWhenTheSessionHasNoName() throws {
        try write([#"{"type":"user","message":{"content":"hi"}}"#])
        XCTAssertNil(SessionTitleReader.read(transcriptPath: file.path))
        XCTAssertNil(SessionTitleReader.read(transcriptPath: "/nope/missing.jsonl"))
    }

    func testIgnoresAnEmptyTitle() throws {
        try write([
            #"{"type":"custom-title","customTitle":"Real name","sessionId":"s"}"#,
            #"{"type":"custom-title","customTitle":"   ","sessionId":"s"}"#,
        ])
        XCTAssertEqual(SessionTitleReader.read(transcriptPath: file.path), "Real name")
    }

    /// Only the tail is read, and titles are rewritten often enough to be there.
    func testReadsTheTitleFromTheTailOfALargeTranscript() throws {
        var lines: [String] = []
        let filler = #"{"type":"user","message":{"content":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}"#
        lines.append(#"{"type":"custom-title","customTitle":"Ancient name","sessionId":"s"}"#)
        for _ in 0..<12_000 { lines.append(filler) }
        lines.append(#"{"type":"custom-title","customTitle":"Current name","sessionId":"s"}"#)
        for _ in 0..<200 { lines.append(filler) }
        try write(lines)

        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, TranscriptTail.defaultBytes)
        XCTAssertEqual(SessionTitleReader.read(transcriptPath: file.path), "Current name")
    }
}

final class ActionDetailTests: XCTestCase {

    /// The whole tool input is what makes a large prompt worth having.
    func testFullDetailListsEveryToolInputField() throws {
        let event = try JSONDecoder().decode(HookEvent.self, from: Data("""
        {"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash",
         "tool_input":{"command":"make test","description":"run the suite","timeout":600}}
        """.utf8))
        let permission = PendingPermission(
            id: "1", sessionId: "s", toolName: "Bash",
            toolInput: event.toolInput, suggestions: [], timeout: 60, responder: { _ in }
        )

        XCTAssertEqual(permission.detail, "make test")
        XCTAssertEqual(
            permission.fullDetail,
            "command: make test\ndescription: run the suite\ntimeout: 600"
        )
        XCTAssertTrue(permission.hasMoreDetail)
    }

    /// A prompt whose input is a single field has nothing more to expand into.
    func testASingleFieldPromptHasNothingMoreToShow() throws {
        let event = try JSONDecoder().decode(HookEvent.self, from: Data("""
        {"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Read",
         "tool_input":{"file_path":"/repo/Package.swift"}}
        """.utf8))
        let permission = PendingPermission(
            id: "1", sessionId: "s", toolName: "Read",
            toolInput: event.toolInput, suggestions: [], timeout: 60, responder: { _ in }
        )
        XCTAssertEqual(permission.detail, "/repo/Package.swift")
        XCTAssertEqual(permission.fullDetail, "file_path: /repo/Package.swift")
    }

    /// Bottom positions size their frame up front, so a fuller prompt needs a
    /// taller one to sit in.
    func testLargerDetailAsksForATallerPanel() {
        XCTAssertGreaterThan(ActionDetail.full.bottomPanelHeight, ActionDetail.standard.bottomPanelHeight)
        XCTAssertGreaterThan(ActionDetail.standard.bottomPanelHeight, ActionDetail.compact.bottomPanelHeight)
        XCTAssertGreaterThan(ActionDetail.full.lineLimit, ActionDetail.compact.lineLimit)
        XCTAssertTrue(ActionDetail.full.showsWholeInput)
        XCTAssertFalse(ActionDetail.compact.showsWholeInput)
    }
}
