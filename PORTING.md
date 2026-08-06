# Porting Updates from Upstream

This project is a macOS-specialized fork of the [Slovensko.Digital Autogram](https://github.com/slovensko-digital/autogram) project. To keep this fork updated with new features and security fixes from the main repository, follow this guide.

## One-time Setup
Add the original repository as an `upstream` remote:
```bash
git remote add upstream https://github.com/slovensko-digital/autogram.git
```

## Pulling Updates
To sync with the latest changes:

1. **Fetch from upstream**:
   ```bash
   git fetch upstream
   ```

2. **Create a sync branch**:
   ```bash
   git switch -c codex/upstream-sync-YYYY-MM
   ```

3. **Merge changes**:
   ```bash
   git merge upstream/main
   ```

4. **Reapply local feature commits**:
   ```bash
   git cherry-pick <local-feature-commit>
   ```

Keep the upstream merge and local feature commits separate so the resulting PRs remain easy to review.

## Conflict Resolution & Protected Files
Our fork modifies specific parts of the UI and build configuration. Pay close attention to these files during a merge:

| Component | Files to Protect / Review Carefully |
| :--- | :--- |
| **CSS Theming** | `macos-native.css`, `macos-native-dark.css` |
| **FXML Layouts** | `main-menu.fxml`, `settings-dialog.fxml` |
| **Build Setup** | `pom.xml`, `run.sh` |
| **macOS Native** | `GUIUtils.java`, `MacOSNotification.java` |
| **CLI automation** | `scripts/macos-automation/`, `docs/macos-cli-automation.md` |

### Merge Recommendation
If a merge conflict occurs in `macos-native.css`, prioritize our changes (Apple HIG colors) while keeping any new structural classes introduced by upstream.

## Verification after Porting
After every merge from upstream, run with JDK 25 and JavaFX:
```bash
./mvnw -Psystem-jdk test
./mvnw -DskipTests package
```
Verify that:
1. The app menu still says **Autogram**.
2. Only one Dock icon appears.
3. The "macOS Native" styles (glassmorphism sidebar) are preserved.
4. `autogram --help` still exposes CLI mode and `PAdES_BASELINE_T`.
5. The Finder Quick Action still signs one or more selected PDFs without opening the GUI.
