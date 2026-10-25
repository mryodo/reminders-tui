import AppKit
import ServiceManagement
import SwiftUI

@main
struct RemindApp: App {
    @State var store: Store

    init() {
        // Without this, `swift run` starts the app as a background process with no window.
        NSApplication.shared.setActivationPolicy(.regular)
        registerFonts()
        let store = Store()
        _store = State(initialValue: store)
        QuickPanel.shared = QuickPanel(store: store)
        // open at login from the first launch on, until turned off in Settings
        if !UserDefaults.standard.bool(forKey: "loginItemOffered"), Bundle.main.bundleURL.pathExtension == "app" {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
        }
    }

    var body: some Scene {
        WindowGroup("Remind") {
            ContentView().environment(store).frame(minWidth: 420, minHeight: 320)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Bigger Text") { store.fontSize += 1 }.keyboardShortcut("=")
                Button("Smaller Text") { store.fontSize -= 1 }.keyboardShortcut("-")
                Button("Default Text Size") { store.fontSize = 14 }.keyboardShortcut("0")
            }
            CommandGroup(replacing: .help) {
                Button("Keys") { store.help = true }.keyboardShortcut("/", modifiers: [.command, .shift])
            }
            CommandMenu("Reminders") {
                Button("New Reminder…") { store.ask = .add }.keyboardShortcut("n")
                Button("Quick Add From Anywhere  ⌥Z") { QuickPanel.shared?.show() }
                Button("Reload") { store.reload() }.keyboardShortcut("r")
                Divider()
                Button("Toggle Light / Dark") { store.toggleTheme() }.keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) { SettingsButton() }
        }
        // A plain Window rather than a Settings scene, so it can hide its title bar.
        Window("Settings", id: "settings") { SettingsView().environment(store) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @Environment(Store.self) var store
    @FocusState var listFocus: Bool
    @FocusState var searchFocus: Bool
    @State var hover = false     // the pointer is over the top of the list
    @State var searching = false

    var body: some View {
        @Bindable var store = store
        let p = store.p
        SwiftUI.Group {
            VStack(spacing: 0) {
                if store.icalBuddy != nil { EventsCard() }
                ScrollViewReader { proxy in
                    ScrollView {
                        list.padding(.horizontal, 36).padding(.top, store.icalBuddy == nil ? 56 : 28).padding(.bottom, 28).frame(maxWidth: 820).frame(maxWidth: .infinity)
                    }
                    .onChange(of: store.sel) { if let s = store.sel { withAnimation(.snappy) { proxy.scrollTo(s) } } }
                }
                if store.ask == .add || store.editing != nil { FormPanel().id(store.editing?.id ?? "new") }
                footer
            }
            .background(p.paper.opacity(store.opacity).ignoresSafeArea())
            .focusable().focused($listFocus).focusEffectDisabled()
            .onKeyPress(action: keys)
            // outside the focusable list, or the search field can't take focus
            .overlay(alignment: .topTrailing) { topBar }
            .onContinuousHover { phase in
                if case .active(let at) = phase { hover = at.y < 64 } else { hover = false }
            }
        }
        .background(Chrome(clear: store.opacity < 1, blur: store.blur, paper: p.paper))
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(NoTitle())
        .id("\(store.fontSize) \(store.fontFamily) \(store.fontStyle)") // read when views are built
        .sheet(isPresented: $store.help) { Help() }
        .sheet(isPresented: Binding(get: { store.sheet }, set: { if !$0 { store.ask = nil } })) {
            switch store.ask {
            case .delete(let r): DeleteSheet(r: r)
            case .lists(let t): ListsSheet(t: t)
            default: EmptyView()
            }
        }
        .preferredColorScheme(store.light ? .light : .dark)
        .tint(p.accent)
        .onAppear { listFocus = true }
        .onChange(of: store.ask == nil && store.inserting == nil) { if $1 { listFocus = true } }
        .onChange(of: store.query) { if store.selected == nil { store.sel = store.items().first?.id } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.reload() }
    }

    var list: some View {
        let p = store.p
        let shown = store.shown()
        let n = shown.reduce(0) { $0 + $1.items.count }
        return VStack(alignment: .leading, spacing: 10) {
            viewPills
            VStack(alignment: .leading, spacing: 4) {
                Caps(text: store.query.isEmpty ? plural(n, "reminder") : "\(plural(n, "reminder")) matching \(store.query)", color: p.inkSoft)
                HStack(alignment: .firstTextBaseline) {
                    Text(store.tab.name).font(display(24)).foregroundStyle(p.ink)
                    Spacer()
                    if store.tab.defaultLists != nil {
                        Button("Lists…") { store.ask = .lists(store.tab) }.buttonStyle(Pill(p: p)).help("Lists in this view (l)")
                    }
                }
            }
            if shown.isEmpty {
                if store.inserting != nil { QuickAdd() }
                Text(store.query.isEmpty ? store.tab.empty : "Nothing matches.")
                    .font(face(15)).foregroundStyle(p.inkSoft).padding(.top, 40).frame(maxWidth: .infinity)
            }
            ForEach(shown, id: \.title) { GroupView(g: $0) }
        }
    }

    /// The views, as the terminal's tab bar: a row of pills, scrolling when
    /// they don't fit.
    var viewPills: some View {
        let p = store.p
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tab.allCases) { t in
                        let on = t == store.tab
                        Button { store.show(t) } label: {
                            Text(Image(systemName: t.icon)) + Text(" " + t.name) + Text("  \(store.shown(t).reduce(0) { $0 + $1.items.count })").foregroundColor(on ? p.onButton.opacity(0.7) : p.inkSoft)
                        }
                        .buttonStyle(Pill(p: p, primary: on)).fixedSize()
                        .help("\(t.name) (\(t.rawValue + 1))")
                        .id(t)
                    }
                }
            }
            .onChange(of: store.tab) { withAnimation(.snappy) { proxy.scrollTo(store.tab) } }
        }
    }

    /// The new-reminder, theme and search buttons, shown while the pointer is
    /// near the top or a search is open.
    var topBar: some View {
        @Bindable var store = store
        let p = store.p
        let open = searching || !store.query.isEmpty
        func round(_ icon: String, _ help: String, _ tap: @escaping () -> Void) -> some View {
            Button(action: tap) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(p.raised)).overlay(Circle().strokeBorder(p.line))
            }.buttonStyle(.plain).help(help)
        }
        return HStack(spacing: 8) {
            if open {
                TextField("Search", text: $store.query)
                    .textFieldStyle(.plain).font(face(13)).foregroundStyle(p.ink)
                    .padding(.horizontal, 14).frame(width: 240, height: 32)
                    .background(Capsule().fill(p.raised)).overlay(Capsule().strokeBorder(p.line))
                    .focused($searchFocus)
                    .onAppear { DispatchQueue.main.async { searchFocus = true } } // it didn't exist yet when search opened
                    .onSubmit { searching = false; listFocus = true }
                    .onKeyPress(.escape) { closeSearch(); return .handled }
            }
            round("square.and.pencil", "New reminder (a)") { store.ask = .add }
            round(store.light ? "moon.fill" : "sun.max.fill", "Light / dark (b)") { store.toggleTheme() }
            round(open ? "xmark" : "magnifyingglass", "Search (/)") { open ? closeSearch() : openSearch() }
        }
        .padding(.top, 12).padding(.trailing, 16)
        .opacity(hover || open ? 1 : 0)
        .allowsHitTesting(hover || open)
        .animation(.easeOut(duration: 0.15), value: hover || open)
    }

    func openSearch() { searching = true; DispatchQueue.main.async { searchFocus = true } }
    func closeSearch() { searching = false; store.query = ""; listFocus = true }

    var footer: some View {
        let p = store.p
        let hints = [("j/k", "move"), ("x", "complete"), ("u", "undo"), ("i", "quick add"), ("a", "add"), ("e", "edit"), ("d", "delete"), ("/", "search"), ("?", "keys")]
        return HStack {
            if let e = store.error {
                Text(e).font(face(12, .medium)).foregroundStyle(p.red).lineLimit(1)
            } else if let s = store.status {
                Text("✓ " + s).font(face(12, .medium)).foregroundStyle(p.teal).lineLimit(1)
            } else {
                hints.reduce(Text("")) { $0 + Text($1.0).font(face(12, .bold)).foregroundColor(p.ink) + Text(" \($1.1)    ").font(face(12)).foregroundColor(p.inkSoft) }
                    .lineLimit(1)
            }
            Spacer()
            if store.loading { Caps(text: "refreshing…", color: p.inkSoft) }
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .background(p.sunk.opacity(0.6))
    }

    /// Opens a field after the key that asked for it is done, or the field,
    /// focused at once, gets the key's letter too.
    func later(_ open: @escaping () -> Void) { DispatchQueue.main.async(execute: open) }

    /// The terminal app's keys.
    func keys(_ k: KeyPress) -> KeyPress.Result {
        guard store.ask == nil, store.inserting == nil else { return .ignored }
        store.error = nil
        if !k.modifiers.subtracting([.shift, .numericPad, .function]).isEmpty { return .ignored }
        let c = k.characters
        switch c {
        case "j": store.step(1)
        case "k": store.step(-1)
        case "g": store.sel = store.items().first?.id
        case "G": store.sel = store.items().last?.id
        case "x", " ": store.complete()
        case "u": store.undo()
        case "i": later { store.insertParent = nil; store.inserting = store.section() }
        case "o": if let r = store.selected { later { store.insertParent = r; store.inserting = r.listName } }
        case "a": later { store.ask = .add }
        case "e": if let r = store.selected { later { store.ask = .edit(r) } }
        case "d": if let r = store.selected { store.ask = .delete(r) }
        case "/": openSearch()
        case "r": store.reload()
        case "c": store.eventsOpen.toggle()
        case "n": store.allNotes.toggle()
        case "l": if store.tab.defaultLists != nil { store.ask = .lists(store.tab) }
        case "b": store.toggleTheme()
        case "?": store.help = true
        case "q": NSApp.terminate(nil)
        case "\t": store.show(Tab(rawValue: (store.tab.rawValue + 1) % Tab.allCases.count)!)
        case "\u{1b}": closeSearch()
        case "1"..."8": store.show(Tab(rawValue: Int(c)! - 1)!)
        default:
            switch k.key {
            case .downArrow: store.step(1)
            case .upArrow: store.step(-1)
            default: return .ignored
            }
        }
        return .handled
    }
}

/// Today's events from Calendar, a title-card band across the top of the
/// window above every view: the first few, or all of them (c).
struct EventsCard: View {
    @Environment(Store.self) var store
    static let few = 4

    var body: some View {
        let c = store.p.onCard
        let all = store.events
        let shown = store.eventsOpen ? all : Array(all.prefix(EventsCard.few))
        let hm = fmt("HH:mm")
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label { Caps(text: "Today's events", color: c.inkSoft) } icon: {
                    Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.inkSoft)
                }
                Spacer()
                if all.count > EventsCard.few {
                    Button(store.eventsOpen ? "Fewer" : "+\(all.count - EventsCard.few) more") { store.eventsOpen.toggle() }.buttonStyle(Pill(p: c))
                }
            }
            if all.isEmpty { Text(store.loading ? "Loading…" : "No events today").font(face(15)).foregroundStyle(c.inkSoft) }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, ev in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    if store.eventIcons {
                        Image(systemName: ev.start == nil ? "sun.max" : "clock").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.accent).frame(width: 16)
                    }
                    Text(ev.start.map { s in hm.string(from: s) + "–" + (ev.end.map(hm.string) ?? "") } ?? "all day")
                        .font(face(13, .semibold)).foregroundStyle(c.accent).frame(width: 110, alignment: .leading)
                    Text(ev.title).font(face(15)).foregroundStyle(store.p.cardTitle ?? c.ink).lineLimit(1)
                    if !ev.location.isEmpty { Text("@ " + ev.location).font(face(13)).foregroundStyle(c.inkSoft).lineLimit(1) }
                }
            }
        }
        .padding(.horizontal, 36).padding(.top, 14).padding(.bottom, 22)
        .frame(maxWidth: 820).frame(maxWidth: .infinity)
        .background(Rectangle().fill(c.raised.opacity(store.opacity)).ignoresSafeArea(edges: .top))
        .shadow(color: .black.opacity(store.opacity < 1 ? 0 : 0.10), radius: 14, y: 8)
    }
}

/// A section of the view on its own card.
struct GroupView: View {
    @Environment(Store.self) var store
    let g: Group

    var body: some View {
        let p = store.p
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Caps(text: g.title, color: g.overdue ? p.red : p.accent, size: store.sectionTitleSize)
                Spacer()
                Caps(text: "\(g.items.count)", color: p.inkSoft)
            }
            .padding(.horizontal, 10).padding(.bottom, 1)
            let subs = subtasks(g.items)
            ForEach(g.items) { r in
                Row(r: r, nested: subs.contains(r.id))
                if store.inserting != nil && store.sel == r.id { QuickAdd() }
            }
        }
        .padding(store.cardPadding)
        .modifier(Raised(p: p, alpha: store.opacity, shown: store.cards, glass: store.glass))
    }
}

/// One reminder: its priority dot (click to complete), title and notes,
/// then when it's due and its list.
struct Row: View {
    @Environment(Store.self) var store
    let r: Reminder
    var nested = false

    var body: some View {
        let p = store.p
        let on = store.sel == r.id
        let overdue = r.overdue()
        let notes = store.allNotes || on ? stripTags(r.notes ?? "") : ""
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button { store.sel = r.id; store.complete() } label: {
                Circle().fill(p.priority(r.priority)).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(on ? p.accent : .clear, lineWidth: 2).padding(-3))
            }
            .buttonStyle(.plain).help("Complete (x)")
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(face(15, on || overdue ? .semibold : .regular)).foregroundStyle(overdue ? p.red : p.ink)
                if !notes.isEmpty { Text(notes).font(face(13)).italic().foregroundStyle(p.inkSoft).textSelection(.enabled) }
            }
            Spacer(minLength: 12)
            if let d = r.due { Text(relativeDate(d)).font(face(12, .semibold)).foregroundStyle(p.due(d)) }
            Text(r.listName).font(face(12)).foregroundStyle(p.list(r.listName)).lineLimit(1)
            if overdue {
                Text("OVERDUE").font(face(10, .bold)).tracking(1).foregroundStyle(p.onButton)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(p.red))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .padding(.leading, nested ? 28 : 0) // a subtask, under its parent
        // the selected reminder sits on a soft accent panel
        .background(RoundedRectangle(cornerRadius: 14).fill(on ? p.accent.opacity(0.08) : .clear))
        .animation(.easeOut(duration: 0.12), value: on)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.sel = r.id; store.ask = .edit(r) }
        .onTapGesture { store.sel = r.id }
        .contextMenu {
            Button("Complete") { store.sel = r.id; store.complete() }
            Button("Edit…") { store.ask = .edit(r) }
            Button("Delete…", role: .destructive) { store.ask = .delete(r) }
        }
        .id(r.id)
    }
}

/// i: a line opened under the selection, filing into its section's list.
struct QuickAdd: View {
    @Environment(Store.self) var store
    @State var line = ""
    @FocusState var focus: Bool

    var body: some View {
        let p = store.p
        let list = store.inserting ?? ""
        let what = store.insertParent.map { "Subtask of \($0.title)" } ?? (list.isEmpty ? "Quick add" : "Quick add to \(list)")
        VStack(alignment: .leading, spacing: 6) {
            Caps(text: what + " · ⏎ adds · esc cancels", color: p.accent)
            field("title @list !priority ~due #tag", $line, p)
                .focused($focus)
                .onSubmit { store.quickAdd(line) }
                .onKeyPress(.escape) { store.inserting = nil; store.insertParent = nil; return .handled }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .onAppear { DispatchQueue.main.async { focus = true } }
    }
}

/// Strips the window's title bar: no title, transparent, content up
/// to the top edge, and dragging by the background moves the window.
struct Chrome: NSViewRepresentable {
    var clear = false  // see-through, for the opacity setting
    var blur = 0.0     // and how much the desktop behind is blurred
    var buttons = true // the close, minimise and zoom buttons
    var paper: Color   // the theme's background, behind the title bar too
    final class V: NSView {
        var clear = false
        var blur = 0.0
        var buttons = true
        var paper = NSColor.windowBackgroundColor
        override func viewDidMoveToWindow() { style() }
        func style() {
            guard let w = window else { return }
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = !buttons }
            w.isOpaque = !clear
            w.backgroundColor = clear ? .clear : paper
            setBlur(w, clear ? blur : 0)
        }
    }
    func makeNSView(context: Context) -> V { let v = V(); updateNSView(v, context: context); return v }
    func updateNSView(_ v: V, context: Context) { v.clear = clear; v.blur = blur; v.buttons = buttons; v.paper = NSColor(paper); v.style() }
}

/// Blurs the desktop behind the window. There's no public API for this, so
/// like Ghostty, iTerm2 and Alacritty we call the window server's private
/// CGSSetWindowBackgroundBlurRadius. It's looked up at run time, so if a
/// future macOS drops it we just get no blur.
func setBlur(_ w: NSWindow, _ radius: Double) {
    typealias MainConnectionID = @convention(c) () -> UInt32
    typealias SetBlurRadius = @convention(c) (UInt32, UInt32, UInt32) -> Int32
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    guard w.windowNumber > 0,
          let connSym = dlsym(rtldDefault, "CGSMainConnectionID"),
          let blurSym = dlsym(rtldDefault, "CGSSetWindowBackgroundBlurRadius") else { return }
    let conn = unsafeBitCast(connSym, to: MainConnectionID.self)()
    let setBlurRadius = unsafeBitCast(blurSym, to: SetBlurRadius.self)
    _ = setBlurRadius(conn, UInt32(w.windowNumber), UInt32(max(0, radius)))
}

/// SettingsButton opens the settings window (⌘,).
struct SettingsButton: View {
    @Environment(\.openWindow) var openWindow
    var body: some View { Button("Settings…") { openWindow(id: "settings") }.keyboardShortcut(",") }
}

/// Keeps SwiftUI from putting the window title back in the bar.
struct NoTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.toolbar(removing: .title) } else { content.navigationTitle("") }
    }
}
