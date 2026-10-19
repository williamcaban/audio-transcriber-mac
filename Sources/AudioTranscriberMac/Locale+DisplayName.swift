import Foundation

extension Locale {
    /// This locale's display name, consistently in the app's own display
    /// language (the current locale), not the locale's own language.
    ///
    /// `locale.localizedString(forIdentifier: locale.identifier)` -- the
    /// naive, self-referential call -- renders each locale's name *in that
    /// locale's own language and capitalization convention*: "español"
    /// (lowercase) for es-ES, "français" (lowercase) for fr-FR, and so on.
    /// That reads as an inconsistent, half-lowercase list sitting right
    /// next to Qwen3-ASR's plain English Title Case names ("Spanish",
    /// "French"). Always interpreting through `Locale.current` instead
    /// fixes both complaints at once: every name renders in the same
    /// language, with that language's normal capitalization.
    var appDisplayName: String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
