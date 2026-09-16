# Web Signing in the Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A web signing request launches Autogram macOS without a main window or Dock icon and shows the signing panel centered over Safari.

**Architecture:** The launchd agent passes `--web-signing`; the app parses it (`AppLaunchMode`), runs as an accessory app with the main `WindowGroup` suppressed, and becomes a regular app on reopen. The panel origin comes from a pure placement function fed by Safari's front window bounds.

**Tech Stack:** Swift 6, SwiftUI (`defaultLaunchBehavior`), AppKit (`NSApplication.ActivationPolicy`, `NSPanel`), CoreGraphics window list, XCTest.

**Spec:** `Autogram/docs/superpowers/specs/2026-09-16-web-signing-background-design.md`

## Global Constraints

- Build and test with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, from `Autogram/`.
- English for code and comments, Slovak for user-facing strings, no em dashes anywhere.
- Keep `CLAUDE.md` and `AGENTS.md` identical.
- A normal launch (no `--web-signing`) must behave exactly as today.

---

### Task 1: Launch mode argument

**Files:**
- Create: `Autogram/Sources/AutogramApp/AppLaunchMode.swift`
- Modify: `Autogram/Sources/autogram-webbridge-agent/main.swift` (`launchApp()`)
- Test: `Autogram/Tests/AutogramAppTests/AppLaunchModeTests.swift`

**Interfaces:**
- Produces: `enum AppLaunchMode { case normal, webSigning; static let argument = "--web-signing"; static func from(arguments: [String]) -> AppLaunchMode; static let current: AppLaunchMode }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AutogramApp

final class AppLaunchModeTests: XCTestCase {
    func testWebSigningArgumentSelectsBackgroundMode() {
        XCTAssertEqual(AppLaunchMode.from(arguments: ["/Applications/Autogram macOS.app/Contents/MacOS/Autogram", "--web-signing"]), .webSigning)
    }

    func testOrdinaryLaunchIsNormal() {
        XCTAssertEqual(AppLaunchMode.from(arguments: ["/Applications/Autogram macOS.app/Contents/MacOS/Autogram"]), .normal)
        XCTAssertEqual(AppLaunchMode.from(arguments: ["Autogram", "-NSDocumentRevisionsDebugMode", "YES"]), .normal)
    }
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `swift test --filter AppLaunchModeTests`. Expected: compile error, `AppLaunchMode` not found.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// How this process was started. The web bridge agent passes `--web-signing` when a
/// portal request finds Autogram not running; that launch shows only the signing panel.
enum AppLaunchMode: Equatable {
    case normal
    case webSigning

    static let argument = "--web-signing"

    static func from(arguments: [String]) -> AppLaunchMode {
        arguments.dropFirst().contains(argument) ? .webSigning : .normal
    }

    static let current = from(arguments: CommandLine.arguments)
}
```

In the agent's `launchApp()` add, next to `configuration.activates = false`:

```swift
            // Tells the app it was started for a portal request, so it shows only
            // the signing panel: no main window, no Dock icon.
            configuration.arguments = ["--web-signing"]
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `swift test --filter AppLaunchModeTests`. Expected: 2 tests pass.

- [ ] **Step 5: Commit**

`git commit -m "feat(web): start Autogram in web-signing mode from the bridge agent"`

---

### Task 2: Accessory app with suppressed main window

**Files:**
- Modify: `Autogram/Sources/AutogramApp/AutogramApp.swift` (`WindowGroup`, `AppDelegate`, `OpenSettingsButton`)

**Interfaces:**
- Consumes: `AppLaunchMode.current`
- Produces: `AppDelegate.becomeRegularApp()` (static, `@MainActor`), used by `OpenSettingsButton`.

- [ ] **Step 1: Suppress the main window in web-signing mode**

On the main `WindowGroup` chain, after `.defaultSize(width: 1320, height: 860)`:

```swift
        .defaultLaunchBehavior(AppLaunchMode.current == .webSigning ? .suppressed : .automatic)
```

- [ ] **Step 2: Accessory policy and reopen in `AppDelegate`**

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // A portal request started the app: no Dock icon and no menu bar until the
        // person opens Autogram themselves.
        if AppLaunchMode.current == .webSigning {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FinderQuickActionService.installQuickAction()
        WebBridgeListener.shared.start()
    }

    /// Dock, Finder or Spotlight while the app already runs: become a regular app,
    /// and let SwiftUI open the main window when none is visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.becomeRegularApp()
        return true
    }

    @MainActor
    static func becomeRegularApp() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
```

- [ ] **Step 3: Settings also turns the app regular**

In `OpenSettingsButton`'s action, before `openWindow(id: SettingsWindow.id)`, call `AppDelegate.becomeRegularApp()`.

- [ ] **Step 4: Build and check a normal launch**

Run: `./build_app.sh --release install`, then `open "/Applications/Autogram macOS.app"`. Expected: main window and Dock icon as before.

- [ ] **Step 5: Check a web launch**

Quit Autogram, run `open -n "/Applications/Autogram macOS.app" --args --web-signing`. Expected: no Dock icon, no window; `pgrep -fl "Autogram macOS.app/Contents/MacOS/Autogram"` lists the process. Then `open "/Applications/Autogram macOS.app"`: Dock icon and main window appear.

- [ ] **Step 6: Commit**

`git commit -m "feat(web): run as an accessory app after a web-signing launch"`

---

### Task 3: Panel placement over Safari

**Files:**
- Create: `Autogram/Sources/AutogramApp/WebSigningPanelPlacement.swift`
- Test: `Autogram/Tests/AutogramAppTests/WebSigningPanelPlacementTests.swift`

**Interfaces:**
- Produces: `enum WebSigningPanelPlacement { struct Screen { let frame: CGRect; let visibleFrame: CGRect }; static func origin(panelSize: CGSize, safariQuartzBounds: CGRect?, screens: [Screen], mouseLocation: CGPoint) -> CGPoint }`. `screens[0]` is the primary screen (Cocoa origin at 0,0). `mouseLocation` is in Cocoa coordinates.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AutogramApp

final class WebSigningPanelPlacementTests: XCTestCase {
    private let primary = WebSigningPanelPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
    private let panel = CGSize(width: 540, height: 600)

    func testCentersOverSafariOnThePrimaryScreen() {
        // Quartz: top-left origin. Window 1200x800 at (360, 140) → Cocoa y = 1080 - 940 = 140.
        let origin = WebSigningPanelPlacement.origin(panelSize: panel,
            safariQuartzBounds: CGRect(x: 360, y: 140, width: 1200, height: 800),
            screens: [primary], mouseLocation: .zero)
        XCTAssertEqual(origin, CGPoint(x: 360 + 600 - 270, y: 140 + 400 - 300))
    }

    func testCentersOverSafariOnASecondScreenAbove() {
        let above = WebSigningPanelPlacement.Screen(
            frame: CGRect(x: 0, y: 1080, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 1080, width: 2560, height: 1415))
        // Quartz y of the upper screen's top is -1440; window 1000x900 at (780, -1170).
        let origin = WebSigningPanelPlacement.origin(panelSize: panel,
            safariQuartzBounds: CGRect(x: 780, y: -1170, width: 1000, height: 900),
            screens: [primary, above], mouseLocation: .zero)
        // Cocoa window minY = 1080 - (-1170 + 900) = 1350; center y = 1800.
        XCTAssertEqual(origin, CGPoint(x: 780 + 500 - 270, y: 1800 - 300))
    }

    func testClampsInsideTheVisibleFrame() {
        let origin = WebSigningPanelPlacement.origin(panelSize: panel,
            safariQuartzBounds: CGRect(x: 1700, y: 900, width: 400, height: 300),
            screens: [primary], mouseLocation: .zero)
        XCTAssertEqual(origin.x, 1920 - 540)
        XCTAssertEqual(origin.y, 0)
    }

    func testWithoutSafariCentersOnTheScreenUnderTheMouse() {
        let right = WebSigningPanelPlacement.Screen(
            frame: CGRect(x: 1920, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1440, height: 875))
        let origin = WebSigningPanelPlacement.origin(panelSize: panel, safariQuartzBounds: nil,
            screens: [primary, right], mouseLocation: CGPoint(x: 2500, y: 400))
        XCTAssertEqual(origin, CGPoint(x: 1920 + 720 - 270, y: 437.5 - 300))
    }
}
```

- [ ] **Step 2: Run and see them fail**

Run: `swift test --filter WebSigningPanelPlacementTests`. Expected: compile error, type not found.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics

/// Where the web signing panel goes: centered over Safari's front window, or on the
/// screen under the mouse when no Safari window is found. Pure, so it is tested
/// with plain rectangles instead of real windows.
enum WebSigningPanelPlacement {
    struct Screen: Equatable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// - Parameters:
    ///   - safariQuartzBounds: window bounds as `CGWindowListCopyWindowInfo` reports
    ///     them, top-left origin on the primary screen.
    ///   - screens: `screens[0]` is the primary screen.
    ///   - mouseLocation: Cocoa coordinates.
    static func origin(panelSize: CGSize, safariQuartzBounds: CGRect?, screens: [Screen],
                       mouseLocation: CGPoint) -> CGPoint {
        guard let primary = screens.first else { return .zero }
        if let quartz = safariQuartzBounds {
            let window = CGRect(x: quartz.minX, y: primary.frame.height - quartz.maxY,
                                width: quartz.width, height: quartz.height)
            let center = CGPoint(x: window.midX, y: window.midY)
            let screen = screens.first { $0.frame.contains(center) } ?? primary
            return clamped(CGPoint(x: center.x - panelSize.width / 2, y: center.y - panelSize.height / 2),
                           panelSize: panelSize, in: screen.visibleFrame)
        }
        let screen = screens.first { $0.frame.contains(mouseLocation) } ?? primary
        let area = screen.visibleFrame
        return clamped(CGPoint(x: area.midX - panelSize.width / 2, y: area.midY - panelSize.height / 2),
                       panelSize: panelSize, in: area)
    }

    private static func clamped(_ origin: CGPoint, panelSize: CGSize, in area: CGRect) -> CGPoint {
        CGPoint(x: min(max(origin.x, area.minX), max(area.minX, area.maxX - panelSize.width)),
                y: min(max(origin.y, area.minY), max(area.minY, area.maxY - panelSize.height)))
    }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `swift test --filter WebSigningPanelPlacementTests`. Expected: 4 tests pass.

- [ ] **Step 5: Commit**

`git commit -m "feat(web): compute the signing panel position over Safari"`

---

### Task 4: Use the placement, drop the Dock bounce, document

**Files:**
- Modify: `Autogram/Sources/AutogramApp/WebSigningPrompt.swift` (`show(coordinator:)`)
- Modify: `CLAUDE.md`, `AGENTS.md` (Browser signing bullet)

**Interfaces:**
- Consumes: `WebSigningPanelPlacement.origin(...)`, `WebSigningPanelPlacement.Screen`

- [ ] **Step 1: Safari window lookup and placement in `WebSigningPrompt`**

```swift
    /// Front on-screen Safari window, in Quartz coordinates. Window bounds need no
    /// Screen Recording permission, only titles would.
    private static func safariFrontWindowBounds() -> CGRect? {
        let safariPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari")
            .map(\.processIdentifier))
        guard !safariPIDs.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, safariPIDs.contains(pid),
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width > 200, bounds.height > 200 else { continue }
            return bounds
        }
        return nil
    }

    private func place(_ panel: NSPanel) {
        let screens = NSScreen.screens.map {
            WebSigningPanelPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let origin = WebSigningPanelPlacement.origin(panelSize: panel.frame.size,
                                                     safariQuartzBounds: Self.safariFrontWindowBounds(),
                                                     screens: screens,
                                                     mouseLocation: NSEvent.mouseLocation)
        panel.setFrameOrigin(origin)
    }
```

In `show(coordinator:)`: replace `panel.center()` with `place(panel)`; in the early-return branch (`if let panel`) call `place(panel)` before `orderFrontRegardless()`; delete `NSApp.requestUserAttention(.criticalRequest)` and its comment. Update the type's doc comment: the panel is placed over Safari and no longer asks for attention.

- [ ] **Step 2: Build, install, full tests**

Run: `swift test --skip SecurityElementsDetectorTests` (0 failures), then `./build_app.sh --release install`.

- [ ] **Step 3: Documentation**

In both `CLAUDE.md` and `AGENTS.md`, in the Browser signing bullet, replace `The agent starts the app on demand.` with `The agent starts the app on demand with \`--web-signing\` (\`AppLaunchMode\`): an accessory app with the main window suppressed, which turns regular on reopen or Settings.` and replace `Every request raises a floating panel (\`WebSigningPrompt\`)` with `Every request raises a floating panel (\`WebSigningPrompt\`) centered over Safari's front window (\`WebSigningPanelPlacement\`), without a Dock bounce,`. Check `diff CLAUDE.md AGENTS.md` prints nothing.

- [ ] **Step 4: Commit**

`git commit -m "feat(web): open the signing panel over Safari without a Dock bounce"`

- [ ] **Step 5: Manual verification (person)**

1. Quit Autogram. Sign on nove.slovensko.sk: no Dock icon, no main window, panel centered over Safari.
2. With Autogram open normally: the main window is not raised, the panel appears over Safari.
3. After step 1, open Autogram from Finder: Dock icon and main window appear.
