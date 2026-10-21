import LeBotCore
import LeBotDesign
import SwiftUI

@main
struct LeBotApp: App {
    @State private var appModel = AppModel(config: .main)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .tint(Palette.accent)
                .task { await appModel.observeAuth() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            switch appModel.state {
            case .loading:
                Palette.background.ignoresSafeArea()
            case .signedOut:
                SignInView()
                    .transition(.opacity)
            case .signedIn, .preview:
                ChatView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: appModel.state)
    }
}
