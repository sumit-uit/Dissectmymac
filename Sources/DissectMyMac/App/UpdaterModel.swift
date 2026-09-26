import Combine
import Foundation
import Sparkle

/// Sparkle auto-updates. Active only in a real .app bundle whose Info.plist has `SUFeedURL` and
/// `SUPublicEDKey` (see README → Releasing). In `swift run` / tests it stays inert.
@MainActor
final class UpdaterModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController?

    init() {
        let bundle = Bundle.main
        let configured = bundle.bundleURL.pathExtension == "app"
            && bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil
            && bundle.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
        if configured {
            let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        } else {
            controller = nil
        }
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
