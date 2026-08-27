import Foundation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String = ""
    var createdAt = Date()
    var updatedAt = Date()
}

@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = [] { didSet { save() } }
    @Published var selectedID: UUID?

    private let storageKey = "antiscratch.notes.v1"
    private let orderMigrationKey = "antiscratch.notes.chronological.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data),
           !decoded.isEmpty {
            if UserDefaults.standard.bool(forKey: orderMigrationKey) {
                notes = decoded
            } else {
                notes = decoded.reversed()
                UserDefaults.standard.set(true, forKey: orderMigrationKey)
            }
        } else {
            notes = [Note(text: "Capture ideas before they disappear.\n\nTry math:\n24 * 7 =\n\nOr type list: and press Return.")]
            UserDefaults.standard.set(true, forKey: orderMigrationKey)
        }
        selectedID = notes.last?.id
    }

    var selectedIndex: Int {
        notes.firstIndex { $0.id == selectedID } ?? 0
    }

    func bindingForSelectedText() -> Binding<String> {
        bindingForText(id: selectedID)
    }

    func bindingForText(id: UUID?) -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard let self, let id,
                      let index = self.notes.firstIndex(where: { $0.id == id }) else { return "" }
                return self.notes[index].text
            },
            set: { [weak self] value in
                guard let self, let id,
                      let index = self.notes.firstIndex(where: { $0.id == id }) else { return }
                self.notes[index].text = NoteEngine.renderInlineResults(in: value)
                self.notes[index].updatedAt = Date()
            }
        )
    }

    func addNote() {
        let note = Note()
        notes.append(note)
        selectedID = note.id
    }

    func deleteSelected() {
        guard notes.count > 1 else {
            notes[0].text = ""
            return
        }
        let index = selectedIndex
        notes.remove(at: index)
        selectedID = notes[min(index, notes.count - 1)].id
    }

    func move(_ offset: Int) {
        let next = selectedIndex + offset
        guard notes.indices.contains(next) else { return }
        selectedID = notes[next].id
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
