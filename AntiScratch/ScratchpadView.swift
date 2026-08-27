import SwiftUI
import AppKit

struct ScratchpadView: View {
    @EnvironmentObject private var store: NoteStore
    @FocusState private var editorFocused: Bool
    @State private var showingPages = false
    @State private var showingSettings = false
    @State private var horizontalOffset: CGFloat = 0
    @State private var isCompletingSwipe = false
    @State private var viewportWidth: CGFloat = 440
    @AppStorage("theme") private var themeName = "Mint"

    private var theme: AppTheme { AppTheme.named(themeName) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                noteViewport
            }
        }
        .frame(width: 310, height: 378)
        .background(
            HorizontalScrollMonitor(
                onChanged: { offset in updateSwipe(offset) },
                onEnded: { offset in finishSwipe(offset) }
            )
        )
        .tint(theme.accent)
        .sheet(isPresented: $showingPages) {
            PagesView().frame(width: 380, height: 340)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView().frame(width: 400, height: 430)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAntiScratchSettings)) { _ in
            showingSettings = true
        }
        .onAppear { editorFocused = true }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { showingPages = true } label: {
                Image(systemName: "rectangle.stack")
            }

            Spacer()

            Text("\(store.selectedIndex + 1) / \(store.notes.count)")
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(theme.secondary)

            Spacer()

            Button { store.addNote(); editorFocused = true } label: {
                Image(systemName: "plus")
            }
            Button(role: .destructive) { store.deleteSelected() } label: {
                Image(systemName: "trash")
            }
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .padding(.horizontal, 18)
        .frame(height: 42)
    }

    private func editor(for id: UUID?) -> some View {
        TextEditor(text: store.bindingForText(id: id))
            .font(.custom("Menlo", fixedSize: 14))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .focused($editorFocused)
            .autocorrectionDisabled(true)
            .accessibilityLabel("Scratchpad")
    }

    private var noteViewport: some View {
        GeometryReader { geometry in
            ZStack {
                currentPage
                    .frame(width: geometry.size.width)
                    .offset(x: horizontalOffset)

                if horizontalOffset < 0 {
                    previewPage(note: nextNote)
                        .frame(width: geometry.size.width)
                        .offset(x: horizontalOffset + geometry.size.width + 12)
                } else if horizontalOffset > 0, let previousNote {
                    previewPage(note: previousNote)
                        .frame(width: geometry.size.width)
                        .offset(x: horizontalOffset - geometry.size.width - 12)
                }
            }
            .clipped()
            .onAppear { viewportWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, width in viewportWidth = width }
        }
    }

    private var currentPage: some View {
        pageSurface(seed: store.selectedID?.hashValue ?? 0) {
            let binding = store.bindingForSelectedText()
            if NoteEngine.analyze(binding.wrappedValue).mode == .list,
               binding.wrappedValue.contains("\n") {
                ChecklistEditor(
                    text: binding,
                    accent: theme.accent,
                    foreground: theme.foreground,
                    onExit: {
                        editorFocused = false
                        DispatchQueue.main.async { editorFocused = true }
                    }
                )
            } else {
                VStack(spacing: 0) {
                    editor(for: store.selectedID)
                    auxiliaryPanel
                }
            }
        }
    }

    private func previewPage(note: Note?) -> some View {
        pageSurface(seed: note?.id.hashValue ?? 91_337) {
            VStack(spacing: 0) {
                ScrollView {
                    Text(note?.text ?? "")
                        .font(.custom("Menlo", fixedSize: 14))
                        .lineSpacing(4)
                        .foregroundStyle(theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 27)
                        .padding(.top, 14)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private func pageSurface<Content: View>(seed: Int, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            theme.background
            PaperTexture(
                color: theme.foreground,
                seed: seed
            )
            .allowsHitTesting(false)
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 5)
    }

    private var nextNote: Note? {
        let index = store.selectedIndex + 1
        guard store.notes.indices.contains(index) else { return nil }
        return store.notes[index]
    }

    private var previousNote: Note? {
        guard store.selectedIndex > 0 else { return nil }
        return store.notes[store.selectedIndex - 1]
    }

    @ViewBuilder
    private var auxiliaryPanel: some View {
        let binding = store.bindingForSelectedText()
        let analysis = NoteEngine.analyze(binding.wrappedValue)
        switch analysis.mode {
        case .timer:
            TimerPanel(duration: analysis.timerDuration, accent: theme.accent)
        case .sum, .average, .count:
            VStack(spacing: 6) {
                ForEach(analysis.results, id: \.label) { result in
                    HStack {
                        Text(result.label).foregroundStyle(theme.secondary)
                        Spacer()
                        Text(result.value).font(.system(.body, design: .monospaced, weight: .semibold))
                    }
                }
            }
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(theme.accent.opacity(0.07))
        default: EmptyView()
        }
    }

    private func updateSwipe(_ offset: CGFloat) {
        guard !isCompletingSwipe else { return }
        var proposed = offset
        if proposed > 0, previousNote == nil { proposed *= 0.2 }
        horizontalOffset = min(max(proposed, -viewportWidth), viewportWidth)
    }

    private func finishSwipe(_ offset: CGFloat) {
        guard !isCompletingSwipe else { return }
        let finalOffset = horizontalOffset
        let towardNext = finalOffset < 0
        guard abs(finalOffset) > 74, towardNext || previousNote != nil else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                horizontalOffset = 0
            }
            return
        }

        isCompletingSwipe = true
        let exitOffset: CGFloat = towardNext ? -(viewportWidth + 12) : viewportWidth + 12

        withAnimation(.easeOut(duration: 0.17)) {
            horizontalOffset = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            if towardNext {
                if store.selectedIndex == store.notes.count - 1 { store.addNote() }
                else { store.move(1) }
            } else {
                store.move(-1)
            }

            let transaction = Transaction(animation: nil)
            withTransaction(transaction) {
                horizontalOffset = 0
            }
            isCompletingSwipe = false
            editorFocused = true
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

private struct ChecklistEditor: View {
    @Binding var text: String
    let accent: Color
    let foreground: Color
    let onExit: () -> Void
    @State private var focusedLine: Int?

    private var lines: [String] { text.components(separatedBy: .newlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lines.first ?? "list:")
                .font(.custom("Menlo", fixedSize: 14))
                .foregroundStyle(foreground)

            ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { index, line in
                let checked = line.trimmingCharacters(in: .whitespaces).hasSuffix("/x")
                HStack(spacing: 10) {
                    Button { toggle(index + 1, checked: checked) } label: {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                    }
                    .buttonStyle(.plain)

                    ChecklistTextField(
                        text: itemBinding(index + 1, checked: checked),
                        focused: Binding(
                            get: { focusedLine == index + 1 },
                            set: { if $0 { focusedLine = index + 1 } }
                        ),
                        checked: checked,
                        onSubmit: { insertLine(after: index + 1) },
                        onDeleteEmpty: { removeLine(index + 1) }
                    )
                    .frame(height: 22)
                }
            }

            Spacer()
        }
        .tint(accent)
        .font(.custom("Menlo", fixedSize: 14))
        .padding(.horizontal, 27)
        .padding(.top, 14)
        .onAppear {
            if lines.count == 1 { text += "\n" }
            DispatchQueue.main.async { focusedLine = 1 }
        }
    }

    private func itemBinding(_ index: Int, checked: Bool) -> Binding<String> {
        Binding(
            get: {
                guard lines.indices.contains(index) else { return "" }
                return lines[index].replacingOccurrences(of: #"\s*/x\s*$"#, with: "", options: .regularExpression)
            },
            set: { value in
                var updated = lines
                guard updated.indices.contains(index) else { return }
                updated[index] = value + (checked ? " /x" : "")
                text = updated.joined(separator: "\n")
            }
        )
    }

    private func toggle(_ index: Int, checked: Bool) {
        var updated = lines
        guard updated.indices.contains(index) else { return }
        if checked {
            updated[index] = updated[index].replacingOccurrences(of: #"\s*/x\s*$"#, with: "", options: .regularExpression)
        } else {
            updated[index] += " /x"
        }
        text = updated.joined(separator: "\n")
    }

    private func insertLine(after index: Int) {
        var updated = lines
        let nextIndex = min(index + 1, updated.count)
        updated.insert("", at: nextIndex)
        text = updated.joined(separator: "\n")
        DispatchQueue.main.async { focusedLine = nextIndex }
    }

    private func removeLine(_ index: Int) {
        var updated = lines
        guard updated.indices.contains(index) else { return }
        updated.remove(at: index)
        text = updated.joined(separator: "\n")
        if updated.count == 1 { onExit() }
        DispatchQueue.main.async { focusedLine = index > 1 ? index - 1 : nil }
    }
}

private struct ChecklistTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let checked: Bool
    let onSubmit: () -> Void
    let onDeleteEmpty: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> BackspaceTextField {
        let field = BackspaceTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont(name: "Menlo", size: 14)
        field.onSubmit = onSubmit
        field.onDeleteEmpty = onDeleteEmpty
        return field
    }

    func updateNSView(_ field: BackspaceTextField, context: Context) {
        context.coordinator.parent = self
        field.onSubmit = onSubmit
        field.onDeleteEmpty = onDeleteEmpty
        field.textColor = checked ? .secondaryLabelColor : .labelColor
        if field.stringValue != text { field.stringValue = text }
        if focused, field.window?.firstResponder !== field.currentEditor() {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ChecklistTextField
        init(_ parent: ChecklistTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty {
                parent.onDeleteEmpty()
                return true
            }
            return false
        }
    }
}

private final class BackspaceTextField: NSTextField {
    var onSubmit: (() -> Void)?
    var onDeleteEmpty: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            onSubmit?()
        } else if (event.keyCode == 51 || event.keyCode == 117), stringValue.isEmpty {
            onDeleteEmpty?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct TimerPanel: View {
    let duration: TimeInterval?
    let accent: Color
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let display = duration.map { max($0 - elapsed, 0) } ?? elapsed
            HStack {
                Image(systemName: duration == nil ? "stopwatch" : "timer")
                Text(clock(display))
                    .font(.system(size: 25, weight: .semibold, design: .monospaced))
                Spacer()
                Button("Reiniciar") { startedAt = Date() }
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(accent.opacity(0.08))
        }
    }

    private func clock(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct HorizontalScrollMonitor: NSViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var finishWorkItem: DispatchWorkItem?

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                let x = event.scrollingDeltaX
                let y = event.scrollingDeltaY
                guard event.momentumPhase.isEmpty,
                      abs(x) > abs(y) * 1.2,
                      abs(x) > 0.2 else { return event }

                if event.phase == .began {
                    self.finishWorkItem?.cancel()
                    self.accumulatedX = 0
                }
                self.accumulatedX += x
                let visualOffset = self.accumulatedX
                self.onChanged(visualOffset)

                self.finishWorkItem?.cancel()
                let finish = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let finalOffset = self.accumulatedX
                    self.accumulatedX = 0
                    self.onEnded(finalOffset)
                }
                self.finishWorkItem = finish
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: finish)
                return event
            }
        }

        deinit {
            finishWorkItem?.cancel()
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

private struct PaperTexture: View {
    let color: Color
    let seed: Int

    var body: some View {
        Canvas { context, size in
            let grid: CGFloat = 26
            var lines = Path()
            stride(from: CGFloat.zero, through: size.width, by: grid).forEach { x in
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat.zero, through: size.height, by: grid).forEach { y in
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(color.opacity(0.085)), lineWidth: 0.65)

            var grain = Path()
            let columns = max(Int(size.width / 13), 1)
            let rows = max(Int(size.height / 13), 1)
            for row in 0...rows {
                for column in 0...columns where abs(row * 17 + column * 31 + seed) % 7 == 0 {
                    let jitterX = CGFloat(abs(row * 11 + column * 5 + seed) % 9) / 3
                    let jitterY = CGFloat(abs(row * 3 + column * 13 + seed / 7) % 9) / 3
                    let point = CGPoint(x: CGFloat(column) * 13 + jitterX,
                                        y: CGFloat(row) * 13 + jitterY)
                    grain.addEllipse(in: CGRect(origin: point, size: CGSize(width: 1.05, height: 1.05)))
                }
            }
            context.fill(grain, with: .color(color.opacity(0.15)))
        }
        .opacity(0.9)
    }
}

private struct PagesView: View {
    @EnvironmentObject private var store: NoteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Páginas")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Pilha temporária de notas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 25, height: 25)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fechar páginas")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.45)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(Array(store.notes.enumerated()), id: \.element.id) { index, note in
                        pageRow(note, number: index + 1)
                    }
                }
                .padding(12)
            }

            Divider().opacity(0.45)

            HStack {
                Text("\(store.notes.count) \(store.notes.count == 1 ? "nota" : "notas")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.addNote()
                    dismiss()
                } label: {
                    Label("Nova nota", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial)
    }

    private func pageRow(_ note: Note, number: Int) -> some View {
        let lines = note.text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let title = lines.first ?? "Nota em branco"
        let preview = lines.dropFirst().first ?? (note.text.isEmpty ? "Página vazia" : "Nota de uma linha")
        let selected = store.selectedID == note.id

        return Button {
            store.selectedID = note.id
            dismiss()
        } label: {
            HStack(spacing: 11) {
                Text("\(number)")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 22, height: 22)
                    .background(selected ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.05), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(note.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.05), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsView: View {
    @AppStorage("theme") private var themeName = "Mint"
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Acesso ao app") {
                    LabeledContent("Atalho global") {
                        Text("⌥ A")
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                    }
                    Toggle("Mostrar ícone na barra de menus", isOn: $showMenuBarIcon)
                    Toggle("Ocultar ícone do Dock", isOn: $hideDockIcon)
                }
                Section("Tema") {
                    ForEach(AppTheme.all, id: \.name) { theme in
                        Button {
                            themeName = theme.name
                        } label: {
                            HStack {
                                Circle().fill(theme.accent).frame(width: 18, height: 18)
                                Text(theme.displayName).foregroundStyle(.primary)
                                Spacer()
                                if themeName == theme.name { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                Section("Gestos") {
                    Label("Deslize horizontalmente para mudar de página", systemImage: "hand.draw")
                    Label("Suas notas ficam neste dispositivo", systemImage: "lock.shield")
                }
            }
            .navigationTitle("Personalizar")
            .toolbar { Button("Concluir") { dismiss() } }
        }
        .frame(width: 400, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct AppTheme {
    let name: String
    let background: Color
    let foreground: Color
    let secondary: Color
    let accent: Color

    var displayName: String {
        switch name {
        case "Mint": return "Hortelã"
        case "Aubergine": return "Berinjela"
        case "Paper": return "Papel"
        default: return name
        }
    }

    static let all = [
        AppTheme(name: "Mint", background: Color(red: 0.025, green: 0.032, blue: 0.03), foreground: .white, secondary: .gray, accent: Color(red: 0.35, green: 0.96, blue: 0.68)),
        AppTheme(name: "Aubergine", background: Color(red: 0.10, green: 0.045, blue: 0.12), foreground: Color(red: 1, green: 0.92, blue: 0.98), secondary: Color(red: 0.65, green: 0.52, blue: 0.65), accent: Color(red: 1, green: 0.43, blue: 0.72)),
        AppTheme(name: "Paper", background: Color(red: 0.94, green: 0.90, blue: 0.79), foreground: Color(red: 0.16, green: 0.13, blue: 0.09), secondary: Color(red: 0.46, green: 0.39, blue: 0.29), accent: Color(red: 0.55, green: 0.30, blue: 0.12))
    ]

    static func named(_ name: String) -> AppTheme { all.first { $0.name == name } ?? all[0] }
}
