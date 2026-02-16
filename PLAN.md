## Autogram macOS Frontend Redesign Plan  
**Variant:** System-first polish + Soft glass hybrid + Phased rollout

### Summary
Cieľ je prerobiť UI tak, aby pôsobilo natívne pre macOS, bolo čitateľné v dark mode, konzistentné naprieč panelmi/modálmi a rýchle v reálnom signing workflow bez zbytočných klikov.  
Implementácia zostane v existujúcej JavaFX architektúre (single window + inline overlays), ale zjednotí sa dizajn systém, layout pravidlá, fokus/keyboard behavior a testovací runbook.

### Current Frontend Architecture (as-is)
- App bootstrap: `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/java/digital/slovensko/autogram/ui/gui/GUIApp.java`
- Main shell + overlays + panel switching: `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/java/digital/slovensko/autogram/ui/gui/MainMenuController.java`
- Signing workflow screen: `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/signing-dialog.fxml` + `SigningDialogController`
- Settings workflow: `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/settings-dialog.fxml` + `SettingsDialogController`
- Theme system: `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/macos-native.css` + `macos-native-dark.css`
- Overlay dialogs: inline host in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/main-menu.fxml`

### Priority Findings to Fix Before Visual Polish
1. Duplicate `fx:id` bug in signing view: `fx:id="signaturesTable"` is duplicated in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/signing-dialog.fxml`.  
2. Undefined color token: `-autogram-accent` used but not defined in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/macos-native.css`.  
3. Overlay sizing conflict: static `maxWidth/maxHeight` in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/main-menu.fxml` fights content-driven dialog sizing.  
4. Dark-mode text leakage: dynamic `Text`/`Label` content in signature table and options can render low-contrast/black in signing area.  
5. Settings tab icon fallback to square: current Region-shape approach is fragile in CSS parsing/fallback states.

### Implementation Plan (Decision Complete)

### Phase 1: Foundation and Safety (UI Stability Baseline)
1. Remove duplicate `signaturesTable` node in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/signing-dialog.fxml`.
2. Normalize overlay container sizing:
- Remove hard `maxWidth/maxHeight` from `dialogContainer` in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/main-menu.fxml`.
- Keep content-sized dialogs by default and enforce min/max per dialog class only.
3. Keep existing focus logic in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/java/digital/slovensko/autogram/ui/gui/PasswordController.java` and `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/java/digital/slovensko/autogram/ui/gui/MainMenuController.java`, then unify into one overlay focus utility method.

### Phase 2: Design System v2 (Native macOS + Soft Glass)
1. In `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/macos-native.css`:
- Define full token set for foreground/background/surface/border/focus states.
- Add missing token definitions (`-autogram-accent` removed or replaced by `-autogram-focus-colour`).
- Introduce fixed semantic tokens: `--surface-0/1/2`, `--text-primary/secondary/muted`, `--interactive-normal/hover/active/disabled`.
2. In `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/macos-native-dark.css`:
- Explicit dark overrides for all controls used in app: `ChoiceBox`, popup menu rows, `CheckBox`, `RadioButton`, table text, labels inside options/signature sections.
- Guarantee WCAG-level readability for body and helper text.
3. Replace fragile settings tab icon `Region` shapes with explicit `SVGPath` icons in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/settings-dialog.fxml`.

### Phase 3: Settings Panel Redesign (Compact, Aligned, Native)
1. Keep four tabs, but redesign layout rules:
- Consistent row height and spacing system (8/12/16 rhythm).
- Fixed label column and responsive control column widths.
- Uniform field widths per row type.
2. Refactor settings row styling in CSS so every row has:
- Proper text contrast in dark mode.
- Clear hover/focus/disabled states.
- Reduced vertical waste.
3. Validation tab and country list:
- Improve density and scanability.
- Keep toggle status readable and keyboard navigable.
4. Footer actions in settings:
- Align Reset left, Save right, with persistent sticky footer behavior.

### Phase 4: Signing Screen Readability and Workflow
1. Ensure all signature summary text nodes get explicit style classes at source creation in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/java/digital/slovensko/autogram/ui/gui/GUIValidationUtils.java`.
2. Update signing options area (`Formát`, `Časová pečiatka`, CTA) in `/Users/Magneto/CascadeProjects/autogram-macOS/src/main/resources/digital/slovensko/autogram/ui/gui/signing-dialog.fxml`:
- Strong contrast labels.
- Balanced spacing.
- Compact CTA row.
3. Keep PDF preview dominant while preserving metadata readability.

### Phase 5: Modal System Redesign (Size + Focus + Keyboard)
1. Introduce dialog size variants as internal contract:
- `compact` (PIN, cert pick),
- `default` (warnings/errors),
- `wide` (detailed warning tables).
2. Apply variants via style classes only; no hardcoded fixed container sizes.
3. Enforce keyboard-first behavior:
- Initial focus always in first actionable input.
- `Enter` submits primary action.
- `Esc` cancels (where safe).
- Focus trap stays inside modal until close.
4. Reduce certificate picker and PIN dialog size to content-fit minima with strict max width.

### Phase 6: Run/Verify Workflow (Always Reproducible on macOS)
1. Keep script-first QA entrypoint:
- `/Users/Magneto/CascadeProjects/autogram-macOS/scripts/macos-update-check.sh`
2. Add a dedicated UI smoke script (`scripts/macos-ui-smoke.sh`) that runs:
- compile,
- targeted tests,
- launches app with dark mode note + checklist.
3. Document exact manual verification protocol in `/Users/Magneto/CascadeProjects/autogram-macOS/DEVELOPER.md`:
- dark mode checks,
- modal focus checks,
- settings dropdown visibility checks,
- signing panel contrast checks.

## Important Changes to Public APIs / Interfaces / Types
1. **Internal UI contract change** in `MainMenuController`:
- from `showOverlayDialog(Parent content)`
- to `showOverlayDialog(Parent content, OverlaySpec spec)`  
where `OverlaySpec` includes size preset, autofocus selector, and dismiss behavior.
2. **New internal enum/type** (GUI package):
- `OverlaySizePreset { COMPACT, DEFAULT, WIDE }`
3. **No external server API changes** (`/server/**` unaffected).
4. **FXML contract updates**:
- settings tab icons switch to explicit `SVGPath`.
- signing dialog single `signaturesTable` instance only.

## Test Cases and Scenarios

### Automated
1. Existing test suite green via `/Users/Magneto/CascadeProjects/autogram-macOS/scripts/macos-update-check.sh`.
2. Add UI controller tests (headless where possible):
- `PasswordController` autofocus behavior.
- Overlay focus assignment from `MainMenuController`.
- Settings tab switch state class toggling.
3. Add regression test for duplicate FXML IDs (parse-time assertion for critical FXML files).

### Manual Acceptance Matrix
1. Dark mode readability:
- settings labels, dropdown selected values, dropdown menu items, signature table texts, checkbox labels.
2. Modal sizing:
- certificate picker fits content without excessive empty space.
- PIN dialog compact and centered.
3. PIN workflow:
- modal opens with caret already in PIN field.
- numeric typing works immediately without mouse click.
4. Keyboard UX:
- tab traversal order logical,
- `Enter` and `Esc` behavior consistent.
5. Signing screen:
- no black text on dark background,
- action row readable at a glance.
6. Settings redesign:
- no icon squares,
- consistent alignment across all tabs.

## Rollout Plan (Phased)
1. Release A: Foundation + theme token fixes + critical readability.
2. Release B: Settings redesign + tab/icon cleanup.
3. Release C: Modal system + focus/keyboard polish + signing surface refinement.
4. Release D: QA hardening + docs/scripts finalization.

## Assumptions and Defaults
1. Slovak copy stays primary (no content rewrite, only UX microcopy polish where needed).
2. Existing business logic and signing behavior remain unchanged.
3. Existing single-window shell and inline overlay architecture remain (no AppKit rewrite).
4. Visual direction stays “soft glass hybrid” with native macOS restraint, not heavy glassmorphism.
5. Coverage warnings and JDK deprecation warnings are tracked separately and are not blockers for UI redesign.
