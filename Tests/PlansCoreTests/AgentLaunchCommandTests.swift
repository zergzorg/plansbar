import Foundation
import XCTest

@testable import PlansCore

final class AgentLaunchCommandTests: XCTestCase {
    func testShellQuoteRoundTripsUnsafeValues() throws {
        let values = [
            "path with spaces",
            "apostrophe's repo",
            "Юникод",
            "line one\nline two",
            "--leading-dash"
        ]
        for value in values {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "/usr/bin/printf %s \(AgentLaunchCommand.shellQuote(value))"]
            process.standardOutput = output
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), value)
        }
    }

    func testTerminalCommandDoesNotExposeLiteralPrompt() {
        let command = AgentLaunchCommand.terminalCommand(
            executablePath: "/opt/homebrew/bin/codex",
            repositoryPath: "/tmp/repo with spaces",
            prompt: "private prompt\nwith lines"
        )
        XCTAssertFalse(command.contains("private prompt"))
        XCTAssertTrue(command.unicodeScalars.allSatisfy(\.isASCII))
    }
}
