import SwiftUI
import AppKit

// MARK: - Command Shortcut
public struct CommandShortcut: View, Equatable {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(ShadcnTheme.foregroundMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ShadcnTheme.cardHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 0.5)
            )
    }
}

// MARK: - Command Separator
public struct CommandSeparator: View, Equatable, Identifiable {
    public let id: String

    public init(id: String = "command-separator") {
        self.id = id
    }

    public static func == (lhs: CommandSeparator, rhs: CommandSeparator) -> Bool {
        lhs.id == rhs.id
    }

    public var body: some View {
        Rectangle()
            .fill(ShadcnTheme.border)
            .frame(height: 1)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
    }
}

// MARK: - Command Empty
public struct CommandEmpty: View, Equatable, Identifiable {
    public let id: String
    public let message: String

    public init(_ message: String = "No results found.", id: String? = nil) {
        self.message = message
        self.id = id ?? "empty-\(message)"
    }

    public static func == (lhs: CommandEmpty, rhs: CommandEmpty) -> Bool {
        lhs.message == rhs.message && lhs.id == rhs.id
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(ShadcnTheme.foregroundMuted.opacity(0.6))

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ShadcnTheme.foregroundMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Command Item
public struct CommandItem: View, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let iconColor: Color?
    public let shortcut: String?
    public let keywords: [String]
    public let isDestructive: Bool
    public let isDisabled: Bool
    public var groupHeading: String?
    public let action: () -> Void

    public static func == (lhs: CommandItem, rhs: CommandItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.icon == rhs.icon &&
        lhs.shortcut == rhs.shortcut &&
        lhs.isDestructive == rhs.isDestructive &&
        lhs.isDisabled == rhs.isDisabled &&
        lhs.groupHeading == rhs.groupHeading
    }

    public init(
        _ title: String,
        id: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        shortcut: String? = nil,
        keywords: [String] = [],
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        groupHeading: String? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.id = id ?? title
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.shortcut = shortcut
        self.keywords = keywords
        self.isDestructive = isDestructive
        self.isDisabled = isDisabled
        self.groupHeading = groupHeading
        self.action = action
    }

    @Environment(CommandContext.self) private var context: CommandContext?

    public var body: some View {
        let isSelected = context?.selectedItemId == id

        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor ?? (isDestructive ? ShadcnTheme.destructive : (isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)))
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isDestructive ? ShadcnTheme.destructive : ShadcnTheme.foreground)
                    .lineLimit(1)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let shortcut = shortcut, !shortcut.isEmpty {
                CommandShortcut(shortcut)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, subtitle == nil ? 6 : 7)
        .background(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                .fill(isSelected ? ShadcnTheme.accentActive : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        .opacity(isDisabled ? 0.4 : 1.0)
        .pointingHand()
        .onHover { hovering in
            if hovering && !isDisabled {
                context?.selectedItemId = id
            }
        }
        .onTapGesture {
            if !isDisabled {
                context?.execute(item: self)
            }
        }
    }
}

// MARK: - Command Item Builder
@resultBuilder
public struct CommandItemBuilder {
    public static func buildBlock(_ components: [CommandItem]...) -> [CommandItem] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ item: CommandItem) -> [CommandItem] {
        [item]
    }

    public static func buildExpression(_ items: [CommandItem]) -> [CommandItem] {
        items
    }

    public static func buildOptional(_ component: [CommandItem]?) -> [CommandItem] {
        component ?? []
    }

    public static func buildEither(first component: [CommandItem]) -> [CommandItem] {
        component
    }

    public static func buildEither(second component: [CommandItem]) -> [CommandItem] {
        component
    }

    public static func buildArray(_ components: [[CommandItem]]) -> [CommandItem] {
        components.flatMap { $0 }
    }
}

// MARK: - Command Group
public struct CommandGroup: View, Identifiable, Equatable {
    public let id: String
    public let heading: String?
    public let items: [CommandItem]

    public static func == (lhs: CommandGroup, rhs: CommandGroup) -> Bool {
        lhs.id == rhs.id &&
        lhs.heading == rhs.heading &&
        lhs.items == rhs.items
    }

    public init(
        heading: String? = nil,
        id: String? = nil,
        items: [CommandItem]
    ) {
        self.id = id ?? (heading ?? UUID().uuidString)
        self.heading = heading
        self.items = items.map { item in
            var copy = item
            if copy.groupHeading == nil {
                copy.groupHeading = heading
            }
            return copy
        }
    }

    public init(
        heading: String? = nil,
        id: String? = nil,
        @CommandItemBuilder items: () -> [CommandItem]
    ) {
        self.init(heading: heading, id: id, items: items())
    }

    @Environment(CommandContext.self) private var context: CommandContext?

    public var body: some View {
        let visibleItems = items.filter { item in
            guard let ctx = context else { return true }
            return ctx.matches(item: item, groupHeading: heading)
        }

        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if let heading = heading, !heading.isEmpty {
                    Text(heading)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                }

                ForEach(visibleItems) { item in
                    item
                }
            }
        }
    }
}

// MARK: - Command Element & List Builder
public enum CommandElement: Identifiable, Equatable {
    case empty(CommandEmpty)
    case group(CommandGroup)
    case item(CommandItem)
    case separator(CommandSeparator)

    public var id: String {
        switch self {
        case .empty(let e): return e.id
        case .group(let g): return "group-\(g.id)"
        case .item(let i): return "item-\(i.id)"
        case .separator(let s): return "sep-\(s.id)"
        }
    }

    public static func == (lhs: CommandElement, rhs: CommandElement) -> Bool {
        switch (lhs, rhs) {
        case (.empty(let a), .empty(let b)): return a == b
        case (.group(let a), .group(let b)): return a == b
        case (.item(let a), .item(let b)): return a == b
        case (.separator(let a), .separator(let b)): return a == b
        default: return false
        }
    }
}

@resultBuilder
public struct CommandListBuilder {
    public static func buildBlock(_ elements: [CommandElement]...) -> [CommandElement] {
        elements.flatMap { $0 }
    }

    public static func buildExpression(_ empty: CommandEmpty) -> [CommandElement] {
        [.empty(empty)]
    }

    public static func buildExpression(_ group: CommandGroup) -> [CommandElement] {
        [.group(group)]
    }

    public static func buildExpression(_ item: CommandItem) -> [CommandElement] {
        [.item(item)]
    }

    public static func buildExpression(_ separator: CommandSeparator) -> [CommandElement] {
        [.separator(separator)]
    }

    public static func buildOptional(_ component: [CommandElement]?) -> [CommandElement] {
        component ?? []
    }

    public static func buildEither(first component: [CommandElement]) -> [CommandElement] {
        component
    }

    public static func buildEither(second component: [CommandElement]) -> [CommandElement] {
        component
    }

    public static func buildArray(_ components: [[CommandElement]]) -> [CommandElement] {
        components.flatMap { $0 }
    }
}

// MARK: - Command Context (CMDK Engine)
@MainActor
@Observable
public final class CommandContext {
    public var query: String = "" {
        didSet {
            updateFilteredState()
        }
    }
    public var selectedItemId: String? = nil
    public var allItems: [CommandItem] = [] {
        didSet {
            updateFilteredState()
        }
    }
    public var visibleItems: [CommandItem] = []
    public var onDismiss: (() -> Void)? = nil

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public func matches(item: CommandItem, groupHeading: String? = nil) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }

        if item.title.localizedCaseInsensitiveContains(q) { return true }
        if let subtitle = item.subtitle, subtitle.localizedCaseInsensitiveContains(q) { return true }
        let heading = item.groupHeading ?? groupHeading
        if let heading = heading, heading.localizedCaseInsensitiveContains(q) { return true }
        for keyword in item.keywords {
            if keyword.localizedCaseInsensitiveContains(q) { return true }
        }

        // Multi-word token matching (all words must match at least one attribute)
        let tokens = q.split(separator: " ").map(String.init)
        if tokens.count > 1 {
            let matchesAllTokens = tokens.allSatisfy { token in
                item.title.localizedCaseInsensitiveContains(token) ||
                (item.subtitle?.localizedCaseInsensitiveContains(token) ?? false) ||
                (heading?.localizedCaseInsensitiveContains(token) ?? false) ||
                item.keywords.contains(where: { $0.localizedCaseInsensitiveContains(token) })
            }
            if matchesAllTokens { return true }
        }

        return false
    }

    public func updateFilteredState() {
        let matching = allItems.filter { matches(item: $0) && !$0.isDisabled }
        self.visibleItems = matching

        if let currentSelected = selectedItemId, matching.contains(where: { $0.id == currentSelected }) {
            // Keep current selection
        } else {
            selectedItemId = matching.first?.id
        }
    }

    public func selectNext() {
        guard !visibleItems.isEmpty else { return }
        if let current = selectedItemId, let idx = visibleItems.firstIndex(where: { $0.id == current }) {
            let nextIdx = (idx + 1) % visibleItems.count
            selectedItemId = visibleItems[nextIdx].id
        } else {
            selectedItemId = visibleItems.first?.id
        }
    }

    public func selectPrevious() {
        guard !visibleItems.isEmpty else { return }
        if let current = selectedItemId, let idx = visibleItems.firstIndex(where: { $0.id == current }) {
            let prevIdx = (idx - 1 + visibleItems.count) % visibleItems.count
            selectedItemId = visibleItems[prevIdx].id
        } else {
            selectedItemId = visibleItems.last?.id
        }
    }

    public func executeSelected() {
        guard let current = selectedItemId, let item = visibleItems.first(where: { $0.id == current }) else {
            return
        }
        execute(item: item)
    }

    public func execute(item: CommandItem) {
        guard !item.isDisabled else { return }
        item.action()
        dismiss()
    }

    public func dismiss() {
        onDismiss?()
    }
}

// MARK: - Command List
public struct CommandList: View {
    public let elements: [CommandElement]

    public init(@CommandListBuilder elements: () -> [CommandElement]) {
        self.elements = elements()
    }

    @Environment(CommandContext.self) private var context: CommandContext?

    private func extractAllItems() -> [CommandItem] {
        var all: [CommandItem] = []
        for element in elements {
            switch element {
            case .item(let item):
                all.append(item)
            case .group(let group):
                for item in group.items {
                    var copy = item
                    if copy.groupHeading == nil {
                        copy.groupHeading = group.heading
                    }
                    all.append(copy)
                }
            case .empty, .separator:
                break
            }
        }
        return all
    }

    private func syncContext() {
        let all = extractAllItems()
        context?.allItems = all
    }

    private var emptyElement: CommandEmpty {
        elements.compactMap { elem -> CommandEmpty? in
            if case .empty(let e) = elem { return e }
            return nil
        }.first ?? CommandEmpty()
    }

    private func computeVisibleElements() -> [CommandElement] {
        let activeElements: [CommandElement] = elements.compactMap { element in
            switch element {
            case .empty:
                return nil
            case .item(let item):
                guard let ctx = context else { return element }
                return ctx.matches(item: item) ? element : nil
            case .group(let group):
                guard let ctx = context else { return element }
                let matching = group.items.filter { ctx.matches(item: $0, groupHeading: group.heading) }
                return matching.isEmpty ? nil : .group(CommandGroup(heading: group.heading, id: group.id, items: matching))
            case .separator:
                return element
            }
        }

        var result: [CommandElement] = []
        for (i, elem) in activeElements.enumerated() {
            if case .separator = elem {
                let hasBefore = result.contains { e in
                    if case .separator = e { return false }
                    return true
                }
                let hasAfter = activeElements[(i + 1)...].contains { e in
                    if case .separator = e { return false }
                    return true
                }
                if hasBefore && hasAfter {
                    result.append(elem)
                }
            } else {
                result.append(elem)
            }
        }
        return result
    }

    public var body: some View {
        let visibleElements = computeVisibleElements()
        let totalMatchingItems = visibleElements.reduce(0) { total, elem in
            switch elem {
            case .item: return total + 1
            case .group(let g): return total + g.items.count
            case .empty, .separator: return total
            }
        }

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    if totalMatchingItems == 0 {
                        emptyElement
                    } else {
                        ForEach(visibleElements) { elem in
                            switch elem {
                            case .item(let item):
                                item
                                    .id(item.id)
                            case .group(let group):
                                VStack(alignment: .leading, spacing: 2) {
                                    if let heading = group.heading, !heading.isEmpty {
                                        Text(heading)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                                            .padding(.horizontal, 10)
                                            .padding(.top, 6)
                                            .padding(.bottom, 2)
                                    }

                                    ForEach(group.items) { item in
                                        item
                                            .id(item.id)
                                    }
                                }
                            case .separator(let sep):
                                sep
                            case .empty:
                                EmptyView()
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 330)
            .onChange(of: context?.selectedItemId) { _, newId in
                if let id = newId {
                    withAnimation(.fluidQuick) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onAppear {
                syncContext()
            }
            .onChange(of: elements) { _, _ in
                syncContext()
            }
        }
    }
}

// MARK: - Command Input
public struct CommandInput: View {
    public var placeholder: String = "Type a command or search..."
    @FocusState private var isFocused: Bool
    @Environment(CommandContext.self) private var context: CommandContext?

    public init(placeholder: String = "Type a command or search...") {
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ShadcnTheme.foregroundMuted)

            TextField(placeholder, text: Binding(
                get: { context?.query ?? "" },
                set: { context?.query = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(ShadcnTheme.foreground)
            .focused($isFocused)

            if let query = context?.query, !query.isEmpty {
                Button {
                    context?.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .pointingHand()
            }

            CommandShortcut("ESC")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isFocused = true
            }
        }
    }
}

// MARK: - Command
public struct Command<Content: View>: View {
    @State private var context: CommandContext
    public let content: () -> Content

    public init(context: CommandContext? = nil, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self._context = State(initialValue: context ?? CommandContext(onDismiss: onDismiss))
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(ShadcnTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
        )
        .environment(context)
    }
}

// MARK: - Command Dialog
public struct CommandDialog<Content: View>: View {
    @Binding public var isPresented: Bool
    @State private var context: CommandContext
    @State private var keyMonitor: Any? = nil
    public let content: () -> Content

    public init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        let ctx = CommandContext()
        self._context = State(initialValue: ctx)
        self.content = content
    }

    public var body: some View {
        if isPresented {
            ZStack {
                // Ambient Backdrop
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeDialog()
                    }

                // High-Craft Floating Palette
                VStack(spacing: 0) {
                    Command(context: context, onDismiss: {
                        closeDialog()
                    }) {
                        content()
                    }
                }
                .frame(width: 560)
                .shadow(color: Color.black.opacity(0.35), radius: 28, x: 0, y: 14)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.97).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    )
                )
            }
            .onAppear {
                context.onDismiss = { [weak context] in
                    _ = context
                    closeDialog()
                }
                context.query = ""
                setupKeyMonitor()
            }
            .onDisappear {
                removeKeyMonitor()
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    context.query = ""
                    setupKeyMonitor()
                } else {
                    removeKeyMonitor()
                }
            }
        }
    }

    private func closeDialog() {
        withAnimation(.fluidSpring) {
            isPresented = false
        }
    }

    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isPresented else { return event }

            let isCmd = event.modifierFlags.contains(.command)
            let isCtrl = event.modifierFlags.contains(.control)
            let isOpt = event.modifierFlags.contains(.option)
            let isShift = event.modifierFlags.contains(.shift)
            let keyCode = event.keyCode

            // Cmd+K to toggle/close
            if isCmd && !isCtrl && !isOpt && keyCode == 40 {
                Task { @MainActor in
                    closeDialog()
                }
                return nil
            }

            // Escape to close
            if keyCode == 53 {
                Task { @MainActor in
                    closeDialog()
                }
                return nil
            }

            // Down Arrow (125), Ctrl+N (45), or Tab (48 without Shift)
            if keyCode == 125 || (isCtrl && keyCode == 45) || (!isShift && !isCmd && !isCtrl && !isOpt && keyCode == 48) {
                Task { @MainActor in
                    context.selectNext()
                }
                return nil
            }

            // Up Arrow (126), Ctrl+P (35), or Shift+Tab (48 with Shift)
            if keyCode == 126 || (isCtrl && keyCode == 35) || (isShift && !isCmd && !isCtrl && !isOpt && keyCode == 48) {
                Task { @MainActor in
                    context.selectPrevious()
                }
                return nil
            }

            // Enter / Return / NumPad Enter
            if keyCode == 36 || keyCode == 76 {
                Task { @MainActor in
                    context.executeSelected()
                }
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// MARK: - Command Palette Manager
@MainActor
@Observable
public final class CommandPaletteManager {
    public static let shared = CommandPaletteManager()

    public var isPresented: Bool = false

    public func toggle() {
        withAnimation(.fluidSpring) {
            isPresented.toggle()
        }
    }

    public func open() {
        withAnimation(.fluidSpring) {
            isPresented = true
        }
    }

    public func close() {
        withAnimation(.fluidSpring) {
            isPresented = false
        }
    }
}
