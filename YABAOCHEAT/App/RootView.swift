import SwiftUI

/// Decides between the language chooser, the license screen and the main shell.
struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authorization: AuthorizationStore

    var body: some View {
        Group {
            if !language.hasChosen {
                LanguagePickerView(store: language)
            } else {
                ContentView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: language.hasChosen)
        .tint(.purple)
    }
}
