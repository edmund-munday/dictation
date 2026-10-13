import AppKit
import DictationCore
import SwiftUI

/// Non-activating floating panel near the bottom of the screen showing the core's panel state.
final class FloatingPanelController {
    var onButton: ((String) -> Void)?
    private var panel: NSPanel?
    private let model = PanelViewModel()

    func show(_ state: PanelState) {
        model.state = state
        guard state.isVisible else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = NSSize(width: 460, height: 90)
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 80,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 90),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: PanelView(model: model) { [weak self] title in
            self?.onButton?(title)
        })
        return panel
    }
}

final class PanelViewModel: ObservableObject {
    @Published var state = PanelState.hidden
}

struct PanelView: View {
    @ObservedObject var model: PanelViewModel
    let onButton: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            Text(model.state.text ?? "")
                .font(.system(size: 15))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(model.state.buttons, id: \.title) { button in
                Button(button.title) { onButton(button.title) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
