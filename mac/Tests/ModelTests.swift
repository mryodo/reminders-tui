import XCTest
@testable import Remind

func date(_ s: String) -> Date { fmt("yyyy-MM-dd HH:mm").date(from: s)! }

func reminder(_ title: String, list: String = "L", due: String? = nil, priority: String = "none", notes: String? = nil) -> Reminder {
    Reminder(id: title, title: title, dueDate: due.map { iso.string(from: date($0)) }, isCompleted: false, listName: list, priority: priority, notes: notes)
}

final class ModelTests: XCTestCase {
    func testNormalizeDue() {
        let now = date("2026-09-27 10:00") // a Sunday
        let cases = [
            "today": "today", "tomorrow": "tomorrow", "today 09:30": "2026-09-27 09:30", "tomorrow 14:00": "2026-09-28 14:00",
            "friday": "2026-10-02", "sunday": "2026-09-27", "fri": "2026-10-02", "friday 14:00": "2026-10-02 14:00",
            "Friday": "2026-10-02", "2026-01-03": "2026-01-03", "friday 25:00": "friday 25:00", "next quarter": "next quarter",
        ]
        for (i, want) in cases { XCTAssertEqual(normalizeDue(i, now), want, i) }
    }

    func testRelativeDate() {
        let now = date("2026-08-01 12:00")
        let cases = ["2026-08-01 18:00": "today", "2026-08-02 09:00": "tomorrow", "2026-07-31 09:00": "yesterday",
                     "2026-08-04 09:00": "in 3 days", "2026-07-27 09:00": "5 days ago", "2026-08-12 09:00": "next week",
                     "2026-08-22 09:00": "Sat Aug 22", "2027-01-10 09:00": "Jan 10, 2027"]
        for (d, want) in cases { XCTAssertEqual(relativeDate(date(d), now), want, d) }
    }

    func testQuickAdd() {
        XCTAssertEqual(parseQuickAdd(#"call bob @Work !high ~"next monday" #a #b"#),
                       Fields(title: "call bob", list: "Work", priority: "high", due: "next monday", notes: "#a #b"))
        XCTAssertEqual(parseQuickAdd("buy milk ~fri"), Fields(title: "buy milk", due: "fri", notes: "#thisweek"))
    }

    func testNatural() {
        let now = date("2026-09-27 10:00") // a Sunday
        func n(_ s: String) -> [String] { let r = natural(s, now); return [r.rest, r.due, r.recur] }
        XCTAssertEqual(n("pay rent jan 3 2027 and repeat every three days"), ["pay rent", "2027-01-03", "every 3 days"])
        XCTAssertEqual(n("call bob on jan 3 2027 at 3pm"), ["call bob", "2027-01-03 15:00", ""])
        XCTAssertEqual(n("meet jan 3 2027 at noon every week"), ["meet", "2027-01-03 12:00", "weekly"])
        XCTAssertEqual(n("sunday every other month"), ["", "2026-09-27", "every 2 months"])
        XCTAssertEqual(n("water plants repeat daily"), ["water plants", "", "daily"])
        XCTAssertEqual(n("friday, no repeat"), ["", "2026-10-02", "none"])
        XCTAssertEqual(n("don't repeat"), ["", "", "none"])
        XCTAssertEqual(n("weekly report"), ["weekly report", "", ""])
        XCTAssertEqual(n("read chapter 2024"), ["read chapter 2024", "", ""])
        XCTAssertEqual(parseQuickAdd(#"call bob every 2 weeks ~"next monday""#),
                       Fields(title: "call bob", due: "next monday", notes: "#thisweek", recur: "every 2 weeks"))
        XCTAssertEqual(parseQuickAdd("lunch tomorrow").title, "lunch tomorrow")
        let lists = ["✍︎ Tasks", "⚔︎ Joint Sparsification", "Habits"]
        XCTAssertEqual(parseQuickAdd("send draft to the joint sparsification list every week", lists: lists),
                       Fields(title: "send draft", list: "⚔︎ Joint Sparsification", notes: "#thisweek", recur: "weekly"))
        XCTAssertEqual(parseQuickAdd("call bob in tasks", lists: lists).list, "✍︎ Tasks")
        XCTAssertEqual(parseQuickAdd("call bob @tasks", lists: lists).list, "✍︎ Tasks")
        XCTAssertEqual(parseQuickAdd("call bob @Errands", lists: lists).list, "Errands") // new: add makes it
        XCTAssertEqual(parseQuickAdd("talk to habits coach", lists: lists).title, "talk to habits coach") // only at the end
        XCTAssertEqual(parseQuickAdd("walk in the park", lists: lists).title, "walk in the park")
        XCTAssertEqual(parseQuickAdd("x in tasks @Habits", lists: lists), Fields(title: "x in tasks", list: "Habits", notes: "#thisweek"))
    }

    func testListCompletion() {
        XCTAssertEqual(typingList("call bob @Ta"), "Ta")
        XCTAssertEqual(typingList(#"call @"✍︎ Ta"#), "✍︎ Ta")
        XCTAssertEqual(typingList("call @"), "")
        XCTAssertNil(typingList("mail a@b"))
        XCTAssertNil(typingList("call @Tasks "))
        XCTAssertEqual(completeList("call bob @ta", "✍︎ Tasks"), #"call bob @"✍︎ Tasks" "#)
        XCTAssertEqual(completeList(#"call @"✍︎ Ta"#, "Habits"), "call @Habits ")
        XCTAssertEqual(parseQuickAdd(completeList("call @ta", "✍︎ Tasks")).list, "✍︎ Tasks")
    }

    func testStripTags() {
        let cases = ["#thisweek #sub:ABCDEF12": "", "call #sub:ABCDEF12": "call","#thisweek": "", "#thisweek #urgent": "#urgent", "call about contract\n#thisweek": "call about contract",
                     "#ThisWeek": "", "just some notes": "just some notes"]
        for (i, want) in cases { XCTAssertEqual(stripTags(i), want, i) }
    }

    func testNest() {
        func r(_ id: String, _ parent: String? = nil) -> Reminder {
            Reminder(id: id + "-0000", title: id, isCompleted: false, listName: "L", priority: "none", notes: parent.map { "#sub:" + $0 })
        }
        // C under P; G's parent is a subtask, so G stays put; A and B tag each other, so neither hides
        let items = [r("CCCCCCCC", "pppppppp"), r("XXXXXXXX"), r("PPPPPPPP"), r("GGGGGGGG", "CCCCCCCC"), r("AAAAAAAA", "BBBBBBBB"), r("BBBBBBBB", "AAAAAAAA")]
        XCTAssertEqual(nest(items).map(\.title), ["XXXXXXXX", "PPPPPPPP", "CCCCCCCC", "GGGGGGGG", "AAAAAAAA", "BBBBBBBB"])
        XCTAssertEqual(subtasks(items), ["CCCCCCCC-0000"])
    }

    func testParseEvents() {
        let evs = parseEvents("@@@ Vacation: Michael\n@@@ 18:00 - 20:00:::strickenabend:::Artemis\n@@@ 09:00 - 10:00:::Standup\n\n", date("2026-09-24 12:00"))
        XCTAssertEqual(evs.map(\.title), ["Vacation: Michael", "Standup", "strickenabend"])
        XCTAssertNil(evs[0].start)
        XCTAssertEqual(evs[1].start, date("2026-09-24 09:00"))
        XCTAssertEqual(evs[2].end, date("2026-09-24 20:00"))
        XCTAssertEqual(evs[2].location, "Artemis")
        XCTAssertEqual(parseEvents("", Date()), [])
    }

    func testSections() {
        let now = date("2026-09-24 12:00") // a Thursday
        let rs = [reminder("late", due: "2026-09-20 09:00"), reminder("low", list: "B", due: "2026-09-24 15:00", priority: "low"),
                  reminder("high", list: "B", due: "2026-09-24 09:00", priority: "high"), reminder("sun", list: "A", due: "2026-09-27 09:00"),
                  reminder("later", due: "2026-10-30 09:00"), reminder("tagged", list: "A", notes: "#thisweek"), reminder("none")]
        let titles = { (t: Tab) in sections(t, rs, now).map { "\($0.title): " + $0.items.map(\.title).joined(separator: " ") } }
        XCTAssertEqual(titles(.thisWeek), ["Overdue: late", "A: sun tagged", "B: high low"])
        XCTAssertEqual(titles(.today), ["Overdue: late", "Due today: high low", "No due date: tagged none"])
        XCTAssertEqual(titles(.upcoming), ["Overdue: late", "Today: high low", "Sun Sep 27: sun"])
        XCTAssertEqual(sections(.thisWeek, rs, now)[1].list, "A")
        XCTAssertNil(sections(.thisWeek, rs, now)[0].list)
        XCTAssertEqual(sections(.teaching, rs, now, lists: ["B", "A", "Z"]).map(\.title), ["B", "A"]) // in the chosen order, empty ones dropped
    }
}
