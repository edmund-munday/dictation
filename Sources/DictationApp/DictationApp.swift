import AppKit
import DictationMac
import SwiftUI

@main
struct DictationMenuBarApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.statusSymbol)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(model.menuTitle) { model.toggleEnabled() }
        Text(model.coreMenuText)
        Divider()
        Text(model.speechLabel)
        Text(model.cleanupLabel)
        Button("Re-check cleanup CLIs") { model.rechooseCleanup() }
        Toggle("Auto-send in chat apps", isOn: Binding(get: { model.autoSendEnabled },
                                                        set: { model.setAutoSend($0) }))
        Toggle("Save dictations for tuning", isOn: Binding(get: { model.saveDictations },
                                                           set: { model.setSaveDictations($0) }))
        Button("Reveal dictation log folder") { model.revealCorpusFolder() }
        Menu("Plugins") {
            ForEach(model.pluginList, id: \.name) { plugin in
                Toggle(plugin.name, isOn: Binding(get: { plugin.enabled },
                                                  set: { model.setPlugin(plugin.name, enabled: $0) }))
            }
            ForEach(model.pluginErrors.keys.sorted(), id: \.self) { file in
                Text("⚠︎ \(file): \(model.pluginErrors[file] ?? "")")
            }
            Divider()
            Button("Reload plugins") { model.reloadPlugins() }
            Button("Open plugins folder") { model.openPluginsFolder() }
        }
        Divider()
        Text("Permissions: " + model.permissions.summary)
        ForEach(model.permissions.missing, id: \.self) { kind in
            Button("Open \(kind.title) settings…") { model.open(kind) }
        }
        if !model.tapRunning {
            Text("Talk key inactive until Input Monitoring is allowed.")
        }
        Button("Refresh permissions") { model.refreshPermissions() }
        Divider()
        Text("Hold left Command to talk. Ctrl-Opt-Space toggles.")
        Button("Quit Dictation") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
