# GitHub README Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the root README with a polished GitHub product landing page, then fast-forward the completed feature into `main` and install the current local application build.

**Architecture:** Keep the README self-contained with GitHub-native Markdown, the existing local app icon, factual badges, one Mermaid workflow, and links to detailed documentation. Verification checks links and hygiene before merging. The application build uses the existing native packaging scripts and is copied to Applications only after focused verification.

**Tech Stack:** GitHub Markdown, Mermaid, shields.io badges, Git, native macOS build scripts.

## Global Constraints

- No obsolete screenshots, tracking assets, personal paths, secrets, client information, or em dashes.
- Do not change application behavior in this plan.
- Preserve preview status, macOS 27+, Apple silicon, middleware, PIN security, upstream attribution, and EUPL facts.
- Merge must be fast-forward only.

---

### Task 1: Redesign and verify README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: existing documentation and `native-macos/Autogram/Resources/AppIcon.svg`.
- Produces: GitHub product landing page with hero, badges, navigation, feature table, workflow, focused sections, and collapsible development details.

- [ ] Rewrite `README.md` according to the approved design specification.
- [ ] Verify every relative Markdown link resolves to an existing repository file.
- [ ] Verify no personal path, obsolete screenshot reference, em dash, or secret-like value was introduced.
- [ ] Review the rendered Markdown structure and commit the README change.

### Task 2: Merge, build, install, and push

**Files:**
- Use: `scripts/native-macos/build-native-app.sh`
- Use: `scripts/native-macos/sign-native-app.sh`
- Use: `scripts/native-macos/verify-native-release.sh`

**Interfaces:**
- Consumes: completed feature branch and local ARM64 JDK 25 plus Xcode beta.
- Produces: updated `main`, synchronized `origin/main`, and current `/Applications/Autogram macOS.app`.

- [ ] Run focused Quick Action, installer, plist, and README checks.
- [ ] Build and locally sign the current native application.
- [ ] Confirm the built application contains managed workflow version `2` and the ARM64 runner.
- [ ] Replace `/Applications/Autogram macOS.app` with the verified build.
- [ ] Fast-forward local `main` to the feature branch and push `main`.
- [ ] Verify local `main`, `origin/main`, and the installed application state.
