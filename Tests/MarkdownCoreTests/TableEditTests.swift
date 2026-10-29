import Testing
import Foundation
@testable import MarkdownCore

// Mirrors Sources/mdcheck/TableEditChecks.swift (same cases and expectations).

/// `^` in `marked` is the caret; returns the clean text and caret offset (UTF-16).
private func unmark(_ marked: String) -> (String, Int) {
    let r = (marked as NSString).range(of: "^")
    return ((marked as NSString).replacingCharacters(in: r, with: ""), r.location)
}

/// Apply `edit` to `text`; mark the selection as `^` (empty) or `[...]`.
private func applied(_ text: String, _ edit: TextEdit) -> String {
    let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
    let s = edit.selection
    if s.length == 0 { return out.replacingCharacters(in: s, with: "^") }
    return out.replacingCharacters(in: s, with: "[" + out.substring(with: s) + "]")
}

/// Run `op` on `marked` (caret at `^`); nil if the op returns nil.
private func run(_ marked: String, _ op: (String, Int) -> TextEdit?) -> String? {
    let (text, caret) = unmark(marked)
    return op(text, caret).map { applied(text, $0) }
}

struct TableEditTests {
    @Test func operations() {
        let fixture = """
        | Name | Qty  | Note  |
        | :--- | ---: | :---: |
        | b    | 10   | x     |
        | A    | 2    | y     |
        | c    | 1    | z     |
        """
        /// Fixture with the caret placed after `needle`'s first occurrence.
        func at(_ needle: String, in s: String = fixture) -> String {
            let r = (s as NSString).range(of: needle)
            return (s as NSString).replacingCharacters(in: NSRange(location: NSMaxRange(r), length: 0), with: "^")
        }

        // (label, input with ^ caret, operation, expected output with ^ caret or [selection]; nil = no-op).
        let cases: [(String, String, (String, Int) -> TextEdit?, String?)] = [
            ("reformat", at("| A"), { TableEdit.reformat(in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A^    | 2    | y     |\n| c    | 1    | z     |"),
            ("addRow below", at("| A"), { TableEdit.addRow(below: true, in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A    | 2    | y     |\n| ^     |      |       |\n| c    | 1    | z     |"),
            ("addRow above", at("| A"), { TableEdit.addRow(below: false, in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| ^     |      |       |\n| A    | 2    | y     |\n| c    | 1    | z     |"),
            ("addRow on header", at("| Na"), { TableEdit.addRow(below: false, in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| ^     |      |       |\n| b    | 10   | x     |\n| A    | 2    | y     |\n| c    | 1    | z     |"),
            ("deleteRow", at("| A"), { TableEdit.deleteRow(in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| c^    | 1    | z     |"),
            ("deleteRow last", at("| c"), { TableEdit.deleteRow(in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A^    | 2    | y     |"),
            ("deleteRow header", at("| Na"), { TableEdit.deleteRow(in: $0, at: $1) },
                nil),
            ("moveRow up", at("| A"), { TableEdit.moveRow(down: false, in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| A^    | 2    | y     |\n| b    | 10   | x     |\n| c    | 1    | z     |"),
            ("moveRow down", at("| A"), { TableEdit.moveRow(down: true, in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| c    | 1    | z     |\n| A^    | 2    | y     |"),
            ("moveRow up first", at("| b"), { TableEdit.moveRow(down: false, in: $0, at: $1) },
                nil),
            ("moveRow down last", at("| c"), { TableEdit.moveRow(down: true, in: $0, at: $1) },
                nil),
            ("addColumn after", at("| 2"), { TableEdit.addColumn(after: true, in: $0, at: $1) },
                "| Name | Qty  |     | Note  |\n| :--- | ---: | --- | :---: |\n| b    | 10   |     | x     |\n| A    | 2    | ^    | y     |\n| c    | 1    |     | z     |"),
            ("addColumn before", at("| 2"), { TableEdit.addColumn(after: false, in: $0, at: $1) },
                "| Name |     | Qty  | Note  |\n| :--- | --- | ---: | :---: |\n| b    |     | 10   | x     |\n| A    | ^    | 2    | y     |\n| c    |     | 1    | z     |"),
            ("deleteColumn", at("| 2"), { TableEdit.deleteColumn(in: $0, at: $1) },
                "| Name | Note  |\n| :--- | :---: |\n| b    | x     |\n| A    | y^     |\n| c    | z     |"),
            ("deleteColumn last col", at("| z"), { TableEdit.deleteColumn(in: $0, at: $1) },
                "| Name | Qty  |\n| :--- | ---: |\n| b    | 10   |\n| A    | 2    |\n| c    | 1^    |"),
            ("moveColumn left", at("| 2"), { TableEdit.moveColumn(right: false, in: $0, at: $1) },
                "| Qty  | Name | Note  |\n| ---: | :--- | :---: |\n| 10   | b    | x     |\n| 2^    | A    | y     |\n| 1    | c    | z     |"),
            ("moveColumn right", at("| 2"), { TableEdit.moveColumn(right: true, in: $0, at: $1) },
                "| Name | Note  | Qty  |\n| :--- | :---: | ---: |\n| b    | x     | 10   |\n| A    | y     | 2^    |\n| c    | z     | 1    |"),
            ("moveColumn left edge", at("| A"), { TableEdit.moveColumn(right: false, in: $0, at: $1) },
                nil),
            ("setAlignment center", at("| A"), { TableEdit.setAlignment(.center, column: 0, in: $0, at: $1) },
                "| Name  | Qty  | Note  |\n| :---: | ---: | :---: |\n| b     | 10   | x     |\n| A^     | 2    | y     |\n| c     | 1    | z     |"),
            ("setAlignment none", at("| A"), { TableEdit.setAlignment(nil, column: 1, in: $0, at: $1) },
                "| Name | Qty | Note  |\n| :--- | --- | :---: |\n| b    | 10  | x     |\n| A^    | 2   | y     |\n| c    | 1   | z     |"),
            ("sort text asc", at("| A"), { TableEdit.sort(column: 0, ascending: true, in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| A^    | 2    | y     |\n| b    | 10   | x     |\n| c    | 1    | z     |"),
            ("sort text desc", at("| A"), { TableEdit.sort(column: 0, ascending: false, in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| c    | 1    | z     |\n| b    | 10   | x     |\n| A^    | 2    | y     |"),
            ("sort numeric asc", at("| A"), { TableEdit.sort(column: 1, ascending: true, in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| c    | 1    | z     |\n| A^    | 2    | y     |\n| b    | 10   | x     |"),
            ("sort numeric desc", at("| Na"), { TableEdit.sort(column: 1, ascending: false, in: $0, at: $1) },
                "| Na^me | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A    | 2    | y     |\n| c    | 1    | z     |"),
            ("transpose", at("| 1"), { TableEdit.transpose(in: $0, at: $1) },
                "| Name | b   | A   | c   |\n| ---- | --- | --- | --- |\n| Qty  | 1^0  | 2   | 1   |\n| Note | x   | y   | z   |"),
            ("nextCell", at("| A"), { TableEdit.nextCell(in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A    | [2]    | y     |\n| c    | 1    | z     |"),
            ("nextCell wraps row", at("| y"), { TableEdit.nextCell(in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A    | 2    | y     |\n| [c]    | 1    | z     |"),
            ("nextCell adds row", at("| z"), { TableEdit.nextCell(in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A    | 2    | y     |\n| c    | 1    | z     |\n| ^     |      |       |"),
            ("previousCell", at("| 2"), { TableEdit.previousCell(in: $0, at: $1) },
                "| Name | Qty  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| [A]    | 2    | y     |\n| c    | 1    | z     |"),
            ("previousCell wraps row", at("| b"), { TableEdit.previousCell(in: $0, at: $1) },
                "| Name | Qty  | [Note]  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A    | 2    | y     |\n| c    | 1    | z     |"),
            ("previousCell first stays put", at("| Na"), { TableEdit.previousCell(in: $0, at: $1) },
                at("| Na")),
            ("merge unsupported", at("| A"), { TableEdit.merge(in: $0, at: $1) },
                nil),
            ("unmerge unsupported", at("| A"), { TableEdit.unmerge(in: $0, at: $1) },
                nil),
            ("caret on alignment row", at("| :-"), { TableEdit.nextCell(in: $0, at: $1) },
                "| Name | [Qty]  | Note  |\n| :--- | ---: | :---: |\n| b    | 10   | x     |\n| A    | 2    | y     |\n| c    | 1    | z     |"),
            ("escapes round-trip", "a\n\n|x|`a\\|b`|\n|-|-|\n|p \\| q^|**y**|\n\nz", { TableEdit.reformat(in: $0, at: $1) },
                "a\n\n| x      | `a\\|b` |\n| ------ | ------ |\n| p \\| q^ | **y**  |\n\nz"),
            ("short and long rows", "|a|b|c|\n|-|-|-|\n|1^|\n|1|2|3|4|", { TableEdit.reformat(in: $0, at: $1) },
                "| a   | b   | c   |\n| --- | --- | --- |\n| 1^   |     |     |\n| 1   | 2   | 3   | 4   |"),
            ("empty cells", "|a|b|c|\n|-|-|-|\n|1||^3|", { TableEdit.reformat(in: $0, at: $1) },
                "| a   | b   | c   |\n| --- | --- | --- |\n| 1   |     | ^3   |"),
            ("CJK and emoji widths", "|中文|x|\n|-|-|\n|👋|é^|\n|❤️|ab|", { TableEdit.reformat(in: $0, at: $1) },
                "| 中文 | x   |\n| ---- | --- |\n| 👋   | é^   |\n| ❤️   | ab  |"),
            ("end of doc, no newline", "text\n\n|a|b|\n|-|-|\n|c|d^|", { TableEdit.nextCell(in: $0, at: $1) },
                "text\n\n| a   | b   |\n| --- | --- |\n| c   | d   |\n| ^    |     |"),
            // Tab/⇧Tab only move the selection: no rewrite, extra cells untouched.
            ("Tab moves only", "|a|b|\n|-|-|\n|1^|2|", { TableEdit.nextCell(in: $0, at: $1) },
                "|a|b|\n|-|-|\n|1|[2]|"),
            ("⇧Tab moves only", "|a|b|\n|-|-|\n|1|2^|", { TableEdit.previousCell(in: $0, at: $1) },
                "|a|b|\n|-|-|\n|[1]|2|"),
            ("Tab keeps extra cells", "| a | b |\n|---|---|\n| 1^ | 2 | 3 |\n", { TableEdit.nextCell(in: $0, at: $1) },
                "| a | b |\n|---|---|\n| 1 | [2] | 3 |\n"),
            ("Tab into an extra cell", "| a | b |\n|---|---|\n| 1 | 2^ | 3 |\n", { TableEdit.nextCell(in: $0, at: $1) },
                "| a | b |\n|---|---|\n| 1 | 2 | [3] |\n"),
            ("Tab to an empty cell", "| a^ |   | c |\n|---|---|---|\n| 1 | 2 | 3 |", { TableEdit.nextCell(in: $0, at: $1) },
                "| a | ^  | c |\n|---|---|---|\n| 1 | 2 | 3 |"),
            ("Tab past the last cell adds a row, keeps extras", "| a | b |\n|---|---|\n| 1 | 2 | 3^ |", { TableEdit.nextCell(in: $0, at: $1) },
                "| a   | b   |\n| --- | --- |\n| 1   | 2   | 3   |\n| ^    |     |"),
            ("reformat keeps cells split by a pipe in code", "| a | b |\n|---|---|\n| `x|y` | 2^ |", { TableEdit.reformat(in: $0, at: $1) },
                "| a   | b   |\n| --- | --- |\n| `x  | y`  | 2^   |"),
            ("deleteColumn keeps extra cells", "|a|b|\n|-|-|\n|1^|2|3|", { TableEdit.deleteColumn(in: $0, at: $1) },
                "| b   |\n| --- |\n| 2^   | 3   |"),
            ("CRLF", "x\r\n\r\n|a|b|\r\n|-|-|\r\n|c^|d|\r\n\r\ny\r\n", { TableEdit.addRow(below: true, in: $0, at: $1) },
                "x\r\n\r\n| a   | b   |\r\n| --- | --- |\r\n| c   | d   |\r\n| ^    |     |\r\n\r\ny\r\n"),
            ("not in table", "para ^here\n\n|a|b|\n|-|-|", { TableEdit.reformat(in: $0, at: $1) },
                nil),
            ("insertTable mid-text", "abc^def", { TableEdit.insertTable(rows: 2, cols: 2, in: $0, at: $1) },
                "abc\n\n| ^    |     |\n| --- | --- |\n|     |     |\n|     |     |\n\ndef"),
            ("insertTable empty doc", "^", { TableEdit.insertTable(rows: 1, cols: 3, in: $0, at: $1) },
                "| ^    |     |     |\n| --- | --- | --- |\n|     |     |     |"),
        ]
        for (label, input, op, expected) in cases {
            #expect(run(input, op) == expected, Comment(rawValue: label))
        }
    }

    @Test func parseSerializeAndVerifyFlow() {
        // parse: raw cells, alignments, and the caret's cell in header / delimiter / body.
        let raw = "|x|`a\\|b`|\n|:-:|-:|\n|p \\| q|**y**|"
        if let p = TableEdit.parse(text: raw, at: 0) {
            #expect(p.table == MarkdownTable(header: ["x", "`a\\|b`"], alignments: [.center, .right], rows: [["p \\| q", "**y**"]])
                  && p.range == NSRange(location: 0, length: (raw as NSString).length), "table parse raw cells")
        } else { Issue.record("table parse raw cells") }
        let cellAt: [(String, Int, Int)] = [
            ("^|x|y|\n|-|-|\n|p|q|", 0, 0), ("|x|^y|\n|-|-|\n|p|q|", 0, 1), ("|x|y|^\n|-|-|\n|p|q|", 0, 1),
            ("|x|y|\n|-|-^|\n|p|q|", 0, 1), ("|x|y|\n|-|-|\n|p \\^| q|r|", 1, 0), ("|x|y|\n|-|-|\n|p|q^|", 1, 1),
            ("x | y\n:-- | --\np | ^q", 1, 1),
        ]
        for (marked, row, col) in cellAt {
            let (text, caret) = unmark(marked)
            let c = TableEdit.parse(text: text, at: caret)?.cell
            #expect(c?.row == row && c?.col == col, "table caret cell \(marked.debugDescription)")
        }

        #expect(TableEdit.serialize(MarkdownTable(header: ["a", "bb"], alignments: [.left, nil], rows: [["1"], ["1", "2", "3"]]))
              == "| a    | bb  |\n| :--- | --- |\n| 1    |     |\n| 1    | 2   | 3   |", "table serialize pads short rows, keeps extra cells")
        // Menu validation's cheap check: a piped line with a delimiter row in its block.
        #expect(TableEdit.looksLikeTable(text: "p\n\n|a|b|\n|-|-|\n|1|2|", at: 14), "looksLikeTable in a body row")
        #expect(TableEdit.looksLikeTable(text: "a | b\n:-- | --", at: 0), "looksLikeTable without outer pipes")
        #expect(!TableEdit.looksLikeTable(text: "a | b\nc | d", at: 0), "looksLikeTable: pipes, no delimiter row")
        #expect(!TableEdit.looksLikeTable(text: "|a|b|\n|-|-|\n\nprose", at: 15), "looksLikeTable: prose after a table")

        // Only top-level tables: never inside code, HTML blocks or list items (the
        // parse runs from `parseFrom`, default 0, so what comes before decides).
        let notTables = [
            "```\nsetup\n\n| a | b |\n|---|---|\n| 1 | 2 |\n```\n",
            "<pre>\nx\n\n| a | b |\n|---|---|\n| 1 | 2 |\n</pre>\n",
            "- item\n\n  | a | b |\n  |---|---|\n  | 1 | 2 |\n\n- next\n",
            "> q\n>\n> | a | b |\n> |---|---|\n> | 1 | 2 |\n",
        ]
        for t in notTables {
            let c = (t as NSString).range(of: "| 1").location + 2
            let ops: [TextEdit?] = [TableEdit.reformat(in: t, at: c), TableEdit.addRow(below: true, in: t, at: c),
                                    TableEdit.sort(ascending: true, in: t, at: c), TableEdit.nextCell(in: t, at: c),
                                    TableEdit.previousCell(in: t, at: c), TableEdit.transpose(in: t, at: c)]
            #expect(TableEdit.parse(text: t, at: c) == nil && ops.allSatisfy { $0 == nil }, "no table ops on a non-top-level table: \(t.debugDescription)")
        }
        let afterFence = "```\ncode\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        #expect(TableEdit.nextCell(in: afterFence, at: (afterFence as NSString).range(of: "| 1").location + 2) != nil, "a table after a closed fence is a table")
        let tableAfterList = "- item\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        #expect(TableEdit.parse(text: tableAfterList, at: (tableAfterList as NSString).range(of: "| 1").location + 2) != nil, "an unindented table after a list is top-level")
        // parseFrom: a top-level block start gives the same answer, cheaper.
        let twoTables = "| x |\n|---|\n| y |\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        #expect(TableEdit.parse(text: twoTables, at: 41, parseFrom: 19)?.cell.row == 1, "parseFrom at a block start finds the table")

        // GFM escapes: only `\|` escapes a pipe; `\\|` is a backslash then an escaped pipe.
        // Re-serializing must leave every cell's rendered text identical.
        let roundTrip = [
            "| a | b |\n|---|---|\n| 1 | 2\\\\|\n", "| a | b |\n|---|---|\n| x\\\\| y |\n",
            "| a | b |\n|---|---|\n| x \\| y | 2 |\n", "| a | b |\n|---|---|\n| `x|y` | 2 |\n",
            "a | b\n--- | ---\n1 | 2\n", "| é | 漢字 |\n|:-:|--:|\n| 😀 | ü |\n", "| a | b |\n|---|---|\n| 1 | 2 | 3 | 4 |\n",
            "| a | b |\n|---|---|\n| \\\\ | c\\d |\n", "|a|b|\n|-|-|\n|\\\\\\||x|\n",
        ]
        for t in roundTrip {
            let caret = (t as NSString).length - 3
            guard let e = TableEdit.reformat(in: t, at: caret) else { Issue.record("round trip: located \(t.debugDescription)"); continue }
            let out = (t as NSString).replacingCharacters(in: e.range, with: e.replacement)
            #expect(MarkdownCore.html(out) == MarkdownCore.html(t), "round trip keeps every cell: \(t.debugDescription) → \(out.debugDescription)")
        }


        // A run of non-blank lines can begin with a fence's closing line: parsing from
        // the run start would read it as an opener. Parses start at restart points only.
        let secondFence = "```\nfoo\n\nbar\n```\n```\n| a | b |\n|---|---|\n| 1 | 2 |\n```\n"
        let sf = (secondFence as NSString).range(of: "| 1").location + 2
        #expect(TableEdit.reformat(in: secondFence, at: sf) == nil && TableEdit.addRow(below: true, in: secondFence, at: sf) == nil
              && TableEdit.reformat(in: secondFence, at: sf, parseFrom: 17) == nil, "table-looking text in a fence right after another fence is not a table")
        let afterFenceNoBlank = "```\nfoo\n\nbar\n```\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        let af = (afterFenceNoBlank as NSString).range(of: "| 1").location + 2
        #expect(TableEdit.reformat(in: afterFenceNoBlank, at: af) != nil && TableEdit.nextCell(in: afterFenceNoBlank, at: af) != nil
              && TableEdit.reformat(in: afterFenceNoBlank, at: af, parseFrom: 17) != nil, "a table right after a closing fence (no blank line) is a table")
        let listInFence = "```\nfoo\n\nbar\n```\n```\nyy\n- x\n```\n\ntail\n"
        #expect(MarkdownCore.isInCodeBlock(listInFence, at: 24) && MarkdownCore.isInCodeBlock(listInFence, at: 24, parseFrom: 17), "a list line in a fence right after another fence is code")
        #expect(MarkdownCore.isRestartPoint(listInFence, 17, parseFrom: 0) && !MarkdownCore.isRestartPoint(listInFence, 13, parseFrom: 0), "restart points: the second fence's opener is one, the first fence's closing line is not")
        let list = "- a\n- b\n\n  more\n- c\n"
        #expect(MarkdownCore.isRestartPoint(list, 4, parseFrom: 0) && MarkdownCore.isRestartPoint(list, 16, parseFrom: 0)
              && !MarkdownCore.isRestartPoint(list, 9, parseFrom: 0), "restart points: top-level list items, not their continuation lines")

        // Column commands with the caret in an extra cell are no-ops (nil).
        let extra = "| a | b |\n|---|---|\n| 1 | 2 | 3 |"
        let c3 = (extra as NSString).range(of: "3").location
        #expect(TableEdit.deleteColumn(in: extra, at: c3) == nil && TableEdit.moveColumn(right: false, in: extra, at: c3) == nil
              && TableEdit.addColumn(after: true, in: extra, at: c3) == nil && TableEdit.setAlignment(.left, in: extra, at: c3) == nil
              && TableEdit.sort(ascending: true, in: extra, at: c3) == nil, "column commands in an extra cell are no-ops")
        #expect(TableEdit.deleteColumn(in: extra, at: c3 - 4) != nil, "…and still act from a real cell")

        // Ticket verify: insert 2×2, tab through the cells, add a column, reformat.
        var doc = ""
        func step(_ e: TextEdit?) -> Int {
            guard let e else { return -1 }
            doc = (doc as NSString).replacingCharacters(in: e.range, with: e.replacement)
            return e.selection.location
        }
        var caret = step(TableEdit.insertTable(rows: 2, cols: 2, in: doc, at: 0))
        var visited: [(Int, Int)] = []
        for _ in 0..<6 {
            caret = step(TableEdit.nextCell(in: doc, at: caret))
            if let c = TableEdit.parse(text: doc, at: caret)?.cell { visited.append((c.row, c.col)) }
        }
        #expect(visited.map { "\($0.0),\($0.1)" } == ["0,1", "1,0", "1,1", "2,0", "2,1", "3,0"], "table verify: tab through cells (adds row at end)")
        caret = step(TableEdit.addColumn(after: true, in: doc, at: caret))
        caret = step(TableEdit.reformat(in: doc, at: caret))
        #expect(doc == "|     |     |     |\n| --- | --- | --- |\n|     |     |     |\n|     |     |     |\n|     |     |     |"
              && caret == 88, "table verify: add column, reformat → pipes aligned")
    }
}
