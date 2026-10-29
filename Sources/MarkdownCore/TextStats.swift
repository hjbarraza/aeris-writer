import Foundation
import Markdown
import NaturalLanguage

/// Document statistics over the VISIBLE text, not the Markdown syntax.
///
/// Decisions:
/// - Plain text is derived from the swift-markdown AST (`.disableSmartOpts`):
///   `#`, `**`, link/image URLs and HTML tags are dropped; link text, image alt
///   text, code span and code block content are kept.
/// - `characters` counts grapheme clusters (Swift `Character`) of that text,
///   excluding every newline (block separators and line breaks inside code blocks).
///   Soft/hard line breaks inside a paragraph count as one space.
/// - `words` / `sentences` come from `NLTokenizer` (`.word` / `.sentence`), so
///   CJK and abbreviations (`e.g.`) follow the system tokenizer.
/// - Tasks are GFM task list items (`ListItem.checkbox`).
/// - Reading time = words / 238 wpm, speaking time = words / 140 wpm.
public struct TextStats: Equatable, Sendable {
    public let characters: Int
    public let charactersWithoutSpaces: Int
    public let words: Int
    public let sentences: Int
    public let readingMinutes: Double
    public let speakingMinutes: Double
    public let tasksDone: Int
    public let tasksTotal: Int

    public static func compute(_ markdown: String) -> TextStats {
        var collector = VisibleText()
        collector.visit(MarkdownCore.parse(markdown))
        let text = collector.text

        var chars = 0, nonSpace = 0
        for ch in text where !ch.isNewline {
            chars += 1
            if !ch.isWhitespace { nonSpace += 1 }
        }
        let words = count(text, .word)
        let sentences = count(text, .sentence)
        return TextStats(
            characters: chars, charactersWithoutSpaces: nonSpace,
            words: words, sentences: sentences,
            readingMinutes: Double(words) / 238, speakingMinutes: Double(words) / 140,
            tasksDone: collector.tasksDone, tasksTotal: collector.tasksTotal)
    }

    /// Tokens that contain at least one non-whitespace character.
    private static func count(_ text: String, _ unit: NLTokenUnit) -> Int {
        guard !text.isEmpty else { return 0 }
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text
        var n = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if text[range].contains(where: { !$0.isWhitespace }) { n += 1 }
            return true
        }
        return n
    }
}

/// Accumulates visible text; blocks are separated by "\n".
struct VisibleText: MarkupWalker {
    var text = ""
    var tasksDone = 0
    var tasksTotal = 0

    private mutating func blockBreak() {
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
    }

    mutating func visitText(_ t: Text) { text += t.string }
    mutating func visitInlineCode(_ c: InlineCode) { text += c.code }
    mutating func visitSoftBreak(_ b: SoftBreak) { text += " " }
    mutating func visitLineBreak(_ b: LineBreak) { text += " " }
    mutating func visitInlineHTML(_ h: InlineHTML) {}
    mutating func visitHTMLBlock(_ h: HTMLBlock) {}

    mutating func visitCodeBlock(_ c: CodeBlock) {
        blockBreak()
        text += c.code
        blockBreak()
    }

    mutating func visitParagraph(_ p: Paragraph) { blockBreak(); descendInto(p); blockBreak() }
    mutating func visitHeading(_ h: Heading) { blockBreak(); descendInto(h); blockBreak() }
    mutating func visitTableCell(_ c: Table.Cell) { descendInto(c); text += "\n" }

    mutating func visitListItem(_ item: ListItem) {
        if let box = item.checkbox {
            tasksTotal += 1
            if box == .checked { tasksDone += 1 }
        }
        descendInto(item)
    }
}
