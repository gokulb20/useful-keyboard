import SwiftUI
import UsefulKeyboardCore

struct DashboardRootView: View {
    let appState: AppState
    let controller: AppController

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState, controller: controller)
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            Group {
                switch appState.selectedTab {
                case .dictations:
                    DictationsView(appState: appState, controller: controller)
                case .meetings:
                    MeetingsView(appState: appState, controller: controller)
                case .dictionary:
                    DictionaryView(appState: appState, controller: controller)
                case .models:
                    ModelsView(appState: appState, controller: controller)
                case .shortcuts:
                    ShortcutsView(appState: appState, controller: controller)
                case .settings:
                    SettingsView(appState: appState, controller: controller)
                case .about:
                    AboutView(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundBase)
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(appState.config.darkMode ? .dark : .light)
    }
}
