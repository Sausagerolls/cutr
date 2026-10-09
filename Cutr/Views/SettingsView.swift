import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unit) private var unit: LengthUnit = Locale.current.measurementSystem == .us ? .inches : .millimetres
    @AppStorage(SettingsKey.defaultKerf) private var defaultKerf = 3.0
    @AppStorage(SettingsKey.defaultEdgeTrim) private var defaultEdgeTrim = 0.0
    @AppStorage(SettingsKey.defaultSheetLength) private var defaultSheetLength = 2440.0
    @AppStorage(SettingsKey.defaultSheetWidth) private var defaultSheetWidth = 1220.0
    @AppStorage(SettingsKey.defaultSheetThickness) private var defaultSheetThickness = 18.0

    private var iCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Measurements", selection: $unit) {
                        ForEach(LengthUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                }

                Section {
                    LengthField("Kerf / buffer", value: $defaultKerf)
                    LengthField("Edge trim", value: $defaultEdgeTrim)
                    LengthField("Sheet length", value: $defaultSheetLength)
                    LengthField("Sheet width", value: $defaultSheetWidth)
                    LengthField("Sheet thickness", value: $defaultSheetThickness)
                } header: {
                    Text("New Cut List Defaults")
                } footer: {
                    Text("A typical table saw or circular saw blade removes about 3 mm (1/8\").")
                }
                .environment(\.lengthUnit, unit)

                Section {
                    Label {
                        VStack(alignment: .leading) {
                            Text(iCloudAvailable ? "iCloud Sync On" : "iCloud Unavailable")
                            Text(iCloudAvailable
                                 ? "Cut lists sync automatically across your iPhone and iPad."
                                 : "Sign in to iCloud in Settings to sync cut lists between devices. Your data is saved on this device.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: iCloudAvailable ? "checkmark.icloud" : "icloud.slash")
                            .foregroundStyle(iCloudAvailable ? .green : .secondary)
                    }
                } header: {
                    Text("Sync")
                }

                Section {
                    LabeledContent("Version", value: version)
                    Link(destination: URL(string: "https://github.com/Sausagerolls/cutr")!) {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://github.com/Sausagerolls/cutr/issues")!) {
                        Label("Report a Problem", systemImage: "ladybug")
                    }
                    Link(destination: URL(string: "https://github.com/Sausagerolls/cutr/blob/main/PRIVACY.md")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Cutr is free and open source under the MIT licence. It collects no data; your cut lists stay on your devices and in your private iCloud.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
