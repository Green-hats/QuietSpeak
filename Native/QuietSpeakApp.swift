import AppKit
import SwiftUI

@main struct QuietSpeakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var client = ClientModel()
    var body: some Scene {
        WindowGroup("轻语") {
            MainView().environmentObject(client)
                .frame(minWidth: 680, minHeight: 620)
                .tint(Palette.accent)
                .onAppear { delegate.client = client }
        }
        .defaultSize(width: 1120, height: 730)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("连接服务器…") { client.showConnection = true }.keyboardShortcut("k")
            }
            CommandMenu("语音") {
                Button(client.microphoneEnabled ? "关闭麦克风" : "开启麦克风") { client.toggleMicrophone() }
                    .keyboardShortcut("m", modifiers: [.command, .shift]).disabled(
                        !client.connected)
                Button(client.deafened ? "恢复耳机" : "耳机静音") { client.toggleDeafen() }
                    .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(
                        !client.connected)
                Divider()
                Button("断开连接") { client.disconnect() }.disabled(!client.busy)
            }
            CommandGroup(replacing: .appSettings) {
                Button("语音设置…") { client.showSettings = true }.keyboardShortcut(",")
            }
        }
        MenuBarExtra {
            Text(client.connected ? client.serverName : "轻语 · 未连接")
            if let channel = client.joined { Text(channel.name) }
            Divider()
            Button(client.microphoneEnabled ? "关闭麦克风" : "开启麦克风") { client.toggleMicrophone() }
                .disabled(!client.connected)
            Button(client.deafened ? "恢复耳机" : "耳机静音") { client.toggleDeafen() }.disabled(
                !client.connected)
            Button("显示轻语") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Button("断开连接") { client.disconnect() }.disabled(!client.busy)
            Divider()
            Button("退出轻语") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: QuietSpeakIcon.template)
                .renderingMode(.template)
                .accessibilityLabel(client.transmitting ? "轻语，正在说话" : "轻语")
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var client: ClientModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { client?.shutdown() }
}

enum Palette {
    static let accent = Color(red: 0.16, green: 0.47, blue: 0.37)
    static let speaking = Color(nsColor: .systemGreen)
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let brand = adaptive(light: (0.16, 0.47, 0.37), dark: (0.48, 0.75, 0.63))
    static let sidebar = adaptive(light: (0.90, 0.94, 0.91), dark: (0.10, 0.16, 0.13))
    static let channelPanel = adaptive(light: (0.96, 0.975, 0.96), dark: (0.135, 0.185, 0.16))
    static let toolbar = adaptive(light: (0.95, 0.97, 0.95), dark: (0.13, 0.16, 0.145))
    static let selection = adaptive(light: (0.81, 0.89, 0.84), dark: (0.16, 0.30, 0.23))

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let rgb =
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            })
    }
}
