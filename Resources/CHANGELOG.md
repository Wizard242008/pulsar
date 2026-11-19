## 2.1.4

- A hidden window no longer holds a pane. Apps that hide themselves — Cmd-H, or a menu-bar
  utility that keeps its window alive instead of closing it — stay tracked with their workspace
  intact, but the layout ignores them while they are invisible, so the window beside them expands
  to the full width and contracts again when they come back.

## 2.1.3

- Closing a menu-bar app's window no longer leaves the other window stuck at part width. Tailscale
  (and anything else that shows a window and then orders it out instead of destroying it) is covered:
  a window we already track keeps being swept even after its app drops back to accessory policy, so
  the pane it was holding is released and the neighbour expands to the full width.
- Directional focus follows the screen, not the window list, and the update installer waits for the
  old process to exit before swapping the bundle.

# Changelog

Newest first. The app reads the section matching its own version to fill the "What's new" sheet, so
keep the heading format exactly `## <version>` and the bullets starting with `- `.

## 2.1.2

- Directional focus and move follow the panes on screen. In a grid, `h j k l` now go to the pane
  actually to the left, right, above or below, instead of stepping through the list one index at a time.
- Directional move swaps the two panes' places, so the window moves where you pointed.
- Updates install reliably: the new build waits for the old one to quit before it is started, so the
  update no longer ends with no running Pulsar.
- A failed update no longer leaves the disk image mounted.
- Closing the Welcome window stops its permission check, so an idle Pulsar no longer wakes once a second.
- The saved window history is trimmed as intended instead of growing without limit.

## 2.1.1

- An app that refuses to grow — System Settings stops at 757 pt however wide it is asked to be — no
  longer leaves an empty strip at the right edge. The other panes take the space it will not use.
- Minimum sizes are only believed after two agreeing sightings, and are corrected downwards when a
  window is later seen smaller. One bad reading had inflated a window's minimum to 1655 pt, which
  over-subscribed the screen and produced the same gap from the other direction.

## 2.1.0

- Guided first run: a four-step tour covers what Pulsar does, the one permission it needs, and the keys.
- The permission step opens Privacy & Security → Accessibility directly, and turns green the moment the switch is on.
- Pulsar can relaunch itself after a permission is granted — macOS only applies a new grant to processes started afterwards.
- "What's new" after an update, with a switch in Settings to turn it off.
- Settings rebuilt: scrollable, wider, and grouped into Behaviour, Keys, Permissions and General.
- Getting Started… in the menu reopens the tour at any time.

## 2.0.10

- Fixed the lock screen collapsing every window onto one desktop.
- Panes divide evenly when minimum sizes cannot all fit, instead of running off the bottom of the screen.
- Unseen windows get a 44 pt minimum, so nothing can be squashed to a sliver.

## 2.0.9

- A window that returns from full screen keeps its workspace.
- Adopted windows inherit their predecessor's workspace after a Space transition.

## 2.0.6

- Survives Accessibility outages — a phone call or a full-screen animation no longer looks like every window closing.
- Quitting gives every window back at full size.
