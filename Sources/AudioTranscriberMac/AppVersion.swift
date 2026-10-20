import Foundation

/// Reads the app's version from the bundle's Info.plist (`scripts/Info.plist`,
/// baked in by `scripts/bundle-app.sh`). A plain `swift run` dev build has no
/// such bundle, so this falls back to an honest "dev build" label rather than
/// a fabricated version number.
enum AppVersion {
    static var displayString: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "dev build"
        }
        return "v\(version)"
    }
}
