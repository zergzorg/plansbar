import Foundation

let version = "0.1.0"

if CommandLine.arguments.dropFirst().first == "--version" {
    print(version)
} else {
    print("plansbar-cli \(version)")
    print("Parser and index commands will be added with PlansCore.")
}
