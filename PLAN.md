# ytd — macOS Menu Bar Downloader — Implementation Plan (v2)

> Supersedes the Telegram-bot plan (written earlier today, 2026-11-06).
> Amir dropped Telegram entirely: he gives links to an app ON his Mac,
> downloads land ON his Mac. Do not reintroduce Telegram, a server,
> Docker, or any network listener.
>
> For the next session: run Tasks 0–5. Decisions below are settled with
> Amir — don't relitigate, don't add infra. No commits/push/git-init
> without his fresh explicit ask.

**Goal:** A native macOS menu bar app. Click icon → paste link → yt-dlp
downloads it to `~/Downloads/ytd/` → macOS notification when done. Menu
window shows active progress + past downloads + reveal-in-Finder.

**Architecture:** Single Swift executable (SwiftUI `MenuBarExtra`,
window style) that shells out to `yt-dlp` (Homebrew) via `Process`.
Each download = one Process, parsed line-by-line. No server, no DB —
in-memory list, files on disk are the source of truth.

**Tech stack:** Swift 5.9+ / SwiftUI (`MenuBarExtra`, needs macOS 13+;
his machine is far newer), Swift Package Manager (`swift build` — no
Xcode project file), `yt-dlp` + `ffmpeg` via Homebrew.

**Status (2026-11-06):** folder + this plan only. Nothing built.

## Approved decisions — do not reopen

- Native Mac app, menu bar (no Dock icon). NOT a web page, NOT CLI-only,
  NOT a Telegram bot.
- yt-dlp stays the engine (home IP — best for YouTube).
- Downloads go to `~/Downloads/ytd/`. App keeps files there; no upload
  anywhere; no size cap.
- Format: best mp4 up to 1080p, single video, no playlists.
- App name/binary: `ytd`. Display name «دانلودر». Bundle id
  `ir.abroun.ytd`. Folder stays `~/Documents/repos/ytbot/` (rename only
  if Amir asks).
- UI language: Persian, RTL.
- No secrets, no accounts, no config file in v1 — folder + format are
  constants. If Amir later wants settings, that's a new ask.

## File structure

```
~/Documents/repos/ytbot/
  Package.swift
  Sources/YtdApp/
    App.swift        — @main, MenuBarExtra scene, label with live %
    ContentView.swift— TextField + list + footer
    Store.swift      — DownloadStore (ObservableObject), actions
    Runner.swift     — yt-dlp Process wrapper + line parser
    Model.swift      — DownloadItem, Status
    Support.swift    — yt-dlp path lookup, download dir, size format
  scripts/make-app.sh — release build + wrap into ytd.app + ad-hoc sign
  PLAN.md
```

## Spec

### Support.swift

- `let downloadDir: URL` = `~/Downloads/ytd` (expand `~` in Swift via
  `FileManager.default.homeDirectoryForCurrentUser`). App creates it at
  startup (`createDirectory(withIntermediateDirectories:)`).
- `func locateYtdlp() -> String?` — first existing of
  `/opt/homebrew/bin/yt-dlp`, `/usr/local/bin/yt-dlp`, then `which yt-dlp`
  via `/bin/zsh -lc "which yt-dlp"`. Result cached.
- `func isPlausibleURL(_ s: String) -> Bool` — trimmed, matches
  `^https?://\S+$`.

### Model.swift — exact types

```swift
enum Status: Equatable {
  case downloading(progress: Double)          // 0...1
  case done(path: String?, sizeBytes: Int64?) // path nil = skipped (already existed)
  case failed(message: String)
}

struct DownloadItem: Identifiable, Equatable {
  let id: UUID
  let url: String
  var title: String                            // starts as url, replaced by TITLE line
  var status: Status
  let startedAt: Date
}
```

### Runner.swift — yt-dlp invocation, exact contract

```swift
final class YtdlpRunner {
  /// Runs yt-dlp for one URL. All callbacks are invoked on MainActor.
  func run(url: String,
           onTitle: @escaping (String) -> Void,
           onProgress: @escaping (Double) -> Void,
           onFilePath: @escaping (String) -> Void) async -> Result
  struct Result { let exitCode: Int32; let errorText: String } // errorText = best ERROR line, ≤100 chars
}
```

Process arguments (exact order irrelevant; exact values matter):

```
yt-dlp --newline --no-playlist
  -f "bv*[height<=1080]+ba/b[height<=1080]/b"
  --merge-output-format mp4
  -o "<downloadDir>/%(title).120B [%(id)s].%(ext)s"
  --progress-template "PROG:%(progress._percent_str)s"
  --print "video:TITLE:%(title)s"
  --print "after_move:FILE:%(filepath)s"
  <url>
```

- Environment: prepend `/opt/homebrew/bin:/usr/local/bin` to `PATH` so
  yt-dlp finds ffmpeg.
- Read stdout line-by-line on a background Task; dispatch to MainActor.
- **Parse contract (stdout):**
  - line starts `PROG:` → strip `%`, `Double`, clamp 0...1 → onProgress
  - line starts `TITLE:` → onTitle(rest)
  - line starts `FILE:` → onFilePath(rest) — post-merge final path
  - ignore everything else
- stderr: keep last ~2000 chars. On exit ≠ 0: `errorText` = first line
  matching `ERROR:` (trimmed, ≤100 chars), fallback last stderr line.
- Exit 0 with no `FILE:` line (yt-dlp "already downloaded" skip) →
  `.done(path: nil, …)`.
- The running `Process` handle must be kept reachable so the app can
  `terminate()` it on quit.

### Store.swift

```swift
@MainActor
final class DownloadStore: ObservableObject {
  @Published private(set) var items: [DownloadItem] = []   // newest first
  @Published var ytdlpPath: String?                        // nil → show install hint, disable input
  @Published var livePercent: Double?                      // nil when idle; drives menu bar label

  func add(url: String)            // validate isPlausibleURL, create item, start
  func reveal(_ item: DownloadItem)// NSWorkspace.activateFileViewerSelecting([path]) if path
  func openFolder()                // NSWorkspace.open(downloadDir)
  func terminateAll()              // kill running yt-dlp processes (app quit)
}
```

- Multiple downloads in parallel are allowed (single user; keep it).
- On app termination (`willTerminate` / scene phase) → `terminateAll()`.
  Partial `.part` files stay; yt-dlp resumes them on re-download of the
  same URL. No cleanup logic.

### App.swift

```swift
@main
struct YtdApp: App {
  @StateObject private var store = DownloadStore()
  // MenuBarExtra label: Image(systemName: "arrow.down.circle");
  // while store.livePercent != nil show "⬇︎ NN%" instead.
  // .menuBarExtraStyle(.window)
}
```

- Startup: resolve yt-dlp path; if nil → window shows
  «yt-dlp نصب نیست: brew install yt-dlp» and the input is disabled.

### ContentView.swift (inside the MenuBarExtra window)

- Whole view RTL: `.environment(\.layoutDirection, .rightToLeft)`.
- `TextField «لینک را بچسبان…»`, `.onSubmit` → `store.add(url:)`, then
  clears. Auto-focus on window open (`.onAppear` focus the field).
- List = `store.items` (newest first). Row:
  - `downloading` → title (or url) + `ProgressView(value:)` + percent
  - `done` → title, filename, size via `ByteCountFormatter`,
    button «نمایش» → `store.reveal`
  - `failed` → title + red one-line message
- Footer: button «پوشه دانلود‌ها» → `store.openFolder()`.
- Touch/click targets ≥ 28pt; system font sizes only; no custom colors
  beyond system semantic colors (dark mode must stay correct).

### Notifications

- `UNUserNotificationCenter` on done/failed. Request authorization
  ("alert | sound") on first submit, degrade silently if denied.
- Requires the app bundle (Task 4) — notifications will crash an
  unbundled `swift run`; that's expected, always test via ytd.app.

### scripts/make-app.sh

1. `swift build -c release`
2. `rm -rf build/ytd.app && mkdir -p build/ytd.app/Contents/MacOS`
3. copy `.build/release/ytd` → `Contents/MacOS/ytd`
4. write `Contents/Info.plist`: `CFBundleIdentifier=ir.abroun.ytd`,
   `CFBundleName=ytd`, `CFBundleExecutable=ytd`,
   `LSUIElement=true` (no Dock icon), `CFBundlePackageType=APPL`
5. `codesign --force -s - build/ytd.app` (ad-hoc)

Launch: `open build/ytd.app`. Login-at-start: Amir adds it manually in
System Settings → General → Login Items (tell him once; no SMAppService
code in v1).

## Tasks

### Task 0 — toolchain check
- [ ] `swift --version` → 5.9+; if missing → `xcode-select --install`
      first (ask Amir before installing anything).
- [ ] `yt-dlp --version && ffmpeg -version` → else
      `brew install yt-dlp ffmpeg`.

### Task 1 — package skeleton
- [ ] `Package.swift`: swift-tools 5.9, platforms `.macOS(.v13)`,
      executable target `YtdApp` at `Sources/YtdApp`.
- [ ] Empty type stubs so `swift build` passes.

### Task 2 — core (no UI needed to verify)
- [ ] `Support.swift`, `Model.swift`, `Runner.swift`, `Store.swift`
      per spec.
- [ ] Inline check (throwaway, allowed): run the Runner against a real
      short YouTube URL from a `swift run` debug entry OR a tiny
      temporary main; confirm TITLE/PROG/FILE parsing and the file
      lands in `~/Downloads/ytd/`. Delete junk file after. Expect exit 0.

### Task 3 — UI
- [ ] `App.swift` + `ContentView.swift` per spec.
- [ ] `swift build` → BUILD SUCCEEDED, zero warnings.

### Task 4 — bundle
- [ ] `scripts/make-app.sh` per spec; `open build/ytd.app`; menu bar
      icon appears, window opens.

### Task 5 — Amir's manual test (he tests himself)
- [ ] Paste link → progress → notification → file in Finder via «نمایش».
- [ ] Bad link (random non-video URL) → red error row, app alive.
- [ ] Quit app mid-download → rerun same link → resumes `.part`.

## Review focus — failure modes a reasonable person expects

- yt-dlp not installed → clear Persian hint, input disabled, no crash.
- Private/age-restricted/unsupported → `failed` row with short real
  error from yt-dlp; app stays alive.
- Long titles → `%(title).120B` keeps filenames sane.
- Same URL twice → second run ends `done(path: nil)` ("already
  downloaded") — row must not look like an error.
- App quit mid-download → yt-dlp killed (no zombie), `.part` resumable.
- Dark mode + RTL → no broken contrast, no LTR text leaking in Persian
  UI (urls/filenames shown LTR-isolated).
- Empty clipboard/Enter on empty field → no-op, no phantom row.

## Out of scope — ask before adding

- Share Sheet / Services integration (Safari → app) — needs bundle
  registration work, separate ask.
- Audio-only mode, playlists, 4K, quality picker.
- Settings UI (folder/format are constants for now).
- Auto-add to Login Items via SMAppService.
- Download history persistence across launches (in-memory for v1).

## Hard rules (Amir's global AGENTS.md)

- He tests the GUI/Telegram-less app himself; agent ceiling = swift
  build + the Task 2 inline Runner check.
- No commits/push without a fresh explicit ask. `git init` also needs
  an ask.
- Nothing deleted without his approval (old files in this folder:
  replace PLAN.md content only — already done by writing this file).
