import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct AntiScratchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NoteStore()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("theme") private var themeName = "Mint"

    var body: some Scene {
        WindowGroup {
            ScratchpadView()
                .environmentObject(store)
                .preferredColorScheme(themeName == "Paper" ? .light : .dark)
                .background(WindowSizer())
        }
        .defaultSize(width: 310, height: 378)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nova nota") {
                    store.addNote()
                    AppVisibility.show()
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Fechar janela") { AppVisibility.close() }
                    .keyboardShortcut("w")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Ajustes…") {
                    AppVisibility.show()
                    NotificationCenter.default.post(name: .showAntiScratchSettings, object: nil)
                }
                .keyboardShortcut(",")
            }
            CommandMenu("Nota") {
                Button("Nova nota") {
                    store.addNote()
                    AppVisibility.show()
                }
                .keyboardShortcut("n")
                Button("Apagar nota atual", role: .destructive) { store.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                Divider()
                Button("Mostrar ou ocultar AntiScratch") { AppVisibility.toggle() }
                    .keyboardShortcut("a", modifiers: .option)
            }
        }

        MenuBarExtra("AntiScratch", systemImage: "note.text", isInserted: $showMenuBarIcon) {
            Button("Mostrar ou ocultar AntiScratch") { AppVisibility.toggle() }
                .keyboardShortcut("a", modifiers: .option)
            Button("Nova nota") {
                store.addNote()
                AppVisibility.show()
            }
                .keyboardShortcut("n")
            Button("Fechar janela") { AppVisibility.close() }
                .keyboardShortcut("w")
            Divider()
            Button("Ajustes…") {
                AppVisibility.show()
                NotificationCenter.default.post(name: .showAntiScratchSettings, object: nil)
            }
                .keyboardShortcut(",")
            Divider()
            Button("Encerrar AntiScratch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
enum AppVisibility {
    static func toggle() {
        let windows = appWindows
        if windows.contains(where: \.isVisible), NSApp.isActive {
            windows.forEach { $0.orderOut(nil) }
        } else {
            show()
        }
    }

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = appWindows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func close() {
        appWindows.forEach { $0.orderOut(nil) }
    }

    static func applyDockPreference() {
        let hidden = UserDefaults.standard.bool(forKey: "hideDockIcon")
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }

    private static var appWindows: [NSWindow] {
        NSApp.windows.filter { $0.canBecomeMain && !($0 is NSPanel) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotKey()
        AppVisibility.applyDockPreference()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { _ in
            Task { @MainActor in AppVisibility.applyDockPreference() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async { AppVisibility.toggle() }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        let signature = OSType(0x41534E54) // ASNT
        let identifier = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

extension Notification.Name {
    static let showAntiScratchSettings = Notification.Name("showAntiScratchSettings")
}

private struct WindowSizer: NSViewRepresentable {
    private static var didApplySize = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard !Self.didApplySize, let window = view.window else { return }
            Self.didApplySize = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.setContentSize(NSSize(width: 310, height: 378))
            window.center()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
