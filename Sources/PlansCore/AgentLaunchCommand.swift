import Foundation

public enum AgentLaunchCommand {
    public static func terminalCommand(
        executablePath: String,
        repositoryPath: String,
        prompt: String
    ) -> String {
        let script = "cd -- \(shellQuote(repositoryPath))\nexec \(shellQuote(executablePath)) -- \(shellQuote(prompt))"
        let encoded = Data(script.utf8).base64EncodedString()
        return "eval \"$(printf %s '\(encoded)' | /usr/bin/base64 -D)\""
    }

    public static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
