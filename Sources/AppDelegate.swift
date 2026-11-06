import AppKit
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Prefs.shared
    private let presence = Presence()
    private let camera = Camera()
    private let check = CheckWindow()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var launchedAtLogin = false
    /// nil = not paused; .distantFuture = until resumed.
    private var pausedUntil: Date?
    private var lastRestart = Date.distantPast
    private var today = Calendar.current.startOfDay(for: Date())
    private var locksToday = 0
    private var wakesToday = 0

    private var now: Double { Date().timeIntervalSinceReferenceDate }
    private var lastWatchLog: Double = 0
    private var loggedLocked: Bool?
    private var loggedStatus: Status?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A login item is opened with this flag; don't pop the welcome window at login.
        if let e = NSAppleEventManager.shared().currentAppleEvent,
           e.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            launchedAtLogin = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs.applyAppearance()
        presence.rules = prefs.rules
        prefs.onChange = { [weak self] in
            guard let self else { return }
            self.presence.rules = self.prefs.rules
            self.tick()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = AppInfo.name
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        NexusBeacon.start(name: AppInfo.name) { [weak self] in
            guard let self else { return ("ok", "") }
            if case .problem = self.presence.status { return ("warn", self.statusText) }
            return ("ok", self.statusText)
        }
        NexusBeacon.attach(statusItem)

        camera.onFrame = { [weak self] faces, image in
            guard let self else { return }
            let min = self.prefs.distance.minHeight
            let counted = faces.filter { $0.box.height >= min }.count
            self.presence.frame(at: self.now, faces: counted)
            if self.presence.status == .away {
                if self.now - self.lastWatchLog >= 1 {
                    self.lastWatchLog = self.now
                    let biggest = faces.map(\.box.height).max() ?? 0
                    Log.presence.notice("Watching: \(faces.count) face(s), biggest \(biggest, format: .fixed(precision: 2)), \(counted) close enough; \(self.presence.trace, privacy: .public)")
                }
                // Decide on this picture rather than the next second's tick.
                self.tick()
            }
            var text = self.statusText
            if self.presence.status == .here || self.presence.status == .seenYou {
                text = "You're here. The camera turns off when you close this window"
            }
            self.check.update(faces: faces, image: image, minHeight: min, status: text)
        }
        check.onOpen = { [weak self] in self?.camera.showPictures(true); self?.tick() }
        check.onClose = { [weak self] in
            guard let self else { return }
            self.camera.showPictures(false)
            if !self.prefs.welcomed { self.prefs.welcomed = true }
            self.tick()
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.camera.stop() }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() }
        // Notice locks and unlocks straight away rather than on the next tick.
        let dn = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            dn.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.tick() }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.2
        tick()

        // A lock guard that's gone after a restart is worse than none: you think you're covered.
        if !prefs.loginDefaultSet {
            prefs.loginDefaultSet = true
            do { try SMAppService.mainApp.register() } catch {
                Log.presence.error("Couldn't turn on Open at login: \(error.localizedDescription, privacy: .public)")
            }
        }
        Log.presence.notice("Started \(AppInfo.version, privacy: .public), open at login: \(SMAppService.mainApp.status == .enabled)")

        if !prefs.welcomed && !launchedAtLogin { check.show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        check.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        camera.stop()
    }

    // MARK: - The loop

    private var paused: Bool {
        guard let until = pausedUntil else { return false }
        if until <= Date() { pausedUntil = nil; return false }
        return true
    }

    private func tick() {
        rollDay()
        let locked = MacScreen.isLocked
        let action = presence.tick(now: now, idle: MacScreen.idleSeconds, locked: locked,
                                   enabled: prefs.enabled, paused: paused, cameraProblem: camera.problem)
        if locked != loggedLocked {
            loggedLocked = locked
            Log.presence.notice("Screen \(locked ? "locked" : "unlocked", privacy: .public)")
        }
        if presence.status != loggedStatus {
            loggedStatus = presence.status
            Log.presence.notice("Status: \(self.statusText, privacy: .public)")
        }
        camera.lookRate(presence.status == .away ? 10 : 4)

        if presence.cameraWanted || check.isOpen {
            camera.start(prefs.camera)
            // A camera that stopped sending pictures gets a fresh start now and then.
            if case .problem = presence.status, camera.isOn, Date().timeIntervalSince(lastRestart) > 15 {
                lastRestart = Date()
                camera.stop()
            }
        } else {
            camera.stop()
        }
        if let p = camera.problem { check.showProblem(p) }

        switch action {
        case .lock:
            Log.presence.notice("Locking: no sign of you for \(Int(self.prefs.rules.leaveAfter))s")
            locksToday += 1
            MacScreen.lock()
            if prefs.displayOff {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MacScreen.displayOff() }
            }
        case .wake:
            Log.presence.notice("You're back: waking the screen")
            wakesToday += 1
            MacScreen.wake()
        case .none:
            break
        }
        updateIcon()
    }

    private func rollDay() {
        let d = Calendar.current.startOfDay(for: Date())
        if d != today { today = d; locksToday = 0; wakesToday = 0 }
    }

    private var lastIcon = ""
    private func updateIcon() {
        let icon: String
        switch presence.status {
        case .off, .paused: icon = "🙈"
        case .problem: icon = "👀⚠️"
        default: icon = "👀"
        }
        guard icon != lastIcon else { return }
        lastIcon = icon
        statusItem.button?.title = icon
        NexusBeacon.beat()
    }

    private var statusText: String {
        switch presence.status {
        case .off: return "Off. Your Mac won't lock by itself"
        case .paused:
            guard let until = pausedUntil, until != .distantFuture else { return "Paused" }
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        case .problem(let p): return "\(p). Won't lock until it's fixed"
        case .here: return "You're here. Camera off"
        case .checking: return "You're idle. Looking for you…"
        case .seenYou: return "You're here. Checking again soon"
        case .locking: return "Locked. You walked away"
        case .away: return "Locked. Will wake the screen when you're back"
        case .resting: return "Locked. Camera off"
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let head = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        let counts = NSMenuItem(title: "Today: locked \(times(locksToday)) · woke the screen \(times(wakesToday))", action: nil, keyEquivalent: "")
        counts.isEnabled = false
        menu.addItem(counts)
        menu.addItem(.separator())

        menu.addItem(toggle("Lock when I walk away", prefs.enabled, #selector(toggleEnabled)))
        if paused {
            menu.addItem(item("Resume", #selector(resume)))
        } else {
            let pause = NSMenu()
            for (title, minutes) in [("15 minutes", 15), ("1 hour", 60), ("Until tomorrow", -1), ("Until I resume", 0)] {
                let i = item(title, #selector(pause(_:)))
                i.tag = minutes
                pause.addItem(i)
            }
            menu.addItem(submenu("Pause", pause))
        }
        menu.addItem(.separator())

        menu.addItem(submenu("Start looking after idle", choices(
            [(3, "3 seconds"), (5, "5 seconds"), (10, "10 seconds"), (15, "15 seconds"), (30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes")],
            prefs.idleBeforeCheck, #selector(pickIdle(_:)))))
        menu.addItem(submenu("Lock after you've gone for", choices(
            [(5, "5 seconds"), (10, "10 seconds"), (20, "20 seconds"), (30, "30 seconds"), (60, "1 minute")],
            prefs.leaveAfter, #selector(pickLeave(_:)))))
        menu.addItem(submenu("Camera while you're idle", choices(
            [(5, "Peek every 5 seconds"), (10, "Peek every 10 seconds"), (30, "Peek every 30 seconds"), (0, "Keep it on")],
            prefs.recheckEvery, #selector(pickRecheck(_:)))))
        let dist = NSMenu()
        for d in Distance.allCases {
            let i = item(d.title, #selector(pickDistance(_:)))
            i.representedObject = d.rawValue
            i.state = prefs.distance == d ? .on : .off
            dist.addItem(i)
        }
        menu.addItem(submenu("Faces that count", dist))
        menu.addItem(toggle("Turn the display off after locking", prefs.displayOff, #selector(toggleDisplayOff)))
        menu.addItem(toggle("Wake the screen when I'm back", prefs.wakeOnReturn, #selector(toggleWake)))
        let watch = choices([(10, "10 minutes"), (30, "30 minutes"), (60, "1 hour"), (120, "2 hours"), (480, "8 hours")],
                            Double(prefs.returnWatchMinutes), #selector(pickWatch(_:)))
        let watchItem = submenu("Watch for me after locking", watch)
        watchItem.isEnabled = prefs.wakeOnReturn
        menu.addItem(watchItem)

        let cams = NSMenu()
        let chosen = Camera.device(for: prefs.camera)?.uniqueID
        for d in Camera.all() {
            let phone = d.isContinuityCamera || d.deviceType == .continuityCamera
            let i = item(d.localizedName + (phone ? " (takes over the phone)" : ""), #selector(pickCamera(_:)))
            i.representedObject = d.uniqueID
            i.state = d.uniqueID == chosen ? .on : .off
            cams.addItem(i)
        }
        if cams.items.isEmpty {
            let none = NSMenuItem(title: "No camera found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            cams.addItem(none)
        }
        menu.addItem(submenu("Camera", cams))
        menu.addItem(.separator())

        menu.addItem(item("Camera check…", #selector(openCheck)))
        menu.addItem(item("Lock now", #selector(lockNow)))
        if AVAuthorization.denied {
            menu.addItem(item("Turn on camera access…", #selector(openCameraPrivacy)))
        }
        menu.addItem(.separator())

        let look = NSMenu()
        for (id, title) in [("system", "System"), ("light", "Light"), ("dark", "Dark")] {
            let i = item(title, #selector(pickAppearance(_:)))
            i.representedObject = id
            i.state = prefs.appearance == id ? .on : .off
            look.addItem(i)
        }
        menu.addItem(submenu("Appearance", look))
        menu.addItem(toggle("Open at login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(item("About \(AppInfo.name) \(AppInfo.version)", #selector(openAbout)))
        let quit = item("Quit", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func times(_ n: Int) -> String { n == 1 ? "once" : "\(n) times" }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let i = item(title, action)
        i.state = on ? .on : .off
        return i
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = sub
        return i
    }

    private func choices(_ options: [(Int, String)], _ current: Double, _ action: Selector) -> NSMenu {
        let m = NSMenu()
        for (value, title) in options {
            let i = item(title, action)
            i.tag = value
            i.state = Int(current) == value ? .on : .off
            m.addItem(i)
        }
        return m
    }

    @objc private func toggleEnabled() { prefs.enabled.toggle() }
    @objc private func pause(_ i: NSMenuItem) {
        switch i.tag {
        case 0: pausedUntil = .distantFuture
        case -1:
            // "Until tomorrow" = 6 AM tomorrow.
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            pausedUntil = Calendar.current.date(byAdding: .hour, value: 6, to: tomorrow)
        default: pausedUntil = Date().addingTimeInterval(Double(i.tag) * 60)
        }
        tick()
    }
    @objc private func resume() { pausedUntil = nil; tick() }
    @objc private func pickIdle(_ i: NSMenuItem) { prefs.idleBeforeCheck = Double(i.tag) }
    @objc private func pickLeave(_ i: NSMenuItem) { prefs.leaveAfter = Double(i.tag) }
    @objc private func pickRecheck(_ i: NSMenuItem) { prefs.recheckEvery = Double(i.tag) }
    @objc private func pickWatch(_ i: NSMenuItem) { prefs.returnWatchMinutes = i.tag }
    @objc private func pickDistance(_ i: NSMenuItem) { if let d = Distance(rawValue: i.representedObject as? String ?? "") { prefs.distance = d } }
    @objc private func toggleDisplayOff() { prefs.displayOff.toggle() }
    @objc private func toggleWake() { prefs.wakeOnReturn.toggle() }
    @objc private func pickCamera(_ i: NSMenuItem) {
        let id = i.representedObject as? String ?? ""
        // Store "" for the built-in camera, so a new Mac or a closed lid still finds the right one.
        prefs.camera = Camera.all().first { $0.uniqueID == id }?.deviceType == .builtInWideAngleCamera ? "" : id
    }
    @objc private func openCheck() { check.show() }
    @objc private func lockNow() {
        Log.presence.notice("Locking: Lock now")
        locksToday += 1
        MacScreen.lock()
    }
    @objc private func openCameraPrivacy() { MacScreen.openCameraPrivacy() }
    @objc private func pickAppearance(_ i: NSMenuItem) { prefs.appearance = i.representedObject as? String ?? "system" }
    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do { svc.status == .enabled ? try svc.unregister() : try svc.register() } catch {}
    }
    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(string: "Locks your Mac when you walk away and wakes the screen when you're back.\n\(AppInfo.repo.absoluteString)",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

enum AVAuthorization {
    static var denied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .video)
        return s == .denied || s == .restricted
    }
}
