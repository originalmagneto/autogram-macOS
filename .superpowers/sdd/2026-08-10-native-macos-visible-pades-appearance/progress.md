# SDD ledger - plan: docs/superpowers/plans/2026-08-10-native-macos-visible-pades-appearance.md

Workspace: /Users/Magneto/CascadeProjects/autogram-macOS-upstream-sync
Branch: codex/feature-cli-synced
Start commit: 9bca2054

Task 1: complete
  Commits: 80b2be93, 7e7fd43a, 6da5c6d5
  Proof: focused VisibleSignatureAssetTests passed; spec and code quality review approved
Task 2: complete
  Commits: 22c9dfb1, 1aae8503
  Proof: focused VisibleSignatureGeometryTests passed; spec and code quality review approved
Task 3: complete
  Commits: db3ffd95, 28233120
  Proof: focused Java and Swift session tests passed; spec and code quality review approved
Task 4: complete
  Commits: 26467251, c1b1a729, 209bc2bc
  Proof: focused Java and Swift signing tests passed; spec and code quality review approved
Task 5: complete
  Commits: f8d8eb7b, 465f6bf8, f53b1d54
  Proof: Java certificate boundary and native workspace tests passed; spec and code quality review approved
Task 6: pending live I.CA acceptance
  Proof: automated tests, ARM64 release build, signed bundle, installed helper, I.CA ARM64 library, and PDF runtime UI passed
Audit fix round 1: addressed
  Addressed: post-signing inspection failure now starts complete DSS validation; ordinary refresh failure no longer does
  Addressed: removed unconsumed committed preview flag and workspace argument
  Open: clean AutogramTests retains an unrelated renderer status-pixel assertion failure
