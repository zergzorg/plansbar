import Darwin
import Foundation
import PlansCore

let version = "0.1.0"
let arguments = Array(CommandLine.arguments.dropFirst())

func value(after option: String) -> String? {
    guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func repositoryPath(for command: String) -> String? {
    if let root = value(after: "--root") { return root }
    guard let index = arguments.firstIndex(of: command), index + 1 < arguments.count else { return nil }
    let candidate = arguments[index + 1]
    return candidate.hasPrefix("--") ? nil : candidate
}

func writeJSON(_ report: RepositoryReport) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.keyEncodingStrategy = .convertToSnakeCase
    guard let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) else {
        fputs("Unable to encode report.\n", stderr)
        exit(1)
    }
    print(text)
}

func runValidation(command: String) -> Never {
    guard let path = repositoryPath(for: command) else {
        fputs("Usage: plansbar \(command) --root <repository> [--json]\n", stderr)
        exit(64)
    }
    let validation = RepositoryValidator.validate(rootURL: URL(fileURLWithPath: path, isDirectory: true))
    let report = RepositoryReport(validation)
    if arguments.contains("--json") {
        writeJSON(report)
    } else {
        print("\(validation.name): \(validation.state.rawValue)")
        for missing in validation.missingPaths { print("missing: \(missing)") }
        for plan in validation.plans where plan.parseState == .invalidPlan {
            print("invalid: \(plan.relativePath) [\(plan.lintErrors.joined(separator: ", "))]")
        }
    }
    exit(validation.state == .ready ? 0 : 2)
}

switch arguments.first {
case "--version", "version":
    print(version)
case "validate-repository":
    runValidation(command: "validate-repository")
case "lint":
    runValidation(command: "lint")
case "scan":
    runValidation(command: "scan")
default:
    print("plansbar \(version)")
    print("Commands: validate-repository, lint, scan, --version")
}
