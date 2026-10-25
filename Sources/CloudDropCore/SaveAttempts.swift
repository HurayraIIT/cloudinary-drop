import Foundation

/// The settings window's saves of a Cloudinary URL: one at a time, and one that finishes after the window was
/// reopened neither closes it nor clears what was typed into it since.
public struct SaveAttempts: Sendable {
    public struct Attempt: Equatable, Sendable {
        let number: Int
        let opening: Int
        let fieldText: String
    }

    private var running: Int?
    private var lastNumber = 0
    private var opening = 0

    public init() {}

    public var isSaving: Bool { running != nil }

    /// Each time the window is shown, even while it's already open.
    public mutating func windowOpened() {
        opening += 1
    }

    /// Nil while another save is still running.
    public mutating func begin(fieldText: String) -> Attempt? {
        guard running == nil else { return nil }
        lastNumber += 1
        running = lastNumber
        return Attempt(number: lastNumber, opening: opening, fieldText: fieldText)
    }

    public mutating func finish(_ attempt: Attempt) {
        if running == attempt.number { running = nil }
    }

    /// Only the window the save began in is closed by it.
    public func mayClose(after attempt: Attempt) -> Bool {
        attempt.opening == opening
    }

    /// Only what the save was given is cleared, never something typed since.
    public func mayClearField(after attempt: Attempt, currentText: String) -> Bool {
        mayClose(after: attempt) && currentText == attempt.fieldText
    }
}
