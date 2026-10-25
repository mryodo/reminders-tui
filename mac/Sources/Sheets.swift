// Sheets in Threader's style: confirming a delete, a view's lists and the
// keys; the add / edit panel; and the settings window.
import AppKit
import ServiceManagement
import SwiftUI

/// The shared look: a label, a heading, content on paper.
struct SheetFrame<Content: View>: View {
    @Environment(Store.self) var store
    let label: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        let p = store.p
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Caps(text: label, color: p.inkSoft)
                Text(title).font(display(22)).foregroundStyle(p.ink).lineLimit(1)
            }
            content
        }
        .padding(28)
        .frame(width: 520)
        .background(p.paper)
    }
}

/// A capsule text field on the raised card colour.
func field(_ prompt: String, _ text: Binding<String>, _ p: Palette) -> some View {
    TextField("", text: text, prompt: Text(prompt).foregroundColor(p.inkSoft))
        .textFieldStyle(.plain).font(face()).foregroundStyle(p.ink)
        .padding(.horizontal, 18).frame(height: 44)
        .background(Capsule().fill(p.raised)).overlay(Capsule().strokeBorder(p.line))
}

/// a and e: the terminal app's form, docked at the bottom of the window
/// as it was there. ⏎ goes title → list → due and saves from there (and
/// from notes, where ⌥⏎ breaks a line); esc cancels.
struct FormPanel: View {
    @Environment(Store.self) var store
    @State var f = Fields()
    @State var query = "" // typed into the list field, to filter the lists
    @State var hi = 0     // the highlighted match
    @FocusState var focus: Field?
    enum Field { case title, list, due, notes }

    var editing: Reminder? { if case .edit(let r) = store.ask { r } else { nil } }

    /// The lists matching what's typed, all of them before anything is.
    var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? store.lists : store.lists.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let p = store.p
        let picking = focus == .list
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Caps(text: editing == nil ? "New reminder" : "Edit reminder", color: p.accent).fixedSize()
                Spacer()
                Caps(text: picking ? "type to filter · ↑↓ choose · ⏎ takes it" : "⏎ next · ⌥⏎ new line · esc cancels", color: p.inkSoft).lineLimit(1) // shortened when narrow
            }
            plain("Title", $f.title, display(18)).focused($focus, equals: .title)
                .onSubmit { if editing == nil { focus = .list } else { save() } }
            HStack(spacing: 12) {
                if editing == nil {
                    TextField("", text: $query, prompt: Text(f.list.isEmpty ? "List" : f.list).foregroundColor(picking ? p.inkSoft : p.ink))
                        .textFieldStyle(.plain).font(face(13)).foregroundStyle(p.ink)
                        .focused($focus, equals: .list)
                        .onSubmit(pick)
                        .onChange(of: query) { hi = 0 }
                        .onKeyPress(.downArrow) { hi = min(hi + 1, max(matches.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { hi = max(hi - 1, 0); return .handled }
                        .padding(.trailing, 18).frame(minWidth: 70, maxWidth: 180)
                        .overlay(alignment: .trailing) {
                            Menu {
                                ForEach(store.lists, id: \.self) { l in Button(l) { f.list = l } }
                            } label: { Image(systemName: "chevron.down") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(p.inkSoft)
                        }
                }
                plain(editing?.due.map { "Due \(relativeDate($0))" } ?? "Due: friday, tomorrow 14:00", $f.due, face(13))
                    .focused($focus, equals: .due).onSubmit(save)
                    .frame(minWidth: 90, maxWidth: 220)
                priorities
            }
            if picking { suggestions }
            plain("Notes", $f.notes, face(13), lines: 4).focused($focus, equals: .notes).onSubmit(save)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: 820).frame(maxWidth: .infinity)
        .background(p.raised)
        .overlay(alignment: .top) { Rectangle().fill(p.line).frame(height: 1) }
        .onExitCommand { store.ask = nil }
        .onChange(of: focus) { _, now in
            if now == .list { query = ""; hi = store.lists.firstIndex(of: f.list) ?? 0 }
        }
        .onAppear {
            if let r = editing {
                f = Fields(title: r.title, priority: r.priority, notes: r.notes ?? "")
            } else {
                f = Fields(list: defaultList, priority: "none", notes: thisWeekTag)
            }
            DispatchQueue.main.async { focus = .title }
        }
    }

    /// The priority as the list draws it: a coloured dot each, the chosen one ringed.
    var priorities: some View {
        let p = store.p
        return HStack(spacing: 2) {
            ForEach(Fields.priorities, id: \.self) { name in
                Button { f.priority = name } label: {
                    Circle().fill(p.priority(name)).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(f.priority == name ? p.accent : .clear, lineWidth: 2).padding(-4))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(name)
            }
        }
        .fixedSize()
    }

    /// The lists matching the list field, the highlighted one filled.
    var suggestions: some View {
        let p = store.p
        let m = matches
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if m.isEmpty { Text("no list matches").font(face(12)).foregroundStyle(p.inkSoft) }
                    ForEach(Array(m.enumerated()), id: \.offset) { i, l in
                        Text(l).font(face(12, .semibold)).foregroundStyle(i == hi ? p.onButton : p.ink)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(i == hi ? p.button : p.sunk))
                            .onTapGesture { hi = i; pick() }
                            .id(i)
                    }
                }
            }
            .onChange(of: hi) { withAnimation(.snappy) { proxy.scrollTo(hi) } }
        }
    }

    /// Takes the highlighted list, then moves on to the due date.
    func pick() {
        let m = matches
        if m.indices.contains(hi) { f.list = m[hi] }
        query = ""
        focus = .due
    }

    /// A borderless field: just the text, its prompt soft.
    func plain(_ prompt: String, _ text: Binding<String>, _ font: Font, lines: Int = 1) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundColor(store.p.inkSoft), axis: lines > 1 ? .vertical : .horizontal)
            .lineLimit(1...lines)
            .textFieldStyle(.plain).font(font).foregroundStyle(store.p.ink)
    }

    func save() {
        f.title = f.title.trimmingCharacters(in: .whitespaces)
        f.due = f.due.trimmingCharacters(in: .whitespaces)
        f.notes = f.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.title.isEmpty else { focus = .title; return }
        if let r = editing { store.edit(r, f) } else { store.add(f) }
        store.ask = nil
    }
}

/// d: y deletes, any other key keeps it, as in the terminal.
struct DeleteSheet: View {
    @Environment(Store.self) var store
    let r: Reminder
    @FocusState var focus: Bool

    var body: some View {
        let p = store.p
        SheetFrame(label: "Delete reminder", title: r.title) {
            HStack(spacing: 8) {
                Caps(text: "y deletes · any other key keeps it", color: p.inkSoft)
                Spacer()
                Button("Keep") { store.ask = nil }.buttonStyle(Pill(p: p))
                Button("Delete") { store.delete(r) }.buttonStyle(Pill(p: p, primary: true))
            }
        }
        .focusable().focused($focus).focusEffectDisabled()
        .onKeyPress { k in
            if k.characters.lowercased() == "y" { store.delete(r) } else { store.ask = nil }
            return .handled
        }
        .onAppear { DispatchQueue.main.async { focus = true } }
    }
}

/// l: picks the lists a fixed view shows. j k move, space or ⏎ adds or
/// removes, esc closes.
struct ListsSheet: View {
    @Environment(Store.self) var store
    let t: Tab
    @State var sel = 0
    @FocusState var focus: Bool

    var body: some View {
        let p = store.p
        let on = store.included(t)
        let all = on + store.lists.filter { !on.contains($0) }.sorted() // shown ones first, in their order
        SheetFrame(label: "Lists in", title: t.name) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(all.enumerated()), id: \.offset) { i, l in
                            row(i, l, on.contains(l)).id(i).onTapGesture { sel = i; store.toggle(l, in: t) }
                        }
                    }
                }
                .frame(maxHeight: 420)
                .onChange(of: sel) { proxy.scrollTo(sel) }
            }
            HStack(spacing: 8) {
                Caps(text: "j k move · space adds or removes · esc", color: p.inkSoft)
                Spacer()
                Button("Reset") { store.viewLists[t.name] = nil }.buttonStyle(Pill(p: p)).disabled(store.viewLists[t.name] == nil)
                Button("Done") { store.ask = nil }.buttonStyle(Pill(p: p, primary: true))
            }
        }
        .focusable().focused($focus).focusEffectDisabled()
        .onKeyPress { k in
            switch (k.key, k.characters) {
            case (.downArrow, _), (_, "j"): sel = min(sel + 1, all.count - 1)
            case (.upArrow, _), (_, "k"): sel = max(sel - 1, 0)
            case (.return, _), (_, " "): if all.indices.contains(sel) { store.toggle(all[sel], in: t) }
            case (.escape, _), (_, "q"), (_, "l"): store.ask = nil
            default: return .ignored
            }
            return .handled
        }
        .onAppear { DispatchQueue.main.async { focus = true } }
    }

    func row(_ i: Int, _ name: String, _ shown: Bool) -> some View {
        let p = store.p
        let cur = i == sel
        return HStack(spacing: 12) {
            Image(systemName: shown ? "checkmark.circle.fill" : "circle").foregroundStyle(cur ? p.onButton : p.accent).frame(width: 20)
            Text(name).font(face(15, .semibold)).foregroundStyle(cur ? p.onButton : p.ink).lineLimit(1)
            Spacer()
            Text("\(store.reminders.filter { !$0.isCompleted && $0.listName == name }.count)").font(face(12, .semibold))
                .foregroundStyle(cur ? p.onButton.opacity(0.75) : p.inkSoft)
        }
        .padding(.horizontal, 18).frame(height: 44)
        .background(Capsule().fill(cur ? p.button : p.raised))
        .overlay(Capsule().strokeBorder(cur ? .clear : p.line))
        .contentShape(Capsule())
    }
}

/// Lists the keys.
struct Help: View {
    @Environment(Store.self) var store
    @FocusState var focus: Bool

    static let keys: [(String, String)] = [
        ("", "List"),
        ("j k  g G", "move · first / last"),
        ("x space  u", "complete · undo the last completion"),
        ("i", "quick add: title @list !priority ~due #tag"),
        ("⌥Z", "quick add from any app, while Remind runs"),
        ("o", "quick add a subtask of the selected (#sub:<id> in its notes)"),
        ("a  e  d", "add · edit · delete"),
        ("1–8  tab", "This Week, Today, Upcoming, Lists, Teaching, Research, Habits, Tasks · next"),
        ("/  esc", "search · clear"),
        ("r", "reload reminders and events"),
        ("c  n", "all of today's events · notes for all or the selected"),
        ("l", "the lists Teaching, Research, Habits or Tasks show"),
        ("b", "light / dark"),
        ("⌘+ ⌘−  ⌘0", "text size · default"),
        ("?  q", "keys · quit"),
        ("", "Due dates"),
        ("friday  tue 9:30", "the next one, today included"),
        ("tomorrow 14:00", "or today, remindctl's YYYY-MM-DD[ HH:mm] …"),
    ]

    var body: some View {
        let p = store.p
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Help.keys.enumerated()), id: \.offset) { _, kv in
                if kv.0.isEmpty {
                    Caps(text: kv.1, color: p.accent).padding(.top, 10)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(kv.0).font(face(13, .bold)).foregroundStyle(p.ink).frame(width: 170, alignment: .leading)
                        Text(kv.1).font(face(13)).foregroundStyle(p.inkSoft)
                    }
                }
            }
            TextSettings()
            HStack {
                Spacer()
                Button("Close") { store.help = false }.buttonStyle(Pill(p: p, primary: true))
            }
        }
        .padding(28)
        .frame(width: 620)
        .background(p.paper)
        .focusable().focused($focus).focusEffectDisabled()
        .onKeyPress { _ in store.help = false; return .handled } // any key closes, as in the terminal
        .onAppear { focus = true }
    }
}

/// The keys window's layout: a bold label in a fixed column, then
/// the rest. Settings uses it too, so the two windows match.
func row<C: View>(_ label: String, _ p: Palette, @ViewBuilder _ content: () -> C) -> some View {
    HStack(alignment: .center, spacing: 16) {
        Text(label).font(face(13, .bold)).foregroundStyle(p.ink).frame(width: 170, alignment: .leading)
        content()
    }
}

/// A heading in the keys window's style.
func section(_ title: String, _ p: Palette) -> some View { Caps(text: title, color: p.accent).padding(.top, 10) }

/// The font family and size, in the keys sheet and ⌘,.
struct TextSettings: View {
    @Environment(Store.self) var store

    // monospaced families first: lists read best in one
    static let families: (mono: [String], other: [String]) = {
        let fm = NSFontManager.shared
        let all = fm.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()
        let mono = all.filter { fm.font(withFamily: $0, traits: [], weight: 5, size: 12)?.isFixedPitch == true }
        return (mono, all.filter { !mono.contains($0) })
    }()

    var body: some View {
        let p = store.p
        VStack(alignment: .leading, spacing: 8) {
            section("Text", p)
            row("Font", p) {
                Menu {
                    Section("Monospaced") { ForEach(TextSettings.families.mono, id: \.self) { f in Button(f) { store.fontFamily = f } } }
                    Section("Other") { ForEach(TextSettings.families.other, id: \.self) { f in Button(f) { store.fontFamily = f } } }
                } label: {
                    Text(store.fontFamily + "  ▾").font(face(13, .semibold)).foregroundStyle(p.ink)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(p.sunk))
            }
            row("Style", p) {
                let styles = fontStyles(store.fontFamily).map(\.style)
                Menu {
                    ForEach(styles, id: \.self) { st in Button(st) { store.fontStyle = st } }
                } label: {
                    Text((styles.contains(store.fontStyle) ? store.fontStyle : "Regular") + "  ▾").font(face(13, .semibold)).foregroundStyle(p.ink)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(p.sunk))
                .disabled(styles.count < 2)
            }
            row("Size", p) {
                Button("−") { store.fontSize -= 1 }.buttonStyle(Pill(p: p))
                Text("\(Int(store.fontSize)) pt").font(face(13, .bold)).foregroundStyle(p.ink).frame(width: 52)
                Button("+") { store.fontSize += 1 }.buttonStyle(Pill(p: p))
                Text("⌘+ ⌘− ⌘0").font(face(13)).foregroundStyle(p.inkSoft)
            }
        }
    }
}

/// ⌘,: text, theme, window opacity and blur, and the events card, laid
/// out like the keys window.
struct SettingsView: View {
    @Environment(Store.self) var store
    @State var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var store = store
        let p = store.p
        VStack(alignment: .leading, spacing: 8) {
            TextSettings()
            section("Theme", p)
            HStack(spacing: 8) {
                ForEach(Palette.themes, id: \.name) { t in
                    Button {
                        store.theme = t.name
                        UserDefaults.standard.set(t.name, forKey: "theme")
                    } label: {
                        HStack(spacing: 7) {
                            Circle().fill(t.palette.card).frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(t.palette.paper, lineWidth: 2))
                            Text(t.name)
                        }
                    }.buttonStyle(Pill(p: p, primary: store.theme == t.name)).fixedSize()
                }
                Text("b flips light ↔ dark").font(face(13)).foregroundStyle(p.inkSoft)
            }
            section("Window", p)
            row("Opacity", p) {
                Slider(value: $store.opacity, in: 0.3...1).tint(p.accent)
                Text(store.opacity >= 1 ? "solid" : "\(Int(store.opacity * 100))%").font(face(13)).foregroundStyle(p.inkSoft).frame(width: 96, alignment: .trailing)
            }
            row("Blur", p) {
                Slider(value: $store.blur, in: 0...40).tint(p.accent)
                Text(store.opacity >= 1 ? "when see-through" : store.blur < 1 ? "none" : "\(Int(store.blur)) px").font(face(13)).foregroundStyle(p.inkSoft).frame(width: 96, alignment: .trailing)
            }
            .disabled(store.opacity >= 1)
            row("Open at login", p) {
                Toggle("", isOn: $login).toggleStyle(.switch).labelsHidden().tint(p.accent)
                    .onChange(of: login) { _, on in
                        _ = try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        login = SMAppService.mainApp.status == .enabled
                    }
                Text("so ⌥Z quick add is always there").font(face(13)).foregroundStyle(p.inkSoft)
            }
            section("Today's events", p)
            row("Icons", p) {
                Toggle("", isOn: $store.eventIcons).toggleStyle(.switch).labelsHidden().tint(p.accent)
                Text(store.eventIcons ? "a sun all day, a clock for timed ones" : "times only").font(face(13)).foregroundStyle(p.inkSoft)
            }
        }
        .padding(28)
        .frame(width: 620)
        .background(p.paper.ignoresSafeArea())
        .background(Chrome(buttons: false, paper: p.paper)) // no title bar at all: ⌘W closes it
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(NoTitle())
        .preferredColorScheme(store.light ? .light : .dark)
    }
}
