import Foundation
import PlansCore

enum AppInfo {
    static var versionLabel: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "PlansBarBuildIdentifier") as? String
        guard let build, !build.isEmpty else { return PlansBarVersion.current }
        return "\(PlansBarVersion.current) (\(build))"
    }

    static let releasesURL = URL(string: "https://github.com/zergzorg/plansbar/releases")!
}
