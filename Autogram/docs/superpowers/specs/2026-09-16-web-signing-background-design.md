# Web signing in the background

Date: 2026-09-16. Status: approved.

## Problem

A signing request from a state portal starts Autogram macOS through the
`autogram-webbridge-agent`. The app then behaves like a normal launch: its main
window opens, its Dock icon appears and bounces (`requestUserAttention`), and the
signing panel sits wherever `NSPanel.center()` put it, often beside the portal's
own "Čakajte, prosím" modal instead of over it. The person expects Safari to stay
in front with one signing window over the page.

## Goals

1. A launch caused by a web request shows only the signing panel: no main window,
   no Dock icon, no bounce, no focus taken from Safari.
2. Opening Autogram afterwards from the Dock, Finder or Spotlight turns it into a
   regular app with its main window.
3. The signing panel is centered over Safari's front window.

Out of scope: rendering the prompt inside the web page or a Safari popover (both
rejected), quitting after idle time, the separate `autogram://` URL scheme clash.

## Design

### Launch mode

- The agent opens the app with `NSWorkspace.OpenConfiguration.arguments =
  ["--web-signing"]` (still `activates = false`).
- `AppLaunchMode` in AutogramApp parses the process arguments once. It is a pure
  function of the argument list so it can be tested.
- In web-signing mode `AppDelegate.applicationWillFinishLaunching` sets
  `NSApp.setActivationPolicy(.accessory)`, and the main `WindowGroup` uses
  `.defaultLaunchBehavior(.suppressed)` so no main window opens.
- `applicationShouldHandleReopen` (Dock, Finder or Spotlight while the app runs)
  switches the policy to `.regular`, activates the app and lets SwiftUI open the
  main window when none is visible. The same switch applies when the person opens
  Settings.
- A normal launch is unchanged.

### Panel placement

- `WebSigningPanelPlacement` computes the panel origin from plain values: the
  front Safari window's bounds (from `CGWindowListCopyWindowInfo`, owner
  `com.apple.Safari`, layer 0, on screen; bounds only, which needs no Screen
  Recording permission), the screens' frames, and the panel size.
- Quartz window bounds use a top-left origin on the primary screen; they are
  converted to Cocoa coordinates before centering, and the result is clamped to
  the visible frame of the screen containing the Safari window.
- Without a Safari window the panel is centered on the screen under the mouse.
- `WebSigningPrompt.show` uses the placement for every new request and no longer
  calls `requestUserAttention`. The panel keeps `.floating` level and
  `orderFrontRegardless`, so it appears over Safari without activating the app.

### Keyboard

Unchanged: macOS does not let a background app take the keyboard, so the panel
gets it when clicked. The eID certificate read still waits for that click.

### After signing

The app keeps running in accessory mode, so the next request is fast and the
listener stays registered with the agent.

## Testing

- Unit tests: `AppLaunchMode` argument parsing; `WebSigningPanelPlacement` for a
  Safari window on the primary screen, on a secondary screen above or beside it,
  a window partly off screen (clamped), and no Safari window (mouse screen).
- Manual: request from nove.slovensko.sk with Autogram not running (no Dock icon,
  no main window, panel over Safari); with Autogram running normally (main window
  not raised); after a web launch, click the Autogram app in Finder (Dock icon and
  main window appear).
