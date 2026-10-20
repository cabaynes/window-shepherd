import Foundation

/// Windows the last move or restore had to skip. For two minutes the ⧉ menu
/// offers "Retry N windows that didn't move" at the top.
public struct RetryOffer {
    public let kind: JobKind
    public let at: Date
    public let missed: [pid_t: Set<UInt32>]
    let run: @MainActor ([pid_t: Set<UInt32>]) -> Void
}

/// How long the retry offer stays in the menu.
public let retryFor: TimeInterval = 120

/// "Safari — Title", or just the app, at most 58 characters.
func retryTitle(app: String, title: String?) -> String {
    var t = (title?.isEmpty == false) ? app + " — " + title! : app
    if t.count > 60 { t = String(t.prefix(57)) + "…" }
    return t
}
