// Walk Off writes what it decides to the Mac's log, so "why didn't it lock / wake?" has an answer:
//   log show --last 1h --style compact --predicate 'subsystem == "com.stangudu.walkoff"'
// Only decisions and face counts go in. Never pictures.
import os

enum Log {
    static let presence = Logger(subsystem: "com.stangudu.walkoff", category: "presence")
    static let camera = Logger(subsystem: "com.stangudu.walkoff", category: "camera")
}
