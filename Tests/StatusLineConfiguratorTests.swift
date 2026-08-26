import XCTest
@testable import ccpulse

final class StatusLineConfiguratorTests: XCTestCase {

    private var directory: URL!
    private var configurator: StatusLineConfigurator!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulse-statusline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configurator = StatusLineConfigurator(
            settingsPath: directory.appendingPathComponent("settings.json"),
            scriptPath: directory.appendingPathComponent("statusline.sh")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeSettings(_ json: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: configurator.settingsPath)
    }

    private func settings() throws -> [String: Any] {
        let data = try Data(contentsOf: configurator.settingsPath)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Claude Code's statusLine holds one command, so Pulse takes the slot
    /// outright instead of chaining to whatever was there.
    func testTakesOverAnExistingStatusLine() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool", "padding": 2]])

        try configurator.install(port: 19_280)

        let statusLine = try XCTUnwrap(settings()["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, configurator.scriptPath.path)
        XCTAssertEqual(statusLine["padding"] as? Int, 2, "layout keys are not ours to change")
        XCTAssertTrue(configurator.isInstalled())
    }

    /// Nothing about the replaced tool is recorded or invoked.
    func testScriptDoesNotReferenceTheReplacedCommand() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool"]])

        try configurator.install(port: 19_280)

        let script = try String(contentsOf: configurator.scriptPath, encoding: .utf8)
        XCTAssertFalse(script.contains("other-tool"))
        XCTAssertTrue(script.contains("/statusline"))
    }

    func testReportsTheCommandItWouldReplace() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool"]])
        XCTAssertEqual(configurator.commandInPlace(), "/opt/other-tool")

        try configurator.install(port: 19_280)
        XCTAssertNil(configurator.commandInPlace(), "our own script is not something to warn about")
    }

    func testInstallsWithNoExistingStatusLine() throws {
        try writeSettings(["hooks": [:]])

        try configurator.install(port: 19_280)

        XCTAssertTrue(configurator.isInstalled())
        XCTAssertNil(configurator.commandInPlace())
    }

    func testInstallIsIdempotent() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool"]])

        try configurator.install(port: 19_280)
        try configurator.install(port: 19_280)

        XCTAssertTrue(configurator.isInstalled())
    }

    /// Pulse never recorded the previous command, so uninstall clears the key
    /// rather than pretending it can restore it.
    func testUninstallRemovesTheStatusLineEntirely() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool"], "hooks": [:]])
        try configurator.install(port: 19_280)

        try configurator.uninstall()

        XCTAssertNil(try settings()["statusLine"])
        XCTAssertNotNil(try settings()["hooks"], "unrelated settings survive")
        XCTAssertFalse(FileManager.default.fileExists(atPath: configurator.scriptPath.path))
    }

    /// Someone else's status line must not be removed by Pulse's uninstall.
    func testUninstallLeavesAStatusLinePulseDoesNotOwn() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool"]])

        try configurator.uninstall()

        let statusLine = try XCTUnwrap(settings()["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, "/opt/other-tool")
    }

    func testSettingsAreBackedUpBeforeChanging() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool"]])

        try configurator.install(port: 19_280)

        let backup = directory.appendingPathComponent("settings.json.ccpulse-backup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let restored = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any]
        )
        let previous = try XCTUnwrap(restored["statusLine"] as? [String: Any])
        XCTAssertEqual(previous["command"] as? String, "/opt/other-tool")
    }

    func testMalformedSettingsAreRefusedRatherThanOverwritten() throws {
        try "not json".write(to: configurator.settingsPath, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try configurator.install(port: 19_280))
        XCTAssertEqual(try String(contentsOf: configurator.settingsPath, encoding: .utf8), "not json")
    }
}

final class StatusLineRendererTests: XCTestCase {

    private func payload(_ json: String) throws -> StatusLinePayload {
        try JSONDecoder().decode(StatusLinePayload.self, from: Data(json.utf8))
    }

    func testRendersModelContextAndLimits() throws {
        let line = StatusLineRenderer.render(try payload("""
        {"model":{"display_name":"Opus 5"},
        "context_window":{"total_input_tokens":756057,"context_window_size":1000000},
        "rate_limits":{"five_hour":{"used_percentage":42.5},"seven_day":{"used_percentage":88}}}
        """))

        XCTAssertEqual(line, "Opus 5 · 76% ctx · 5h 43% · wk 88%")
    }

    /// Plans without weekly limits, and payloads before any request has been
    /// made, still have to produce a sensible line.
    func testOmitsWhatIsMissing() throws {
        let line = StatusLineRenderer.render(try payload(
            #"{"model":{"display_name":"Sonnet 5"},"context_window":{"total_input_tokens":20000,"context_window_size":200000}}"#
        ))

        XCTAssertEqual(line, "Sonnet 5 · 10% ctx")
    }

    func testEmptyPayloadRendersNothing() throws {
        XCTAssertEqual(StatusLineRenderer.render(try payload("{}")), "")
    }
}

final class UsageSnapshotPersistenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "pulse-usage-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRoundTrips() throws {
        let resets = Date(timeIntervalSince1970: 1_787_664_424)
        let snapshot = UsageSnapshot(
            fiveHour: RateLimitWindow(usedPercentage: 42.5, resetsAt: resets),
            sevenDay: RateLimitWindow(usedPercentage: 88, resetsAt: nil),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            updatedAt: Date()
        )
        snapshot.persist(to: defaults)

        let restored = try XCTUnwrap(UsageSnapshot.restore(from: defaults))
        XCTAssertEqual(restored.fiveHour?.usedPercentage, 42.5)
        XCTAssertEqual(restored.fiveHour?.resetsAt, resets)
        XCTAssertEqual(restored.sevenDay?.usedPercentage, 88)
        XCTAssertNil(restored.sevenDayOpus)
    }

    /// A day-old reading describes windows that have rolled over since.
    func testStaleReadingsAreDropped() throws {
        let snapshot = UsageSnapshot(
            fiveHour: RateLimitWindow(usedPercentage: 42.5, resetsAt: nil),
            sevenDay: nil, sevenDayOpus: nil, sevenDaySonnet: nil,
            updatedAt: Date()
        )
        snapshot.persist(to: defaults)

        let later = Date().addingTimeInterval(25 * 3600)
        XCTAssertNil(UsageSnapshot.restore(from: defaults, now: later))
    }

    func testNothingStoredRestoresNothing() {
        XCTAssertNil(UsageSnapshot.restore(from: defaults))
    }
}

extension StatusLineConfiguratorTests {

    /// An app update changes the script; the old one must be replaced without
    /// asking the user again.
    func testDetectsAndRefreshesAnOutdatedScript() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool"]])
        try configurator.install(port: 19_280)
        XCTAssertFalse(configurator.needsScriptRefresh(port: 19_280))

        try "#!/bin/sh\n# an older Pulse wrote this\n".write(
            to: configurator.scriptPath, atomically: true, encoding: .utf8
        )
        XCTAssertTrue(configurator.needsScriptRefresh(port: 19_280))

        try configurator.refreshScript(port: 19_280)

        XCTAssertFalse(configurator.needsScriptRefresh(port: 19_280))
        let script = try String(contentsOf: configurator.scriptPath, encoding: .utf8)
        XCTAssertTrue(script.contains("/statusline"))
    }

    /// A status line belonging to another tool is not ours to refresh.
    func testNeverRefreshesWhenPulseDoesNotOwnTheSlot() throws {
        try writeSettings(["statusLine": ["type": "command", "command": "/opt/other-tool"]])
        XCTAssertFalse(configurator.needsScriptRefresh(port: 19_280))
    }
}
