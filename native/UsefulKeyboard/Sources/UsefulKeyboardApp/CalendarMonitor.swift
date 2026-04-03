import EventKit
import Foundation
import UsefulKeyboardCore

struct UpcomingMeetingEvent {
    let id: String
    let title: String
    let startDate: Date
}

final class CalendarMonitor {
    private let store = EKEventStore()
    private var timer: Timer?
    private var notifiedEvents = Set<String>()
    var onMeetingSoon: ((UpcomingMeetingEvent) -> Void)?

    func start() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted, let self else { return }
            DispatchQueue.main.async {
                self.checkMeetings()
                self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    self?.checkMeetings()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Returns the current calendar event if one is happening right now.
    func currentEvent() -> UpcomingMeetingEvent? {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(60), calendars: nil)
        let events = store.events(matching: predicate)
        for event in events {
            guard let startDate = event.startDate, let endDate = event.endDate else { continue }
            if startDate <= now && endDate > now {
                return UpcomingMeetingEvent(
                    id: event.eventIdentifier ?? "",
                    title: event.title ?? "Meeting",
                    startDate: startDate
                )
            }
        }
        return nil
    }

    /// Returns the current or recently started event (within 15 minutes)
    /// for meeting detection. Prefers currently active events over nearby ones.
    func currentOrNearbyEvent() -> CalendarEventContext? {
        currentOrNearbyRichEvent()?.asCalendarEventContext
    }

    /// Returns rich calendar context with attendees, recurrence, notes, etc.
    func currentOrNearbyRichEvent() -> RichCalendarContext? {
        let now = Date()
        let searchStart = now.addingTimeInterval(-15 * 60)
        let searchEnd = now.addingTimeInterval(5 * 60)
        let predicate = store.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: nil)
        let events = store.events(matching: predicate)

        var nearby: RichCalendarContext?
        for event in events {
            guard let startDate = event.startDate, let endDate = event.endDate else { continue }
            let ctx = richContext(from: event)
            // Currently active — return immediately
            if startDate <= now && endDate > now {
                return ctx
            }
            // Recently started (within 15 min) or about to start (within 5 min)
            if nearby == nil {
                nearby = ctx
            }
        }
        return nearby
    }

    /// Extract rich context from an EKEvent.
    private func richContext(from event: EKEvent) -> RichCalendarContext {
        let attendeeNames = event.attendees?.compactMap { participant -> String? in
            participant.name ?? participant.url.absoluteString
        } ?? []

        return RichCalendarContext(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Meeting",
            attendees: attendeeNames,
            attendeeCount: event.attendees?.count ?? 0,
            notes: event.notes,
            isRecurring: event.hasRecurrenceRules,
            organizer: event.organizer?.name,
            location: event.location
        )
    }

    private func checkMeetings() {
        let now = Date()
        let end = now.addingTimeInterval(5 * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        for event in events {
            guard let eventID = event.eventIdentifier, !notifiedEvents.contains(eventID) else {
                continue
            }
            notifiedEvents.insert(eventID)
            onMeetingSoon?(UpcomingMeetingEvent(
                id: eventID,
                title: event.title ?? "Meeting",
                startDate: event.startDate
            ))
        }
    }
}
