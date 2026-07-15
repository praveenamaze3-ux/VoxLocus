
import EventKit

actor RemindersService {

    static let shared = RemindersService()
    private let store = EKEventStore()
    private let listName = "SmartNotes"

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }
    func createChecklist(for todos: [TodoItem], noteTitle: String) async throws -> [TodoItem] {
        guard try await requestAccess() else {
            throw RemindersError.accessDenied
        }

        let calendar = try fetchOrCreateList()
        var updated: [TodoItem] = []

        for todo in todos {
            let reminder = EKReminder(eventStore: store)
            reminder.title = todo.text
            reminder.notes = String(localized: "From note: \(noteTitle)")
            reminder.calendar = calendar
            reminder.isCompleted = todo.isCompleted

            try store.save(reminder, commit: false)
            var copy = todo
            copy.reminderIdentifier = reminder.calendarItemIdentifier
            updated.append(copy)
        }

        try store.commit()
        return updated
    }

    private func fetchOrCreateList() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == listName }) {
            return existing
        }
        let newList = EKCalendar(for: .reminder, eventStore: store)
        newList.title = listName
        if let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local }) {
            newList.source = source
        }
        try store.saveCalendar(newList, commit: true)
        return newList
    }

    enum RemindersError: LocalizedError {
        case accessDenied
        var errorDescription: String? { String(localized: "Reminders access was denied. Enable it in Settings to auto-create checklists.") }
    }
}

