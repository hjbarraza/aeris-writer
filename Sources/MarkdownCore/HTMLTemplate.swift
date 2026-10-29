import Foundation
import NaturalLanguage

extension MarkdownCore {
    /// The page's body for an empty document: one quiet, centred line.
    public static let emptyPreviewBody = "<p class=\"empty\">Nothing to preview</p>"

    /// The body to show for `text`: its rendering, or the placeholder when it is only whitespace.
    public static func previewBody(_ text: String, sourceLines: Bool = false) -> String {
        text.allSatisfy(\.isWhitespace) ? emptyPreviewBody : html(text, sourceLines: sourceLines)
    }

    /// The document's dominant language as a BCP 47 code ("fr", "en"), or nil when the text is
    /// empty or too short or mixed to tell.
    public static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value >= 0.5 else { return nil }
        return best.key.rawValue
    }

    /// Wrap rendered body HTML in a full, themeable page. Light/dark follow the
    /// system via `prefers-color-scheme`. Pure; reused by the preview and (later) export.
    /// `lang` becomes the `<html lang>` so hyphenation and quotes match the text.
    public static func htmlDocument(body: String, title: String, lang: String? = nil) -> String {
        let langAttr = lang.map { " lang=\"\($0.filter { $0.isLetter || $0 == "-" })\"" } ?? ""
        let safeTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html\(langAttr)>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(safeTitle)</title>
        <style>\(css)</style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    static let css = """
    :root {
      --fg: #24262b; --bg: #fdfcf9; --muted: #6b6f78; --rule: #dedbd3;
      --code-bg: #f1eee7; --accent: #2a62c9; --quote: #c9c4b8;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #dcdad5; --bg: #1d1e21; --muted: #9a9ca3; --rule: #3a3b40;
        --code-bg: #2a2b30; --accent: #7aa7f0; --quote: #4a4b52;
      }
    }
    html { background: var(--bg); }
    body {
      color: var(--fg); background: var(--bg);
      font: 17px/1.65 "New York", Charter, Georgia, serif;
      max-width: 40em; margin: 0 auto; padding: 2em 1.5em 4em;
      overflow-wrap: break-word; hyphens: auto;
    }
    p.empty { text-align: center; color: var(--muted); margin-top: 30vh; font-size: 0.95em; }
    h1, h2, h3, h4, h5, h6 {
      font-family: -apple-system, "SF Pro Text", system-ui, sans-serif;
      line-height: 1.25; margin: 1.6em 0 0.5em;
    }
    h1 { font-size: 2em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; }
    h1:first-child, h2:first-child { margin-top: 0; }
    h1, h2 { border-bottom: 1px solid var(--rule); padding-bottom: 0.25em; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
    a { color: var(--accent); }
    code, pre {
      font: 0.88em/1.5 ui-monospace, "SF Mono", Menlo, monospace;
    }
    code { background: var(--code-bg); padding: 0.1em 0.35em; border-radius: 4px; }
    pre {
      background: var(--code-bg); padding: 0.9em 1.1em; border-radius: 8px; overflow-x: auto;
    }
    pre code { background: none; padding: 0; font-size: 1em; }
    blockquote {
      margin-left: 0; padding: 0.1em 1em; color: var(--muted);
      border-left: 3px solid var(--quote);
    }
    table { border-collapse: collapse; }
    th, td { border: 1px solid var(--rule); padding: 0.4em 0.8em; }
    th { background: var(--code-bg); text-align: left; }
    hr { border: 0; border-top: 1px solid var(--rule); margin: 2em 0; }
    img { max-width: 100%; }
    li > input[type=checkbox] { margin: 0 0.5em 0 -1.4em; vertical-align: middle; }
    li:has(> input[type=checkbox]) { list-style: none; }
    li > input[type=checkbox] + p { display: inline; }
    """
}
