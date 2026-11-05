# Security policy

## Reporting a problem

Please report security problems privately through GitHub:
**Security → Report a vulnerability** on this repository. Don't open a public issue for them.

Include what you found, how to reproduce it, and the Walk Off version (👀 menu → About).
You'll get a reply within a week.

## Supported versions

Only the latest release gets fixes. Update from the
[latest release](https://github.com/Sravankumartangudu/walk-off/releases/latest).

## What Walk Off can do to your Mac

- **Lock it**, using the same system call as the  menu's Lock Screen.
- **Turn the display off** (`pmset displaysleepnow`).
- **Wake the display** (an IOKit "user is active" signal, like touching a key). The Mac stays locked.

It **cannot unlock** the Mac and has no code that tries to. It doesn't install login plugins, change
the authorization database, store your password, or need admin rights.

## What Walk Off handles

- **Camera:** on only after you've stopped typing for a while, while the Mac is locked (up to the
  "Watch for me" time), and while the Camera check window is open. Pictures (640×480) go through
  Apple's on-device Vision face finder about 4 times a second and are dropped straight away. Only
  face *positions* are used. Nothing is recognised, saved or sent.
- **Idle time:** the seconds since your last key press or mouse move, read from macOS. Walk Off
  never sees *which* keys you press.
- **No network.** No accounts, analytics, ads or update checks. The only link is in About, which
  opens your browser.
- **Stored on your Mac:** settings in the app's preferences (`com.stangudu.walkoff`).
- **Status files:** small local files in `~/.nexus/` (a heartbeat with the name, version and status
  line, and a copy of the 👀 menu) for Nexus, the author's local app monitor. They hold no pictures.

## Limits

Walk Off checks that *a* face is there, not *whose* face. Anyone sitting in front of your Mac keeps
it from locking, the same as if you'd left it unlocked. It's a convenience that locks the Mac when
you forget, not a barrier. Your password, Touch ID or Apple Watch still guards the lock screen.
