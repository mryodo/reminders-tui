// ⌥Z from anywhere, while Remind runs: a floating quick-add line in i's
// syntax, into Tasks unless it says @list. A Carbon hot key, so it needs no
// accessibility permission.
import AppKit
import Carbon.HIToolbox
import SwiftUI

final class QuickPanel {
    static var shared: QuickPanel?
    let store: Store
    let panel = KeyPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
    var hotKey: EventHotKeyRef?

    init(store: Store) {
        self.store = store
        panel.backgroundColor = .clear // the view draws its own rounded card
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in self?.hide() }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { QuickPanel.shared?.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_Z), UInt32(optionKey), EventHotKeyID(signature: 0x524d_4e44, id: 1), // "RMND"
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    func toggle() { panel.isVisible ? hide() : show() }

    /// Opens a fresh line in the upper third of the screen the pointer is on.
    func show() {
        let view = NSHostingView(rootView: QuickPanelView { [weak self] in self?.hide() }.environment(store))
        panel.contentView = view
        panel.setContentSize(view.fittingSize)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height / 3))
        }
        panel.makeKeyAndOrderFront(nil) // key without activating Remind, as Spotlight does
    }

    func hide() { panel.orderOut(nil) }
}

/// A panel that takes typing although it doesn't activate the app.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct QuickPanelView: View {
    @Environment(Store.self) var store
    let close: () -> Void
    @State var line = ""
    @State var hi = 0 // the highlighted list while completing an @list
    @FocusState var focus: Bool

    /// The lists for the @list being typed, if one is.
    var matches: [String]? {
        typingList(line).map { q in q.isEmpty ? store.lists : store.lists.filter { $0.localizedCaseInsensitiveContains(q) } }
    }

    var body: some View {
        let p = store.p
        let f = parseQuickAdd(line)
        let m = matches
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(.white, .blue).frame(height: 44)
                field("title @list !priority ~due #tag", $line, p)
                    .focused($focus)
                    .onChange(of: line) { hi = 0 }
                    .onKeyPress(.downArrow) { m == nil ? .ignored : { hi = min(hi + 1, max(m!.count - 1, 0)); return .handled }() }
                    .onKeyPress(.upArrow) { m == nil ? .ignored : { hi = max(hi - 1, 0); return .handled }() }
                    .onKeyPress(.tab) { complete(m) }
                    .onKeyPress(.return) { complete(m) }
                    .onSubmit {
                        guard !f.title.isEmpty else { return }
                        store.add(f)
                        close()
                    }
            }
            if let m { suggestions(m) }
            HStack {
                // what ⏎ will do
                Caps(text: ["into " + (f.list.isEmpty ? defaultList : f.list), f.due.isEmpty ? "" : "due " + f.due,
                            f.priority.isEmpty ? "" : f.priority + " priority"].filter { !$0.isEmpty }.joined(separator: " · "), color: p.inkSoft)
                Spacer()
                Caps(text: m == nil ? "⏎ adds · esc closes" : "↑↓ choose · tab or ⏎ completes", color: p.inkSoft)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 18).fill(p.paper.opacity(store.opacity)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(p.line))
        .onExitCommand(perform: close)
        .preferredColorScheme(store.light ? .light : .dark)
        .tint(p.accent)
        .onAppear { DispatchQueue.main.async { focus = true } }
    }

    /// Finishes the @list being typed with the highlighted list, if there's one.
    func complete(_ m: [String]?) -> KeyPress.Result {
        guard let m, m.indices.contains(hi) else { return .ignored }
        line = completeList(line, m[hi])
        return .handled
    }

    /// The lists matching the @list being typed, the highlighted one filled.
    func suggestions(_ m: [String]) -> some View {
        let p = store.p
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if m.isEmpty { Text("no list matches").font(face(12)).foregroundStyle(p.inkSoft) }
                    ForEach(Array(m.enumerated()), id: \.offset) { i, l in
                        Text(l).font(face(12, .semibold)).foregroundStyle(i == hi ? p.onButton : p.ink)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(i == hi ? p.button : p.sunk))
                            .onTapGesture { hi = i; _ = complete(m) }
                            .id(i)
                    }
                }
            }
            .onChange(of: hi) { withAnimation(.snappy) { proxy.scrollTo(hi) } }
        }
    }
}
