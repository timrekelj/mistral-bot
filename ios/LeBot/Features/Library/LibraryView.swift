import LeBotDesign
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Agents") {
                    HStack(spacing: 14) {
                        PixelMark().frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Mistral").font(.headline)
                            Text("Main agent · Large 4").eyebrow()
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Conversations") {
                    Text("Your conversations will appear here.")
                        .font(.callout)
                        .foregroundStyle(Palette.textSecondary)
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label {
                            HStack {
                                Text("Settings")
                                Spacer()
                                if appModel.mistralKey.needsKey {
                                    Text("Add API key").eyebrow(Palette.accent)
                                }
                            }
                        } icon: {
                            Image(systemName: "gearshape.fill").foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
