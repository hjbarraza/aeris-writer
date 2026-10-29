import AppKit
import Combine
import MarkdownCore
import SwiftUI

/// The statistics a document can show in the status bar. Raw value is what we persist.
enum StatKind: String, CaseIterable, Identifiable {
    case characters, charactersWithoutSpaces, words, sentences, readingTime, speakingTime, tasks
    var id: String { rawValue }

    var title: String {
        switch self {
        case .characters: "Characters"
        case .charactersWithoutSpaces: "Characters without spaces"
        case .words: "Words"
        case .sentences: "Sentences"
        case .readingTime: "Reading time"
        case .speakingTime: "Speaking time"
        case .tasks: "Tasks done"
        }
    }

    private static func minutes(_ m: Double) -> String { m < 1 ? "< 1 min" : "\(Int(m.rounded())) min" }

    /// The value as shown in the popover row.
    func value(_ s: TextStats) -> String {
        switch self {
        case .characters: s.characters.formatted()
        case .charactersWithoutSpaces: s.charactersWithoutSpaces.formatted()
        case .words: s.words.formatted()
        case .sentences: s.sentences.formatted()
        case .readingTime: Self.minutes(s.readingMinutes)
        case .speakingTime: Self.minutes(s.speakingMinutes)
        case .tasks: "\(s.tasksDone.formatted()) of \(s.tasksTotal.formatted())"
        }
    }

    /// The status bar text, e.g. "1,234 words".
    func label(_ s: TextStats) -> String {
        switch self {
        case .characters: "\(value(s)) \(s.characters == 1 ? "character" : "characters")"
        case .charactersWithoutSpaces: "\(value(s)) characters, no spaces"
        case .words: "\(value(s)) \(s.words == 1 ? "word" : "words")"
        case .sentences: "\(value(s)) \(s.sentences == 1 ? "sentence" : "sentences")"
        case .readingTime: "\(value(s)) read"
        case .speakingTime: "\(value(s)) spoken"
        case .tasks: s.tasksTotal == 0 ? "No tasks" : "\(value(s)) tasks done"
        }
    }
}

/// What the status bar and the popover show. Main-thread only.
@MainActor
final class StatsModel: ObservableObject {
    static let defaultsKey = "statusBarStat"

    @Published private(set) var stats: TextStats?
    @Published var selected: StatKind {
        didSet { AppDefaults.store.set(selected.rawValue, forKey: Self.defaultsKey) }
    }

    init() {
        selected = AppDefaults.store.string(forKey: Self.defaultsKey).flatMap(StatKind.init) ?? .words
    }

    func update(_ new: TextStats) { stats = new }

    var label: String { stats.map { selected.label($0) } ?? "" }
}

/// Keeps a `StatsModel` current for one text storage. Only character edits count
/// (the styler's attribute-only passes don't), debounced, and the count runs off the
/// main thread, one at a time.
@MainActor
final class StatsController {
    let model = StatsModel()
    /// How many times `TextStats.compute` was started (for tests).
    private(set) var computeCount = 0

    private var storage: NSTextStorage?
    private var observer: NSObjectProtocol?
    private var debounce: Task<Void, Never>?
    private var generation = 0
    private var inFlight = false
    private var pending = false

    var debounceInterval: Duration = .milliseconds(300)

    func attach(to storage: NSTextStorage?) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        debounce?.cancel()
        generation += 1
        self.storage = storage
        guard let storage else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main
        ) { [weak self] note in
            let chars = (note.object as? NSTextStorage)?.editedMask.contains(.editedCharacters) ?? false
            guard chars else { return }
            MainActor.assumeIsolated { self?.textChanged() }
        }
        run()  // once on open
    }

    private func textChanged() {
        generation += 1
        debounce?.cancel()
        let delay = debounceInterval
        debounce = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.run()
        }
    }

    private func run() {
        guard let storage else { return }
        if inFlight { pending = true; return }
        inFlight = true
        computeCount += 1
        let gen = generation
        // A native copy: the storage's own string may be a live view of mutable text.
        let text = String(decoding: Array(storage.string.utf8), as: UTF8.self)
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                TextStats.compute(text)
            }.value
            guard let self else { return }
            self.inFlight = false
            if gen == self.generation { self.model.update(result) }
            // The text changed while counting: count the newer text once more.
            if self.pending {
                self.pending = false
                if gen != self.generation { self.run() }
            }
        }
    }
}

// MARK: Popover content

struct StatsPopoverView: View {
    @ObservedObject var model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows) { kind in
                Button { model.selected = kind } label: {
                    HStack {
                        Image(systemName: "checkmark").opacity(model.selected == kind ? 1 : 0).frame(width: 14)
                        Text(kind.title)
                        Spacer(minLength: 16)
                        Text(model.stats.map { kind.value($0) } ?? "").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
        .font(.system(size: 13))
        .padding(12)
        .frame(width: 280)
    }

    /// Tasks are hidden when the document has none.
    var rows: [StatKind] {
        StatKind.allCases.filter { $0 != .tasks || (model.stats?.tasksTotal ?? 0) > 0 }
    }
}

// MARK: Status bar

/// A thin strip showing one stat; clicking it opens the popover.
final class StatusBarView: NSView {
    static let height: CGFloat = 24
    let label = NSTextField(labelWithString: "")
    private let model: StatsModel
    private var cancellable: AnyCancellable?
    private var popover: NSPopover?

    @MainActor
    init(model: StatsModel) {
        self.model = model
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
        ])
        // @Published emits in willSet; read the model on the next main-queue turn.
        cancellable = Publishers.Merge(model.$stats.map { _ in () }, model.$selected.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.label.stringValue = self?.model.label ?? "" }
            }
        setAccessibilityRole(.button)
        setAccessibilityLabel("Document statistics")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseDown(with event: NSEvent) { togglePopover() }

    func togglePopover() {
        if let popover, popover.isShown { popover.close(); return }
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: StatsPopoverView(model: model))
        p.show(relativeTo: label.bounds, of: label, preferredEdge: .maxY)
        popover = p
    }
}
