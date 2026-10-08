import SwiftUI

/// Render the server-sent control catalog by section.
struct ControlsView: View {
    @EnvironmentObject var menu: MenuStore
    @EnvironmentObject var auth: AuthorizationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if menu.catalog.isEmpty {
                    Card {
                        VStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("controls_unavailable")
                                .font(.headline)
                            Text("controls_unavailable_hint")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                    }
                } else {
                    ForEach(menu.sections, id: \.self) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func sectionView(_ section: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section)
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(menu.controls(inSection: section)) { descriptor in
                    controlRow(descriptor)
                }
            }
        }
    }

    private func controlRow(_ descriptor: ControlDescriptor) -> some View {
        Card(padding: 12, radius: 14) {
            HStack(alignment: .center, spacing: 12) {
                if let symbol = descriptor.symbol {
                    Image(systemName: symbol)
                        .frame(width: 26)
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title)
                        .font(.body.weight(.semibold))
                    if let subtitle = descriptor.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 10)

                switch descriptor.policy ?? .value {
                case .exclusiveGroup:
                    if let options = descriptor.options {
                        Picker("", selection: menu.picker(for: descriptor)) {
                            ForEach(options, id: \.self) { option in
                                Text(optionValue(option)).tag(optionValue(option))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                case .option:
                    if let options = descriptor.options {
                        Picker("", selection: menu.picker(for: descriptor)) {
                            ForEach(options, id: \.self) { option in
                                Text(optionValue(option)).tag(optionValue(option))
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 160)
                    }

                case .value:
                    if descriptor.id == ControlID.headshot.rawValue {
                        Toggle("", isOn: menu.toggle(for: descriptor))
                    } else {
                        HStack(spacing: 8) {
                            Slider(
                                value: menu.binding(for: descriptor),
                                in: (descriptor.min ?? 0)...(descriptor.max ?? 100),
                                step: descriptor.step ?? 1
                            )
                            .frame(maxWidth: 160)
                            Text("\(Int(menu.value(of: descriptor)))")
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func optionValue(_ option: String) -> String {
        option.split(separator: "|").last.map(String.init) ?? option
    }
}
