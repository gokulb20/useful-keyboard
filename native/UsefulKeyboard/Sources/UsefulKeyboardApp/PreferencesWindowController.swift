import AppKit
import Foundation
import UsefulKeyboardCore

@MainActor
final class PreferencesWindowController: NSObject {
    private let controller: AppController

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        controller.openHistoryWindow(tab: .settings)
    }

    func refresh() {
        controller.syncAppState()
    }
}
