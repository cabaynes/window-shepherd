import Foundation

public enum JobProblem: Equatable {
    case outOfTime, interrupted
}

public enum JobKind: String {
    case move, restore
}

/// One step of a job. It may queue more steps through the context, and may
/// return a wait (seconds) before the next step; nothing is held meanwhile.
public typealias JobStep = @MainActor (JobContext) async -> TimeInterval?

/// The running job's step list, which steps may extend.
@MainActor
public final class JobContext {
    var steps: [JobStep]
    /// Index of the step now running.
    public internal(set) var index = 0

    init(_ steps: [JobStep]) { self.steps = steps }

    public func insert(_ s: @escaping JobStep, at i: Int) { steps.insert(s, at: min(i, steps.count)) }
    public func append(_ s: @escaping JobStep) { steps.append(s) }
}

/// Runs a job one small step at a time, with a short gap between steps so
/// hotkeys and the menu always get through, and a hard overall deadline. A
/// new job interrupts the old one, which still reports what it got done.
/// Every app is tried fresh on every job: nothing is benched between jobs.
@MainActor
public final class JobRunner {
    private struct Active {
        let id: Int
        let kind: JobKind
        let deadline: Date
        let done: @MainActor (JobProblem?) -> Void
        var task: Task<Void, Never>?
    }

    private let gap: TimeInterval
    private var active: Active?
    private var nextID = 0

    public var onBusyChanged: (() -> Void)?

    public init(gap: TimeInterval = 0.02) { self.gap = gap }

    public var current: (kind: JobKind, deadline: Date)? { active.map { ($0.kind, $0.deadline) } }

    public func run(_ kind: JobKind, steps: [JobStep], deadline seconds: TimeInterval,
                    done: @escaping @MainActor (JobProblem?) -> Void) {
        if let old = active {
            active = nil
            old.task?.cancel()
            old.done(.interrupted)
        }
        nextID += 1
        let id = nextID
        let ctx = JobContext(steps)
        active = Active(id: id, kind: kind, deadline: Date().addingTimeInterval(seconds), done: done)
        onBusyChanged?()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loop(id, ctx)
        }
        if active?.id == id { active?.task = task }
    }

    private func loop(_ id: Int, _ ctx: JobContext) async {
        var i = 0
        while let job = active, job.id == id {
            if i >= ctx.steps.count || Date() > job.deadline {
                finish(id, i < ctx.steps.count ? .outOfTime : nil)
                return
            }
            ctx.index = i
            let t = Date()
            let wait = await ctx.steps[i](ctx)
            let took = Date().timeIntervalSince(t)
            if took > 0.3 { Log.info(String(format: "slow step %.2fs", took)) }
            i += 1
            guard active?.id == id else { return }
            let pause = max(gap, wait ?? 0)
            try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
        }
    }

    private func finish(_ id: Int, _ problem: JobProblem?) {
        guard let job = active, job.id == id else { return }
        active = nil
        job.done(problem)
        onBusyChanged?()
    }

    /// Stop the running job. `reportAs` nil = silently (its target is gone,
    /// e.g. the screens changed); otherwise its `done` gets that problem.
    public func stopCurrent(reportAs: JobProblem?) {
        guard let job = active else { return }
        active = nil
        job.task?.cancel()
        if let reportAs { job.done(reportAs) }
        onBusyChanged?()
    }

    /// Safety net: a job that outlived its own deadline by 5 s is stale; drop
    /// it so it can't pause snapshots (and so auto-restore) forever.
    public func clearIfStale(now: Date) {
        guard let job = active, now > job.deadline.addingTimeInterval(5) else { return }
        Log.info("cleared a stale job")
        active = nil
        job.task?.cancel()
        onBusyChanged?()
    }
}

/// Generous because each step yields: a long job is slow, never a hang.
public func deadlineFor(windowCount n: Int) -> TimeInterval { min(10 + 1.0 * Double(n), 120) }
