// Reminders come from remindctl and today's events from icalBuddy, shelled
// out to exactly as the terminal app does: no EventKit here either.
import Foundation
import Observation

struct Reminder: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var dueDate: String?
    var isCompleted: Bool
    var listName: String
    var priority: String
    var notes: String?

    var due: Date? { dueDate.flatMap { iso.date(from: $0) } }
    var short: String { String(id.prefix(8)) } // remindctl takes an id prefix
    func overdue(_ now: Date = Date()) -> Bool { !isCompleted && due.map { day($0) < day(now) } == true }
    func dueToday(_ now: Date = Date()) -> Bool { !isCompleted && due.map { day($0) == day(now) } == true }
    func matches(_ q: String) -> Bool { [title, listName, notes ?? ""].contains { $0.localizedCaseInsensitiveContains(q) } }
}

struct Event: Hashable {
    var title = ""
    var location = ""
    var start, end: Date? // nil all day
}

/// The fields of a new or edited reminder.
struct Fields: Equatable {
    var title = "", list = "", priority = "", due = "", notes = ""

    static let priorities = ["none", "low", "medium", "high"] // remindctl's
}

let cal = Calendar.current
let iso = ISO8601DateFormatter()
func day(_ d: Date) -> Date { cal.startOfDay(for: d) }
func fmt(_ pattern: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = pattern
    return f
}

/// Returns the capture groups of the first match of `re` in `s` (group 0 is
/// the whole match, unmatched groups are ""), or nil if there is no match.
func groups(_ re: NSRegularExpression, _ s: String) -> [String]? {
    guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
    }
}

extension Array {
    /// Sorted by key, keeping the original order among equal keys.
    func sorted<K: Comparable>(on key: (Element) -> K) -> [Element] {
        enumerated().sorted { (key($0.element), $0.offset) < (key($1.element), $1.offset) }.map(\.element)
    }
}

func plural(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }

// MARK: Tags, quick add and due dates

/// Pulls a reminder into This Week whatever its due date. New reminders get
/// it by default; it's hidden when notes are shown.
let thisWeekTag = "#thisweek"
/// The tags Remind uses itself, hidden when notes are shown.
let ownTagsRe = try! NSRegularExpression(pattern: #"(?i)#thisweek\b|#sub:\S+"#)

func hasThisWeekTag(_ r: Reminder) -> Bool {
    (r.title + " " + (r.notes ?? "")).lowercased().contains(thisWeekTag)
}

/// Notes without #thisweek and #sub:…: a line of only tags goes, others lose them.
func stripTags(_ notes: String) -> String {
    notes.components(separatedBy: "\n").compactMap { line in
        guard ownTagsRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { return line }
        let s = ownTagsRe.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
        let cleaned = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// A subtask says #sub:<its parent's id prefix> in its notes; Reminders
/// itself has no subtasks that EventKit can see.
let subRe = try! NSRegularExpression(pattern: #"#sub:([0-9A-Za-z]{8})"#)
func parentID(_ r: Reminder) -> String? { groups(subRe, r.notes ?? "").map { $0[1].uppercased() } }

/// The ids of the subtasks among items whose parent is there too and is not
/// itself one of them: one level, so a loop of #sub tags can't hide anything.
func subtasks(_ items: [Reminder]) -> Set<String> {
    let byShort = Dictionary(items.map { ($0.short.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
    return Set(items.filter { r in
        guard let p = parentID(r).flatMap({ byShort[$0] }) else { return false }
        return parentID(p).flatMap { byShort[$0] } == nil
    }.map(\.id))
}

/// items with each subtask moved right under its parent.
func nest(_ items: [Reminder]) -> [Reminder] {
    let subs = subtasks(items)
    return items.filter { !subs.contains($0.id) }.flatMap { p in
        [p] + items.filter { subs.contains($0.id) && parentID($0) == p.short.uppercased() }
    }
}

/// @list !priority ~due #tag, a value quoted to hold spaces: ~"next monday".
let tokenRe = try! NSRegularExpression(pattern: #"([@!~#])(?:"([^"]*)"|(\S+))"#)

/// Splits a quick-add line into its fields; the rest is the title. Tags go
/// to notes, #thisweek if there are none, as the add form prefills.
func parseQuickAdd(_ line: String) -> Fields {
    var f = Fields(), tags: [String] = [], title = ""
    let ns = line as NSString
    var last = 0
    for m in tokenRe.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
        title += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        last = NSMaxRange(m.range)
        let value = ns.substring(with: m.range(at: m.range(at: 2).location != NSNotFound ? 2 : 3))
        switch ns.substring(with: m.range(at: 1)) {
        case "@": f.list = value
        case "!": f.priority = value
        case "~": f.due = value
        default: tags.append("#" + value)
        }
    }
    title += ns.substring(from: last)
    f.title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    f.notes = tags.isEmpty ? thisWeekTag : tags.joined(separator: " ")
    return f
}

/// An @list being typed at the end of a quick-add line: @Ta, or @"✍︎ Ta.
let atRe = try! NSRegularExpression(pattern: #"(?:^|\s)@(?:"([^"]*)|([^\s"]*))$"#)

/// What's typed of the @list at the end of line, or nil if it isn't one.
func typingList(_ line: String) -> String? {
    groups(atRe, line).map { $0[1] + $0[2] }
}

/// line with the @list being typed finished as list, quoted if it has spaces.
func completeList(_ line: String, _ list: String) -> String {
    guard let m = atRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return line }
    let at = (line as NSString).range(of: "@", options: .backwards, range: m.range)
    return (line as NSString).replacingCharacters(in: NSRange(location: at.location, length: NSMaxRange(m.range) - at.location),
                                                  with: "@" + (list.contains(" ") ? "\"\(list)\"" : list) + " ")
}

let weekdays = ["sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
                "wed": 4, "weds": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
                "fri": 6, "friday": 6, "sat": 7, "saturday": 7]
let dueRe = try! NSRegularExpression(pattern: #"(?i)^(today|tomorrow|\#(weekdays.keys.joined(separator: "|")))(?:\s+(\d{1,2}):(\d{2}))?$"#)

/// Rewrites a weekday ("friday": its next one, today included) or
/// today/tomorrow with a time into remindctl's "YYYY-MM-DD[ HH:mm]".
/// Anything else passes through for remindctl to read or reject.
func normalizeDue(_ due: String, _ now: Date = Date()) -> String {
    guard let g = groups(dueRe, due.trimmingCharacters(in: .whitespaces)) else { return due }
    let word = g[1].lowercased(), hh = g[2]
    let offset: Int
    switch word {
    case "today", "tomorrow":
        if hh.isEmpty { return due } // remindctl knows these itself
        offset = word == "today" ? 0 : 1
    default:
        offset = (weekdays[word]! - cal.component(.weekday, from: now) + 7) % 7
    }
    let date = fmt("yyyy-MM-dd").string(from: cal.date(byAdding: .day, value: offset, to: now)!)
    if hh.isEmpty { return date }
    guard let h = Int(hh), let m = Int(g[3]), h < 24, m < 60 else { return due }
    return date + String(format: " %02d:%02d", h, m)
}

/// "today", "in 3 days", "next week", else the date.
func relativeDate(_ due: Date, _ now: Date = Date()) -> String {
    let days = cal.dateComponents([.day], from: day(now), to: day(due)).day!
    switch days {
    case 0: return "today"
    case 1: return "tomorrow"
    case -1: return "yesterday"
    case 2...7: return "in \(days) days"
    case -7 ... -2: return "\(-days) days ago"
    case 8...14: return "next week"
    default: return fmt(cal.isDate(due, equalTo: now, toGranularity: .year) ? "EEE MMM d" : "MMM d, yyyy").string(from: due)
    }
}

// MARK: Views

enum Tab: Int, CaseIterable, Identifiable {
    case thisWeek, today, upcoming, lists, teaching, research, habits, tasks
    var id: Int { rawValue }

    var name: String { ["This Week", "Today", "Upcoming", "Lists", "Teaching", "Research", "Habits", "Tasks"][rawValue] }
    var icon: String { ["calendar", "sun.max", "calendar.badge.clock", "list.bullet", "graduationcap", "flask", "repeat", "checklist"][rawValue] }

    /// The Reminders lists, in order, the fixed views show until changed (l).
    var defaultLists: [String]? {
        switch self {
        case .teaching: ["♨︎ Statistics", "✾ I2CN", "✒︎ Thesis", "⛵︎ Seminar", "⛲︎ DPN"]
        case .research: ["☋ Grassman Interpolation", "⚔︎ Joint Sparsification", "⚖︎ Effective Resistances", "⛽︎ GNN convergence"]
        case .habits: ["Habits"]
        case .tasks: ["✍︎ Tasks"]
        default: nil
        }
    }

    var empty: String {
        switch self {
        case .today: "Nothing due today — nice!"
        case .upcoming: "Nothing coming up this week"
        case .thisWeek: "Nothing scheduled for this week"
        default: "No reminders"
        }
    }
}

/// A section of a view; list is set when it's one Reminders list, so
/// quick add can file into it.
struct Group: Hashable {
    var title: String
    var overdue = false
    var list: String?
    var items: [Reminder]
}

/// Where a new reminder goes when nothing says otherwise.
let defaultList = "✍︎ Tasks"

let priorityRank = ["high": 0, "medium": 1, "low": 2]
func byPriority(_ rs: [Reminder]) -> [Reminder] { rs.sorted(on: { priorityRank[$0.priority] ?? 3 }) }

/// One group per list, by name.
func byList(_ rs: [Reminder]) -> [Group] {
    Dictionary(grouping: rs, by: \.listName).sorted { $0.key < $1.key }
        .map { Group(title: $0.key, list: $0.key, items: byPriority($0.value)) }
}

/// The incomplete reminders `rs` as `tab` groups them; a fixed view shows `lists`.
func sections(_ tab: Tab, _ rs: [Reminder], _ now: Date = Date(), lists: [String]? = nil) -> [Group] {
    let overdue = rs.filter { $0.overdue(now) }
    let overdueGroup = overdue.isEmpty ? [] : [Group(title: "Overdue", overdue: true, items: byPriority(overdue))]
    var out: [Group]
    switch tab {
    case .today:
        out = overdueGroup + [Group(title: "Due today", items: byPriority(rs.filter { $0.dueToday(now) })),
                              Group(title: "No due date", items: rs.filter { $0.due == nil })]
    case .upcoming:
        let end = cal.date(byAdding: .day, value: 8, to: day(now))!
        let days = Dictionary(grouping: rs.filter { r in r.due.map { day($0) >= day(now) && day($0) < end } == true }) { day($0.due!) }
        out = overdueGroup + days.sorted { $0.key < $1.key }.map { d, rs in
            let rel = relativeDate(d, now)
            return Group(title: rel == "today" || rel == "tomorrow" ? rel.capitalized : fmt("EEE MMM d").string(from: d), items: byPriority(rs))
        }
    case .lists:
        out = byList(rs)
    case .thisWeek:
        let start = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: now) + 5) % 7), to: day(now))! // Monday
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        out = overdueGroup + byList(rs.filter { r in
            !r.overdue(now) && (r.due.map { $0 >= start && $0 < end } == true || hasThisWeekTag(r))
        })
    default:
        let byName = Dictionary(grouping: rs, by: \.listName)
        out = (lists ?? tab.defaultLists!).map { Group(title: $0, list: $0, items: byPriority(byName[$0] ?? [])) }
    }
    return out.filter { !$0.items.isEmpty }.map { g in var g = g; g.items = nest(g.items); return g }
}

// MARK: The command-line tools

/// Finds a command where the terminal app would: ~/.local/bin, Homebrew,
/// then PATH (an app opened from Finder gets a bare PATH).
func which(_ name: String) -> String? {
    let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    return (["\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"] + path)
        .map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
}

struct Failure: LocalizedError { var errorDescription: String? }

/// Runs bin and returns its output, or throws with what it wrote to stderr.
func run(_ bin: String, _ args: [String]) throws -> Data {
    let p = Process(), out = Pipe(), err = Pipe()
    p.executableURL = URL(fileURLWithPath: bin)
    p.arguments = args
    p.standardOutput = out
    p.standardError = err
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw Failure(errorDescription: "\((bin as NSString).lastPathComponent) \(args.first ?? ""): \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return data
}

/// Runs work off the main thread and hands its result back on it.
func background<T>(_ work: @escaping () throws -> T, _ done: @escaping (Result<T, Error>) -> Void) {
    DispatchQueue.global().async {
        let r = Result(catching: work)
        DispatchQueue.main.async { done(r) }
    }
}

let rangeRe = try! NSRegularExpression(pattern: #"^(\d{1,2}):(\d{2}) - (\d{1,2}):(\d{2})$"#)

/// Parses icalBuddy's "@@@ 09:00 - 10:30:::title:::location" lines (no
/// time range: all day), all-day events first, then by start.
func parseEvents(_ out: String, _ on: Date) -> [Event] {
    let at = { (h: String, m: String) in cal.date(bySettingHour: Int(h)!, minute: Int(m)!, second: 0, of: on) }
    return out.components(separatedBy: "\n").compactMap { raw -> Event? in
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("@@@") { line = line.dropFirst(3).trimmingCharacters(in: .whitespaces) }
        let parts = line.components(separatedBy: ":::").map { $0.trimmingCharacters(in: .whitespaces) } + ["", ""]
        var ev = Event(title: parts[0], location: parts[1])
        if let g = groups(rangeRe, parts[0]) {
            ev = Event(title: parts[1], location: parts[2], start: at(g[1], g[2]), end: at(g[3], g[4]))
        }
        return ev.title.isEmpty ? nil : ev
    }.sorted(on: { $0.start?.timeIntervalSince1970 ?? -.infinity })
}

// MARK: The store

@Observable final class Store {
    var reminders: [Reminder] = []
    var lists: [String] = []
    var events: [Event] = []
    var tab = Tab.thisWeek
    var sel: String? // the selected reminder's id
    var query = ""
    var allNotes = true    // notes under every reminder, or only the selected one (n)
    var eventsOpen = false // every event, not just the first few (c)
    var loading = false
    var status: String?    // what the last change did, for a few seconds
    var error: String?

    // Sheets, and the quick-add line
    var help = false
    var ask: Ask?
    enum Ask: Equatable { case add, edit(Reminder), delete(Reminder), lists(Tab) }
    var editing: Reminder? { if case .edit(let r) = ask { r } else { nil } }
    var sheet: Bool { ask != nil && ask != .add && editing == nil } // add and edit are a panel
    var inserting: String? // the quick-add line is open, filing into this list ("" for the default)
    var insertParent: Reminder? // ...adding a subtask of this one (o)

    /// The lists each fixed view shows, by view name, where changed.
    var viewLists = UserDefaults.standard.dictionary(forKey: "viewLists") as? [String: [String]] ?? [:] {
        didSet { UserDefaults.standard.set(viewLists, forKey: "viewLists") }
    }

    var theme = UserDefaults.standard.string(forKey: "theme") ?? "ayugloom"
    var fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 14 {
        didSet {
            // Assigning inside didSet runs didSet again under @Observable,
            // so only reassign when the size is actually out of range.
            let clamped = min(24, max(11, fontSize))
            if fontSize != clamped {
                fontSize = clamped
                return
            }
            fontScale = fontSize / 15
            UserDefaults.standard.set(fontSize, forKey: "fontSize")
        }
    }

    var eventIcons = UserDefaults.standard.object(forKey: "eventIcons") as? Bool ?? true { // a sun or a clock by each event
        didSet { UserDefaults.standard.set(eventIcons, forKey: "eventIcons") }
    }
    var opacity = UserDefaults.standard.object(forKey: "opacity") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(opacity, forKey: "opacity") }
    }
    var blur = UserDefaults.standard.object(forKey: "blur") as? Double ?? 10 { // blur radius behind a see-through window
        didSet { UserDefaults.standard.set(blur, forKey: "blur") }
    }
    var fontFamily = UserDefaults.standard.string(forKey: "fontFamily") ?? "Maple Mono" {
        didSet {
            fontName = fontFamily
            UserDefaults.standard.set(fontFamily, forKey: "fontFamily")
            applyStyle()
        }
    }
    var fontStyle = UserDefaults.standard.string(forKey: "fontStyle") ?? "Regular" { // Thin, Light, ...
        didSet {
            UserDefaults.standard.set(fontStyle, forKey: "fontStyle")
            applyStyle()
        }
    }

    /// Points regular text at the chosen style of the font family, if the
    /// family has that style.
    func applyStyle() {
        regularFace = fontStyles(fontFamily).first { $0.style == fontStyle }?.face
    }

    @ObservationIgnored var completed: [Reminder] = [] // this session's, for u
    let remindctl = which("remindctl")
    let icalBuddy = which("icalBuddy")

    init() {
        fontScale = fontSize / 15
        fontName = fontFamily
        applyStyle()
        reload()
    }

    func reload() {
        guard let bin = remindctl else { error = "remindctl not found in ~/.local/bin, Homebrew or PATH"; return }
        loading = true
        background({ (try JSONDecoder().decode([Reminder].self, from: run(bin, ["show", "all", "--json"])),
                      try JSONDecoder().decode([ListTitle].self, from: run(bin, ["list", "--json"]))) }) { r in
            self.loading = false
            switch r {
            case .success(let (rs, ls)):
                self.reminders = rs
                self.lists = ls.map(\.title)
                if self.selected == nil { self.sel = self.items().first?.id }
            case .failure(let e): self.error = e.localizedDescription
            }
        }
        guard let ical = icalBuddy else { return }
        let today = Date()
        background({ try run(ical, ["-nc", "-npn", "-nrd", "-df", "", "-tf", "%H:%M", "-iep", "datetime,title,location",
                                    "-po", "datetime,title,location", "-b", "@@@ ", "-ps", "|:::|",
                                    "eventsFrom:" + fmt("yyyy-MM-dd").string(from: today), "to:" + fmt("yyyy-MM-dd").string(from: today)]) }) { r in
            if case .success(let out) = r { self.events = parseEvents(String(decoding: out, as: UTF8.self), today) }
        }
    }

    func shown(_ t: Tab? = nil) -> [Group] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let t = t ?? tab
        return sections(t, reminders.filter { !$0.isCompleted && (q.isEmpty || $0.matches(q)) }, lists: included(t))
    }

    func included(_ t: Tab) -> [String] { viewLists[t.name] ?? t.defaultLists ?? [] }

    /// Adds list to t's view, at the end, or takes it out.
    func toggle(_ list: String, in t: Tab) {
        var ls = included(t)
        if let i = ls.firstIndex(of: list) { ls.remove(at: i) } else { ls.append(list) }
        viewLists[t.name] = ls
    }

    /// Every reminder, in the order they're drawn.
    func items() -> [Reminder] { shown().flatMap(\.items) }
    var selected: Reminder? { items().first { $0.id == sel } }

    /// Moves the selection `d` reminders down (or up, if negative).
    func step(_ d: Int) {
        let all = items()
        guard !all.isEmpty else { return }
        let k = all.firstIndex { $0.id == sel } ?? (d > 0 ? -1 : all.count)
        sel = all[max(0, min(all.count - 1, k + d))].id
    }

    func show(_ t: Tab) {
        tab = t
        sel = items().first?.id
    }

    /// The list of the section the selection is in, if it is one list, else Tasks.
    func section() -> String {
        shown().first { g in g.items.contains { $0.id == sel } }?.list ?? defaultList
    }

    /// Selects the reminder after the selected one (before, at the end),
    /// for when the selected one is about to go.
    func selectNeighbour() {
        let all = items()
        guard let k = all.firstIndex(where: { $0.id == sel }) else { return }
        sel = k + 1 < all.count ? all[k + 1].id : k > 0 ? all[k - 1].id : nil
    }

    /// Runs remindctl with args, then says what happened and reloads.
    func act(_ args: [String], _ done: String) {
        guard let bin = remindctl else { return }
        background({ try run(bin, args) }) { r in
            switch r {
            case .success:
                self.status = done
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.status == done { self.status = nil } }
            case .failure(let e): self.error = e.localizedDescription
            }
            self.reload()
        }
    }

    /// Marks r done or not here at once, before remindctl catches up.
    func mark(_ r: Reminder, _ done: Bool) {
        if let i = reminders.firstIndex(where: { $0.id == r.id }) { reminders[i].isCompleted = done }
    }

    func complete() {
        guard let r = selected else { return }
        completed.append(r)
        selectNeighbour()
        mark(r, true)
        act(["complete", r.short], "Completed: \(r.title)")
    }

    func undo() {
        guard let r = completed.popLast() else { return }
        mark(r, false)
        sel = r.id
        act(["edit", r.short, "--incomplete"], "Restored: \(r.title)")
    }

    func delete(_ r: Reminder) {
        ask = nil
        if sel == r.id { selectNeighbour() }
        reminders.removeAll { $0.id == r.id }
        act(["delete", r.short, "--force"], "Deleted: \(r.title)")
    }

    func add(_ f: Fields) {
        guard !f.title.isEmpty else { return }
        var args = ["add", f.title]
        args += ["--list", f.list.isEmpty ? defaultList : f.list]
        if !f.due.isEmpty { args += ["--due", normalizeDue(f.due)] }
        if !f.priority.isEmpty && f.priority != "none" { args += ["--priority", f.priority] }
        if !f.notes.isEmpty { args += ["--notes", f.notes] }
        act(args, "Added: \(f.title)")
    }

    /// Changes what differs from r; remindctl can't clear notes or a due date.
    func edit(_ r: Reminder, _ f: Fields) {
        var args = ["edit", r.short]
        if !f.title.isEmpty && f.title != r.title { args += ["--title", f.title] }
        if !f.due.isEmpty { args += ["--due", normalizeDue(f.due)] }
        if f.priority != r.priority { args += ["--priority", f.priority] }
        if !f.notes.isEmpty && f.notes != (r.notes ?? "") { args += ["--notes", f.notes] }
        if args.count > 2 { act(args, "Edited: \(f.title)") }
    }

    /// Adds the quick-add line, into the open section's list unless it says @list.
    func quickAdd(_ line: String) {
        var f = parseQuickAdd(line)
        guard !f.title.isEmpty else { return }
        if f.list.isEmpty { f.list = inserting ?? "" }
        if let p = insertParent { f.notes += " #sub:\(p.short)" }
        inserting = nil
        insertParent = nil
        add(f)
    }

    func toggleTheme() {
        theme = theme == "ayugloom" ? "sw1comm" : "ayugloom"
        UserDefaults.standard.set(theme, forKey: "theme")
    }
}

struct ListTitle: Decodable { var title: String }
