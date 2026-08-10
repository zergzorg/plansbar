import CryptoKit
import Foundation

public struct RepositoryIdentity: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case gitRemote = "git_remote"
        case localRegistration = "local_registration"
    }

    public let rawValue: String
    public let kind: Kind

    public init(rawValue: String, kind: Kind) {
        self.rawValue = rawValue
        self.kind = kind
    }

    public static func resolve(rootURL: URL, fallback: String? = nil) -> RepositoryIdentity {
        if let remote = originRemote(in: rootURL) {
            let digest = SHA256.hash(data: Data(remote.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            return RepositoryIdentity(rawValue: "git:\(digest)", kind: .gitRemote)
        }
        let local = fallback ?? rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        return RepositoryIdentity(rawValue: "local:\(local)", kind: .localRegistration)
    }

    private static func originRemote(in rootURL: URL) -> String? {
        guard let configURL = gitConfigURL(in: rootURL),
              let config = try? String(contentsOf: configURL, encoding: .utf8)
        else { return nil }

        var isOrigin = false
        for line in config.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") {
                isOrigin = value.lowercased() == "[remote \"origin\"]"
                continue
            }
            guard isOrigin, let separator = value.firstIndex(of: "=") else { continue }
            let key = value[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == "url" else { continue }
            let remote = value[value.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return remote.isEmpty ? nil : remote
        }
        return nil
    }

    private static func gitConfigURL(in rootURL: URL) -> URL? {
        let dotGit = rootURL.appending(path: ".git")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return dotGit.appending(path: "config")
        }

        guard let marker = try? String(contentsOf: dotGit, encoding: .utf8),
              marker.hasPrefix("gitdir:")
        else { return nil }
        let path = marker.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDirectory = URL(fileURLWithPath: path, relativeTo: rootURL).standardizedFileURL
        let directConfig = gitDirectory.appending(path: "config")
        if FileManager.default.fileExists(atPath: directConfig.path) { return directConfig }

        guard let common = try? String(
            contentsOf: gitDirectory.appending(path: "commondir"),
            encoding: .utf8
        ) else { return nil }
        return URL(
            fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines),
            relativeTo: gitDirectory
        ).standardizedFileURL.appending(path: "config")
    }
}
