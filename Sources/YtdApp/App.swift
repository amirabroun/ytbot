import SwiftUI

@main
struct YtdApp: App {
  @StateObject private var store = DownloadStore()
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    WindowGroup("ytd") {
      ContentView()
        .environmentObject(store)
    }
    .windowResizability(.contentMinSize)
    .commands {
      // Single-window utility: no File > New.
      CommandGroup(replacing: CommandGroupPlacement.newItem) {}
    }
  }
}

/// Closes the last window = quits the app (no zombie yt-dlp processes).
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
