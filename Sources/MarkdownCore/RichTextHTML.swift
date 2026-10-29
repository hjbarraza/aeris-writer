import Foundation

/// HTML made safe to hand to Cocoa's HTML importer for Copy as Rich Text, which would otherwise
/// fetch remote images, stylesheets, frames and scripts on the main thread during the copy.
public enum RichTextHTML {
    /// `html` without script, style, link, frame, object, embed, meta and base elements, and without
    /// the `src`, `srcset`, `background`, `poster`, `data` and `style` attributes (the ways a
    /// resource is named). Formatting tags stay.
    public static func withoutResources(_ html: String) -> String {
        var out = html
        for (pattern, template) in patterns {
            out = out.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    private static let patterns: [(String, String)] = [
        (#"<(script|style|iframe|object|embed|frameset|noscript)\b[^>]*>[\s\S]*?</\1\s*>"#, ""),
        (#"<(script|style|iframe|object|embed|frameset|noscript|link|meta|base|source|track|param)\b[^>]*>"#, ""),
        (#"\s(src|srcset|background|poster|data|style)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#, ""),
    ]
}
