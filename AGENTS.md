# RuneReader — Project Rules

This file applies to `E:\Project\AI\RuneReader` and everything below it. It overrides the parent `E:\Project\AI\AGENTS.md` where the two conflict. Rules of the parent file that are not overridden here (voice, reporting, Windows environment, safety) still apply.

## Project

- Android e-book reader (TXT and image viewer) written in Dart with Flutter.
- Target platform: Android only. Do not add iOS, web, or desktop platforms unless asked.
- Feature specification and implementation checklist: `docs/FEATURES.md`. Update it whenever a feature is added, changed, or verified.

## Toolchain

- Flutter 3.47.7 (stable) with Dart 3.13.5, installed project-locally at `.sdk\flutter`.
- Android SDK installed project-locally at `.sdk\android` (platform 36, build-tools 36.0.0, platform-tools, NDK 28.2.13676358; CMake 3.22.1 is fetched by AGP on demand). The machine-wide SDK at `C:\Users\runed\AppData\Local\Android\Sdk` has stripped packages (no `android.jar`, no NDK `build/cmake`) and must not be used for builds.
- `.sdk\` is git-ignored. Never use the global Flutter at `C:\envs\flutter`.
- Build and run through the wrapper, which points `ANDROID_HOME` at `.sdk\android` and isolates `LOCALAPPDATA` from stale `AndroidStudio*` folders that crash the Flutter tool:
  - `.\tool\flutter.ps1 pub get`
  - `.\tool\flutter.ps1 analyze`
  - `.\tool\flutter.ps1 test`
  - `.\tool\flutter.ps1 build apk --debug`
  - `.\tool\flutter.ps1 run -d emulator-5554`
- Restore on a fresh checkout:
  - `git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git .sdk\flutter`
  - copy `licenses\android-sdk-license` from the machine SDK into `.sdk\android\licenses\`, then
    `& C:\Users\runed\AppData\Local\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat --sdk_root=.sdk\android platforms/android-36 build-tools/36.0.0 platform-tools ndk/28.2.13676358`
    (the current `sdkmanager` wrapper expects `/`-separated package paths).
- `android/gradle.properties` sets `kotlin.incremental=false`: plugin sources in the pub cache (C:) and build output (E:) on different drives break Kotlin incremental caches.
- JDK: Zulu 21 (`JAVA_HOME`).
- Package manager: pub (`pubspec.lock` is committed).

## Version Control: Jujutsu

- This repository is a colocated Jujutsu + Git repository (`.jj` and `.git`). Use `jj` for all version-control work. Use `git` only for read-only inspection or when `jj` has no equivalent.
- The parent `AGENTS.md` sections "Git Workflow", "Commits", "Commit Messages", "Integration into the Default Branch", and "Archiving the Integrated Branch" do NOT apply to this project.
- Working style:
  - The working-copy commit (`@`) is snapshotted automatically. Describe finished work with `jj describe -m "..."` or `jj commit -m "..."`.
  - Commit directly on the main line; task bookmarks, squash integration, and archive tags are not required.
  - Commit messages: short, descriptive; Korean or English. Conventional Commit prefixes are optional.
  - Move the `main` bookmark with `jj bookmark set main -r @-` after committing when a Git branch is needed.
- Still forbidden without explicit request: pushing to a remote, `jj abandon` or `jj op restore` on work you did not create, and rewriting commits that were already pushed.
- Never commit `.sdk/`, `build/`, `.dart_tool/`, signing keys, or `local.properties`.

## Code Conventions

- Follow `analysis_options.yaml` (`flutter_lints`). `flutter analyze` must report no issues, and `flutter test` must pass before a commit.
- State management: plain `ChangeNotifier` + `ListenableBuilder`; no state-management package.
- Directory layout:
  - `lib/models` — data classes with JSON (de)serialization
  - `lib/services` — I/O, decoding, fonts, persistence, pagination
  - `lib/ui` — pages and widgets
- Add unit tests under `test/` for logic in `lib/models` and `lib/services`.
