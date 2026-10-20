import AppKit
import SwiftUI

// This bare SPM executable has no Info.plist, so without this, closing the
// window leaves the process running headless in the background -- wasteful
// here specifically, since the Qwen3-ASR backend keeps a multi-GB MLX model
// loaded in memory for the rest of the (otherwise invisible) process's life.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct AudioTranscriberMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Audio Transcriber \(AppVersion.displayString)") {
            ContentView()
        }
    }
}
