// Settings, saved in UserDefaults (com.stangudu.walkoff). The menu edits them; the engine reads them.
import AppKit

/// How close a face must be to count, as a share of the picture's height.
enum Distance: String, CaseIterable {
    case close, room, any
    var title: String {
        switch self {
        case .close: return "Close (about 1.5 m)"
        case .room: return "Same room (about 3 m)"
        case .any: return "Anywhere in view"
        }
    }
    var minHeight: CGFloat {
        switch self {
        case .close: return 0.15
        case .room: return 0.07
        case .any: return 0
        }
    }
}

final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard
    var onChange: (() -> Void)?

    var enabled: Bool { didSet { save(enabled, "enabled") } }
    var idleBeforeCheck: Double { didSet { save(idleBeforeCheck, "idleBeforeCheck") } }
    var leaveAfter: Double { didSet { save(leaveAfter, "leaveAfter") } }
    var recheckEvery: Double { didSet { save(recheckEvery, "recheckEvery") } }
    var distance: Distance { didSet { save(distance.rawValue, "distance") } }
    var displayOff: Bool { didSet { save(displayOff, "displayOff") } }
    var wakeOnReturn: Bool { didSet { save(wakeOnReturn, "wakeOnReturn") } }
    var returnWatchMinutes: Int { didSet { save(returnWatchMinutes, "returnWatchMinutes") } }
    /// AVCaptureDevice.uniqueID, or "" for the built-in camera.
    var camera: String { didSet { save(camera, "camera") } }
    var welcomed: Bool { didSet { save(welcomed, "welcomed") } }
    /// Open at login is switched on once, on first run. After that the menu's choice stands.
    var loginDefaultSet: Bool { didSet { save(loginDefaultSet, "loginDefaultSet") } }
    /// system | light | dark. Missing means system, like every other app in the fleet.
    var appearance: String { didSet { save(appearance, "appearance"); applyAppearance() } }

    private init() {
        let d = UserDefaults.standard
        func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        func num(_ k: String, _ def: Double) -> Double { d.object(forKey: k) == nil ? def : d.double(forKey: k) }
        enabled = bool("enabled", true)
        idleBeforeCheck = num("idleBeforeCheck", 3)
        leaveAfter = num("leaveAfter", 5)
        recheckEvery = num("recheckEvery", 5)
        distance = Distance(rawValue: d.string(forKey: "distance") ?? "") ?? .close
        displayOff = bool("displayOff", true)
        wakeOnReturn = bool("wakeOnReturn", true)
        returnWatchMinutes = d.object(forKey: "returnWatchMinutes") == nil ? 30 : d.integer(forKey: "returnWatchMinutes")
        camera = d.string(forKey: "camera") ?? ""
        welcomed = bool("welcomed", false)
        loginDefaultSet = bool("loginDefaultSet", false)
        appearance = d.string(forKey: "appearance") ?? "system"
    }

    private func save(_ v: Any, _ k: String) {
        d.set(v, forKey: k)
        onChange?()
    }

    var rules: Rules {
        Rules(idleBeforeCheck: idleBeforeCheck, leaveAfter: leaveAfter, recheckEvery: recheckEvery,
              wakeOnReturn: wakeOnReturn, returnWatchFor: Double(returnWatchMinutes) * 60)
    }

    func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
