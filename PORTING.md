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

2. **Merge changes**:
   ```bash
   git merge upstream/master
   ```

## Conflict Resolution & Protected Files
Our fork modifies specific parts of the UI and build configuration. Pay close attention to these files during a merge:

| Component | Files to Protect / Review Carefully |
| :--- | :--- |
| **CSS Theming** | `macos-native.css`, `macos-native-dark.css` |
| **FXML Layouts** | `main-menu.fxml`, `settings-dialog.fxml` |
| **Build Setup** | `pom.xml`, `run.sh` |
| **macOS Native** | `GUIUtils.java`, `MacOSNotification.java` |

### Merge Recommendation
If a merge conflict occurs in `macos-native.css`, prioritize our changes (Apple HIG colors) while keeping any new structural classes introduced by upstream.

## Verification after Porting
After every merge from upstream, run:
```bash
./run.sh
```
Verify that:
1. The app menu still says **Autogram**.
2. Only one Dock icon appears.
3. The "macOS Native" styles (glassmorphism sidebar) are preserved.
