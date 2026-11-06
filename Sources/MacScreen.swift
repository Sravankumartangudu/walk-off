// The few system calls Walk Off makes: read idle time and lock state, lock, turn the display off, wake it.
// None of them can unlock the Mac. Only you can, with Touch ID, your Apple Watch or your password.
import AppKit
import IOKit.pwr_mgt

enum MacScreen {
    /// Seconds since the last key press, click or mouse move.
    static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static var isLocked: Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private typealias LockFunction = @convention(c) () -> Int32
    private static let lockFunction: LockFunction? = {
        // The same call the  menu's Lock Screen uses.
        guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let f = dlsym(h, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(f, to: LockFunction.self)
    }()

    static func lock() {
        releaseWake()
        if let lockFunction {
            _ = lockFunction()
        } else {
            // Fallback: display sleep locks too when "Require password" is set to Immediately.
            displayOff()
        }
    }

    static func displayOff() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }

    private static var wakeID: IOPMAssertionID?
    private static var keepOnID: IOPMAssertionID?
    /// How long a wake keeps the lock screen lit if nobody unlocks.
    private static let wakeHold: Double = 20
    /// How long the display stays on after an unlock that followed a wake.
    private static let keepOnAfterUnlock: Double = 60

    /// Turns the display on, as if you'd touched a key. The lock screen stays locked.
    /// Held until you unlock (or `wakeHold`): letting go early makes macOS turn the display off
    /// about 10 seconds later, which locks the Mac again right after your watch unlocked it.
    static func wake() {
        releaseWake()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionDeclareUserActivity("Walk Off: you're back" as CFString, kIOPMUserActiveLocal, &id)
        guard result == kIOReturnSuccess else {
            Log.presence.error("Couldn't wake the screen (IOKit error \(result))")
            return
        }
        wakeID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeHold) {
            if wakeID == id, isLocked { releaseWake() }
        }
    }

    /// The screen just unlocked. If Walk Off woke it, keep the display on for a minute before
    /// handing back to the normal display-sleep timer, so it doesn't go dark and lock again.
    static func unlocked() {
        guard wakeID != nil else { return }
        var id: IOPMAssertionID = 0
        if IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                       "Walk Off: you just unlocked" as CFString, &id) == kIOReturnSuccess {
            keepOnID = id
            DispatchQueue.main.asyncAfter(deadline: .now() + keepOnAfterUnlock) {
                if keepOnID == id { IOPMAssertionRelease(id); keepOnID = nil }
            }
        }
        if let w = wakeID { IOPMAssertionRelease(w); wakeID = nil }
    }

    /// Lets the display sleep as normal: on a lock, or when a wake wasn't followed by an unlock.
    static func releaseWake() {
        if let w = wakeID { IOPMAssertionRelease(w); wakeID = nil }
        if let k = keepOnID { IOPMAssertionRelease(k); keepOnID = nil }
    }

    static func openTouchIDSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension")!)
    }

    static func openCameraPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }
}
