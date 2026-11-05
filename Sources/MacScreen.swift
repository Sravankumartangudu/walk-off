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

    /// Turns the display on, as if you'd touched a key. The lock screen stays locked.
    static func wake() {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionDeclareUserActivity("Walk Off: you're back" as CFString, kIOPMUserActiveLocal, &id)
        guard result == kIOReturnSuccess else {
            Log.presence.error("Couldn't wake the screen (IOKit error \(result))")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { IOPMAssertionRelease(id) }
    }

    static func openTouchIDSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension")!)
    }

    static func openCameraPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }
}
