import Foundation

/// Windows the last move or restore had to skip. Until the next move or
/// screen change the ⧉ menu offers "Retry N windows that didn't move" at the top.
public struct RetryOffer {
    public let kind: JobKind
    public let at: Date
    public let missed: [pid_t: Set<UInt32>]
    let run: @MainActor ([pid_t: Set<UInt32>]) -> Void
}

/// "Safari — Title", or just the app, at most 58 characters.
func retryTitle(app: String, title: String?) -> String {
    var t = (title?.isEmpty == false) ? app + " — " + title! : app
    if t.count > 60 { t = String(t.prefix(57)) + "…" }
    return t
}
