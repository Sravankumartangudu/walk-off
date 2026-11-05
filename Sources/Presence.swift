// The presence engine: decides when the camera should be on, when to lock, and when to wake the screen.
// No camera or system calls in here, so tests/main.swift can drive it with a fake clock.
//
//   You type or move the mouse     → camera off ("here").
//   Idle for `idleBeforeCheck`     → camera on, looking for a face that's close enough.
//   Face found                     → camera off again until `recheckEvery` (or stays on when that's 0).
//   No face for `leaveAfter`       → lock.
//   Locked                         → watch for `returnWatchFor`; once you've been gone a few seconds,
//                                    a face that stays for a few frames wakes the screen.
//
// The camera failing never locks the Mac: no frames means "can't tell", not "you left".
import Foundation

struct Rules: Equatable {
    var idleBeforeCheck: Double = 15
    var leaveAfter: Double = 10
    /// Seconds the camera rests after it has seen you. 0 keeps it on while you're idle.
    var recheckEvery: Double = 10
    var wakeOnReturn = true
    var returnWatchFor: Double = 30 * 60
}

enum Status: Equatable {
    case off
    case paused
    case problem(String)
    case here
    case checking
    case seenYou
    case locking
    case away
    case resting
}

enum Action: Equatable {
    case none, lock, wake
}

final class Presence {
    var rules = Rules()
    private(set) var cameraWanted = false
    private(set) var status: Status = .here

    /// How long the screen must be empty after a lock before a face counts as "back". Stops a manual
    /// lock (⌃⌘Q while you're still sitting there) from waking the screen straight away.
    static let goneBeforeWake: Double = 5
    /// Frames in a row with a face before waking, so a passing glance doesn't.
    static let framesToWake = 3
    /// After a wake, wait this long before waking again (you might be busy on your phone).
    static let wakeCooldown: Double = 60
    /// The camera counts as stuck after this long without a picture.
    static let stallAfter: Double = 8

    private var cameraOnSince: Double?
    private var windowStart: Double?
    private var lastFrame: Double?
    private var lastFace: Double?
    private var nextCheck: Double = 0
    private var lastLock: Double = -.infinity

    private var lockedSince: Double?
    private var emptySince: Double?
    private var armed = false
    private var faceStreak = 0
    private var lastWake: Double = -.infinity
    private var lastTick: Double?

    /// One processed camera picture. `faces` counts only faces close enough to count.
    func frame(at t: Double, faces: Int) {
        guard cameraWanted else { return }
        lastFrame = t
        if windowStart == nil { windowStart = t }
        if faces > 0 {
            lastFace = t
            faceStreak += 1
            emptySince = nil
        } else {
            faceStreak = 0
            if emptySince == nil { emptySince = t }
        }
    }

    /// Called about once a second. `idle` is seconds since the last key press or mouse move.
    func tick(now: Double, idle: Double, locked: Bool, enabled: Bool, paused: Bool, cameraProblem: String?) -> Action {
        // A long gap between ticks means the Mac slept: old pictures say nothing about now.
        if let last = lastTick, now - last > 5 { camera(false) }
        lastTick = now
        if !enabled { camera(false); status = .off; lockedSince = nil; return .none }
        if paused { camera(false); status = .paused; lockedSince = nil; return .none }

        if locked {
            if lockedSince == nil {
                lockedSince = now
                camera(false)
                armed = false
                emptySince = nil
            }
            guard rules.wakeOnReturn, now - lockedSince! < rules.returnWatchFor else {
                camera(false); status = .resting; return .none
            }
            if let p = cameraProblem { camera(false); status = .problem(p); return .none }
            camera(true, now)
            if let p = stalled(now) { status = .problem(p); return .none }
            status = .away
            if !armed, let e = emptySince, now - e >= Self.goneBeforeWake { armed = true }
            if armed && faceStreak >= Self.framesToWake && now - lastWake >= Self.wakeCooldown {
                lastWake = now
                armed = false
                return .wake
            }
            return .none
        }

        if lockedSince != nil {
            // Just unlocked: start fresh.
            lockedSince = nil
            camera(false)
            nextCheck = 0
        }

        if idle < rules.idleBeforeCheck {
            camera(false); nextCheck = 0; status = .here; return .none
        }
        if now < nextCheck {
            camera(false); status = .seenYou; return .none
        }
        if let p = cameraProblem { camera(false); status = .problem(p); return .none }
        camera(true, now)
        if let p = stalled(now) { status = .problem(p); return .none }
        guard let start = windowStart else { status = .checking; return .none }

        if let f = lastFace, f >= start {
            if rules.recheckEvery > 0 {
                nextCheck = now + rules.recheckEvery
                camera(false)
                status = .seenYou
                return .none
            }
            if now - f < 2 { status = .seenYou; return .none }
        }
        let goneSince = max(start, lastFace ?? start)
        status = .checking
        // Idle must cover the whole empty stretch too, or a key press inside it would be ignored.
        if now - goneSince >= rules.leaveAfter && idle >= now - goneSince && now - lastLock > 5 {
            lastLock = now
            camera(false)
            status = .locking
            return .lock
        }
        return .none
    }

    private func camera(_ on: Bool, _ now: Double = 0) {
        if on {
            if !cameraWanted { cameraWanted = true; cameraOnSince = now }
        } else if cameraWanted {
            cameraWanted = false
            cameraOnSince = nil
            windowStart = nil
            lastFrame = nil
            faceStreak = 0
            emptySince = nil
        }
    }

    private func stalled(_ now: Double) -> String? {
        let since = lastFrame ?? cameraOnSince ?? now
        return now - since > Self.stallAfter ? "The camera isn't sending pictures" : nil
    }
}
