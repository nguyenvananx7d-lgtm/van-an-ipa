import SwiftUI

/// First-run language chooser. Shown once; the choice is persisted under
/// `ffxc.langSelected` and the screen never appears again.
struct LanguagePickerView: View {
    @ObservedObject var store: LanguageStore
    @State private var selection: Language?

    var body: some View {
<<<<<<< HEAD
        ZStack {
            ThemeBackground()

            ScrollView {
                VStack(spacing: 20) {
                    Mark(size: 84)

                    VStack(spacing: 6) {
                        Text("app_title")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Palette.text)
                        Text("select_your_language")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textDim)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(Language.allCases) { language in
                            row(language)
                        }
                    }

                    Button {
                        if let selection { store.choose(selection) }
                    } label: {
                        Text("confirm")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(selection == nil)
                    .padding(.top, 4)

                    Spacer(minLength: 24)
                }
                .padding(20)
            }
        }
    }

    private func row(_ language: Language) -> some View {
        let active = selection == language
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selection = language
            }
        } label: {
            HStack(spacing: 14) {
                Text(language.flag).font(.title2)
                Text(language.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.text)
                    .environment(\.layoutDirection,
                                 language.isRightToLeft ? .rightToLeft : .leftToRight)
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .machined(radius: 14, elevated: active, glow: active ? Palette.accent : nil)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(active ? Palette.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
=======
        ScrollView {
            VStack(spacing: 18) {
                Mark()

                VStack(spacing: 6) {
                    Text("app_title")
                        .font(.largeTitle.bold())
                    Text("select_your_language")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                VStack(spacing: 10) {
                    ForEach(Language.allCases) { language in
                        Button {
                            selection = language
                        } label: {
                            HStack(spacing: 14) {
                                Text(language.flag).font(.title2)
                                Text(language.displayName)
                                    .font(.body.weight(.medium))
                                    .environment(\.layoutDirection,
                                                 language.isRightToLeft ? .rightToLeft : .leftToRight)
                                Spacer()
                                if selection == language {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selection == language
                                          ? Color.accentColor.opacity(0.14)
                                          : Color(.secondarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    if let selection { store.choose(selection) }
                } label: {
                    Text("confirm")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil)
                .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
    }
}
