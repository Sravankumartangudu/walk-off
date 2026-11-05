// Presence engine tests with a fake clock.
//   swiftc -o /tmp/walkoff-tests tests/main.swift Sources/Presence.swift && /tmp/walkoff-tests
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("✗ line \(line): \(what)") }
}

/// Drives the engine second by second. `face(t)` says whether a close face is in view at time t.
final class Sim {
    let p = Presence()
    var t = 0.0
    var lastInput = 0.0
    var locked = false
    var problem: String?
    var actions: [(Double, Action)] = []

    init(_ rules: Rules = Rules()) { p.rules = rules }

    func run(until end: Double, face: (Double) -> Bool, framesPerSecond: Int = 4) {
        while t < end {
            if p.cameraWanted && problem == nil {
                for i in 0..<framesPerSecond {
                    let ft = t + Double(i) / Double(framesPerSecond)
                    p.frame(at: ft, faces: face(ft) ? 1 : 0)
                }
            }
            t += 1
            let a = p.tick(now: t, idle: t - lastInput, locked: locked, enabled: true, paused: false, cameraProblem: problem)
            if a != .none { actions.append((t, a)) }
            if a == .lock { locked = true }
        }
    }
    var locks: [Double] { actions.filter { $0.1 == .lock }.map { $0.0 } }
    var wakes: [Double] { actions.filter { $0.1 == .wake }.map { $0.0 } }
}

// Typing all the time: the camera never turns on and nothing locks.
do {
    let s = Sim()
    var cameraEver = false
    while s.t < 300 { s.lastInput = s.t; s.run(until: s.t + 1) { _ in false }; cameraEver = cameraEver || s.p.cameraWanted }
    check(!cameraEver, "camera stays off while typing")
    check(s.locks.isEmpty, "no lock while typing")
    check(s.p.status == .here, "status here")
}

// Reading quietly in front of the Mac: never locks, camera only peeks.
do {
    let s = Sim()
    var onSeconds = 0
    while s.t < 600 { s.run(until: s.t + 1) { _ in true }; if s.p.cameraWanted { onSeconds += 1 } }
    check(s.locks.isEmpty, "no lock while you're there")
    check(onSeconds < 600 / 5, "camera mostly off while you're there (on \(onSeconds)s)")
}

// Walking away: locks about idle + leave delay later.
do {
    let s = Sim()
    s.run(until: 120) { _ in false }
    check(s.locks.count == 1, "locks once (got \(s.locks))")
    if let l = s.locks.first { check(l >= 25 && l <= 28, "locks after ~15s idle + 10s gone (at \(l))") }
}

// Leaving mid-read with peeks: locks within recheck + leave delay of leaving.
do {
    let s = Sim()
    s.run(until: 200) { t in t < 100 }
    check(s.locks.count == 1, "locks once after leaving")
    if let l = s.locks.first { check(l > 100 && l <= 100 + 10 + 10 + 3, "locks soon after leaving at 100 (at \(l))") }
}

// Continuous camera: locks leaveAfter after the last face.
do {
    var r = Rules(); r.recheckEvery = 0
    let s = Sim(r)
    s.run(until: 200) { t in t < 100 }
    if let l = s.locks.first { check(l >= 110 && l <= 112, "continuous locks ~10s after last face (at \(l))") } else { check(false, "continuous should lock") }
}

// A key press just before the lock would fire cancels it.
do {
    let s = Sim()
    s.run(until: 24) { _ in false }
    s.lastInput = s.t
    s.run(until: 30) { _ in false }
    check(s.locks.isEmpty, "key press resets the countdown")
}

// A broken camera never locks.
do {
    let s = Sim()
    s.problem = "No camera found"
    s.run(until: 300) { _ in false }
    check(s.locks.isEmpty, "no lock without a camera")
    check(s.p.status == .problem("No camera found"), "shows the camera problem")
}

// A camera that turns on but sends nothing never locks, and says so.
do {
    let s = Sim()
    s.run(until: 300, face: { _ in false }, framesPerSecond: 0)
    check(s.locks.isEmpty, "no lock when the camera sends no pictures")
    check(s.p.status == .problem("The camera isn't sending pictures"), "reports the stuck camera (got \(s.p.status))")
}

// Coming back after a lock wakes the screen once.
do {
    let s = Sim()
    s.run(until: 200) { t in t >= 150 }
    check(s.locks.count == 1, "locked once")
    check(s.wakes.count == 1, "woke once (got \(s.wakes))")
    if let w = s.wakes.first { check(w > 150 && w <= 153, "wakes within ~2s of returning (at \(w))") }
}

// Locking by hand while sitting there doesn't wake the screen straight back up.
do {
    let s = Sim()
    s.locked = true
    s.run(until: 60) { _ in true }
    check(s.wakes.isEmpty, "no wake while you never left")
    s.run(until: 120) { t in t < 70 || t > 90 }
    check(s.wakes.count == 1, "wakes after leaving and coming back (got \(s.wakes))")
}

// Hanging around in front of a locked screen doesn't keep waking it.
do {
    let s = Sim()
    s.locked = true
    s.run(until: 20) { _ in false }
    s.run(until: 200) { _ in true }
    check(s.wakes.count == 1, "one wake, not one per minute (got \(s.wakes))")
}

// Wake off, or past the watch window: camera rests.
do {
    var r = Rules(); r.wakeOnReturn = false
    let s = Sim(r)
    s.locked = true
    s.run(until: 30) { t in t > 20 }
    check(!s.p.cameraWanted && s.p.status == .resting && s.wakes.isEmpty, "no watching when wake is off")

    var r2 = Rules(); r2.returnWatchFor = 60
    let s2 = Sim(r2)
    s2.locked = true
    s2.run(until: 100) { _ in false }
    check(!s2.p.cameraWanted && s2.p.status == .resting, "camera rests after the watch window")
}

// Unlocking resets: no instant re-lock just because idle is high.
do {
    let s = Sim()
    s.run(until: 40) { _ in false }
    check(s.locks.count == 1, "locked")
    s.locked = false
    s.lastInput = s.t
    s.run(until: 45) { _ in true }
    check(s.locks.count == 1 && s.p.status == .here, "fresh start after unlock")
}

// Paused and off keep the camera off.
do {
    let p = Presence()
    _ = p.tick(now: 100, idle: 100, locked: false, enabled: true, paused: true, cameraProblem: nil)
    check(!p.cameraWanted && p.status == .paused, "paused")
    _ = p.tick(now: 101, idle: 101, locked: false, enabled: false, paused: false, cameraProblem: nil)
    check(!p.cameraWanted && p.status == .off, "off")
}

// Waking from sleep while locked: no false "camera stuck", watching carries on.
do {
    let s = Sim()
    s.locked = true
    s.run(until: 20) { _ in false }
    s.t += 3600 // asleep for an hour
    s.lastInput = s.t
    s.run(until: s.t + 1, face: { _ in false }, framesPerSecond: 0)
    check(s.p.status != .problem("The camera isn't sending pictures"), "no stuck-camera report straight after sleep (got \(s.p.status))")
}

print(failures == 0 ? "✓ all presence tests passed" : "✗ \(failures) failed")
exit(failures == 0 ? 0 : 1)
