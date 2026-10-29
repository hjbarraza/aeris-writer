import AppKit
import MarkdownCore

/// Main menu built in code (no XIB). Every item sends its action to the first
/// responder: standard AppKit actions, plus the editor's Format commands.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Aeris", [
            item("About Aeris", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide Aeris", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Quit Aeris", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("File", [
            item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            .separator(),
            item("Add Location…", #selector(AppDelegate.addLocation(_:))),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save", #selector(NSDocument.save(_:)), "s"),
            item("Save As…", #selector(NSDocument.saveAs(_:)), "S"),
            item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            // Standard NSTextView spelling actions; the text view validates them.
            submenu("Spelling and Grammar", [
                item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"),
                item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"),
                .separator(),
                item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))),
                item("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:))),
                item("Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))),
            ]),
        ]))
        main.addItem(formatMenu())
        main.addItem(viewMenu())
        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ])
        NSApp.windowsMenu = window.submenu
        main.addItem(window)
        return main
    }

    /// Format commands go to the editor (`EditorViewController`, via the responder chain).
    private static func formatMenu() -> NSMenuItem {
        let inline = #selector(EditorViewController.toggleInline(_:))
        let block = #selector(EditorViewController.toggleBlock(_:))
        func f(_ title: String, _ e: MarkdownElement, _ key: String = "",
               _ mods: NSEvent.ModifierFlags = .command, _ action: Selector? = nil) -> NSMenuItem {
            let isInline = if case .inline = e { true } else { false }
            let i = NSMenuItem(title: title, action: action ?? (isInline ? inline : block), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.representedObject = e
            return i
        }
        let headings = (1...6).map { f("Heading \($0)", .heading($0), "\($0)") }
        return submenu("Format", [
            f("Bold", .inline(.strong), "b"),
            f("Italic", .inline(.emphasis), "i"),
            f("Code", .inline(.code), "c", [.command, .shift]),
            f("Strikethrough", .inline(.strikethrough), "x", [.command, .shift]),
            f("Highlight", .inline(.highlight), "h", [.command, .shift]),
            .separator(),
            f("Link", .inline(.link), "k"),
            f("Image", .inline(.image), "k", [.command, .shift]),
            f("Footnote", .inline(.footnote)),
            f("Wikilink", .inline(.wikilink)),
            f("Comment", .inline(.comment), "/"),
            f("Clear Formatting", .clearFormatting),
            .separator(),
        ] + headings + [
            f("Body Text", .heading(0), "0", [.command, .option]),
            .separator(),
            f("Quote", .quote, "q", [.command, .option]),
            f("Code Block", .codeBlock, "c", [.command, .option]),
            submenu("Callout", [
                f("Note", .callout("NOTE")),
                f("Tip", .callout("TIP")),
                f("Warning", .callout("WARNING")),
            ]),
            f("Display Math", .displayMath, "b", [.command, .option]),
            f("Horizontal Rule", .horizontalRule),
            f("Page Break", .pageBreak),
            f("Table of Contents", .tableOfContents),
            .separator(),
            submenu("List", [
                f("Bullet List", .list(.bullet), "u", [.command, .option]),
                f("Numbered List", .list(.ordered), "o", [.command, .option]),
                f("Task List", .list(.task), "x", [.command, .option]),
                f("Numbered Task List", .list(.orderedTask)),
            ]),
            submenu("Table", [
                f("Insert Table", .insertTable, "t", [.command, .option]),
                .separator(),
                f("Add Row Above", .addRow(below: false)),
                f("Add Row Below", .addRow(below: true)),
                f("Delete Row", .deleteRow),
                f("Move Row Up", .moveRow(down: false)),
                f("Move Row Down", .moveRow(down: true)),
                .separator(),
                f("Add Column Before", .addColumn(after: false)),
                f("Add Column After", .addColumn(after: true)),
                f("Delete Column", .deleteColumn),
                f("Move Column Left", .moveColumn(right: false)),
                f("Move Column Right", .moveColumn(right: true)),
                .separator(),
                f("Align Left", .align(.left)),
                f("Align Center", .align(.center)),
                f("Align Right", .align(.right)),
                .separator(),
                f("Sort Ascending", .sort(ascending: true)),
                f("Sort Descending", .sort(ascending: false)),
                f("Transpose", .transpose),
                f("Reformat", .reformat),
            ]),
        ])
    }

    /// View commands go to the editor too.
    private static func viewMenu() -> NSMenuItem {
        typealias E = EditorViewController
        func scope(_ title: String, _ s: FocusRange.Scope) -> NSMenuItem {
            let i = item(title, #selector(E.setFocusScope(_:)))
            i.tag = s.rawValue
            return i
        }
        let bigger2 = item("Bigger", #selector(E.makeTextBigger(_:)), "=")
        bigger2.isHidden = true  // ⌘= also enlarges (the + key without Shift)
        bigger2.allowsKeyEquivalentWhenHidden = true
        let sidebarToggle = item("Hide Library", #selector(NSSplitViewController.toggleSidebar(_:)), "s")
        sidebarToggle.keyEquivalentModifierMask = [.command, .option]
        return submenu("View", [
            item("Typewriter Mode", #selector(E.toggleTypewriterMode(_:))),
            item("Focus Mode", #selector(E.toggleFocusMode(_:))),
            submenu("Focus Scope", [scope("Sentence", .sentence), scope("Paragraph", .paragraph)]),
            .separator(),
            item("Bigger", #selector(E.makeTextBigger(_:)), "+"),
            bigger2,
            item("Smaller", #selector(E.makeTextSmaller(_:)), "-"),
            item("Actual Size", #selector(E.makeTextActualSize(_:)), "0"),
            .separator(),
            sidebarToggle,
            item("Hide Organizer", #selector(LibrarySplitViewController.toggleOrganizer(_:))),
            submenu("Organizer", [("Favorites", "favorites"), ("Smart Folders", "smartFolders"), ("Tags", "tags")].map { title, kind in
                let i = item(title, #selector(AppDelegate.toggleOrganizerSection(_:)))
                i.representedObject = kind
                return i
            }),
        ])
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }
}
