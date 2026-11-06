# Changelog

## 1.0.2 (2026-11-06)

- Locks 5 seconds after you walk away (was about 25). The countdown now starts at your last key press,
  mouse move or face, not when the camera turns on. The camera turns on after 3 s quiet (was 15) and
  rests 5 s after seeing you (was 10). It still needs 2 s of seeing nobody before it locks.
- Opens at login by default, so a restart or log out doesn't quietly leave the Mac unguarded. Switch it
  off in the menu and it stays off.
- Logs the version and the Open at login state when it starts.

## 1.0.1 (2026-11-05)

- Wakes the screen faster when you're back: while the Mac is locked it looks 10 times a second (was 4)
  and wakes on the picture that sees you, not on the next second. That gives your Apple Watch time to
  unlock before you reach for Touch ID.
- Someone walking past a locked screen holds the next wake back for 20 s (was 60 s).
- Writes its decisions to the Mac's log (lock, unlock, faces seen while locked, wake), so a missed lock
  or wake can be explained. No pictures are logged.
- Stops asking macOS about camera permission every second while the camera is already running.

## 1.0.0 (2026-11-05)

First release.

- 👀 menu-bar app that locks the Mac when your face has gone, and wakes the screen when you're back so
  Touch ID or your Apple Watch can unlock it.
- Camera only after you've been idle (15 s by default), then peeks every 10 s while you stay. Or keep it on.
- Faces that count: close, same room, or anywhere in view.
- Turns the display off after locking; watches for you for up to 30 minutes (10 min–8 h).
- Never locks if the camera fails, stops sending pictures, or the lid is closed (👀⚠️ says why).
- Camera check window with a live, mirrored preview and face boxes.
- Pause (15 min, 1 h, until tomorrow, until resumed), Lock now, camera picker (iPhone never picked
  by default), System/Light/Dark appearance, Open at login.
- Presence engine tests run on every build.
