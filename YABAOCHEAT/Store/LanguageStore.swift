import Foundation
import SwiftUI

/// Interface language selection, persisted so the choice survives a relaunch.
///
/// The selected language is also written to `UserDefaults` under its own key so
/// the resource loader can read it before any SwiftUI view exists.
@MainActor
public final class LanguageStore: ObservableObject {
    public static let shared = LanguageStore()

    public static let defaultsKey = "ffxc.langSelected"

    @AppStorage(LanguageStore.defaultsKey)
    private var stored: String = Language.english.rawValue

    @Published public var selected: Language {
        didSet {
            guard selected != oldValue else { return }
            stored = selected.rawValue
            NotificationCenter.default.post(name: Notifications.languageSelected, object: selected)
        }
    }

    /// True once the user has made a choice. The language screen is skipped
    /// after that, and the app goes straight to the license screen.
    @Published public var hasChosen: Bool

    private init() {
        let raw = UserDefaults.standard.string(forKey: LanguageStore.defaultsKey)
        let language = raw.flatMap(Language.init(rawValue:)) ?? .english
        selected = language
        hasChosen = raw != nil
    }

    public func choose(_ language: Language) {
        selected = language
        hasChosen = true
    }
}
