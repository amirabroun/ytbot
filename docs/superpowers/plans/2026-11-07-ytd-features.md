# ytd Feature Bundle Implementation Plan

> **For agentic workers:** Plan is executed natively in-session (Amir's standing rule:
> he picks, I execute). Steps tracked via session todos, not checkboxes. No commits —
> repo is not git.

**Goal:** 11 picked features: 480p, music folder `~/Downloads/ytd/Music`, best mp3
(`--audio-quality 0`), speed/ETA/size in row, pause/resume, persistent history,
dock badge, queue (max 2 concurrent), clear/remove rows, open file, mp3 cover art.

**Architecture:** Same shape — Model (data), Runner (yt-dlp process + pure parser),
Store (MainActor state machine), ContentView (rows). New `Status` cases
(`queued`, `paused`) drive the queue and pause/resume; history is a JSON snapshot
of `items` in Application Support; dock badge derives from active progresses.

**Tech Stack:** Swift 5.9 tools, SwiftUI/AppKit, macOS 13 target, no new dependencies.

**Spec:** Amir's picks in chat 2026-11-07 (this file). PLAN.md at repo root is the
outdated v1 spec — not authoritative for this bundle.

## Global Constraints

- UI text English. Notifications English.
- No git repo — no commits, working tree only.
- Constants, not a settings screen (`maxConcurrent = 2`, folders fixed).
- yt-dlp PROG contract (observed live 2026-11-07, `Me at the zoo` probe):
  `PROG:  1.1%|   5.48MiB/s|00:00|       N/A` — pipe-separated; placeholders
  `Unknown B/s`, `Unknown`, `N/A`, `NA` must parse to nil fields.
- Store setters keep the `runners[id] != nil` guard (late-line race, audit fix #1).

## Review Focus

1. Queue never stalls: every terminal transition (finish/pause/remove/cancel)
   calls `startQueuedIfNeeded()`.
2. Restored history maps `downloading`/`queued` → `paused` (never zombie-running).
3. Pause keeps `.part`: resume re-runs same args; yt-dlp continues, not restart.
4. Old-format PROG line (no pipes, `PROG: 42.5%`) still parses.
5. Quit path persists running rows as `paused` before exit.

---

### Task 1: Model — 480p, Live, queued/paused, Codable
**Files:** Modify `Sources/YtdApp/Model.swift`.
**Interfaces (produced):**
- `Quality`: + `case q480 = "480p"` (first case → picker order), `maxHeight` 480.
- `struct Live: Equatable, Codable { var progress: Double; var speed: String?; var eta: String?; var sizeEstimate: String? }`
- `enum Status: Equatable, Codable { case queued; case downloading(Live); case paused; case done(path: String?, sizeBytes: Int64?); case failed(message: String) }`
- `Phase`: `queued, running, paused, succeeded, failed`; `Status.phase` maps 1:1.
- `DownloadItem: Identifiable, Equatable, Codable` (fields unchanged, no new ones).

### Task 2: Runner — new PROG template, parser, music branch
**Files:** Modify `Sources/YtdApp/Runner.swift`, `scripts/check-ytdlp.sh`.
**Interfaces:**
- Consumes: `Live`, `targetDir(audioOnly:)`.
- Produces: `ParsedLine.progress(Live)` (replaces `.progress(Double)`); `parse(_:) -> ParsedLine?` unchanged signature; `cleanStat(_:) -> String?` private.
- Template: `"PROG:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_estimate_str)s"`.
- Music args: `-f ba/b -x --audio-format mp3 --audio-quality 0 --embed-thumbnail`; output dir `targetDir(audioOnly: true)`.

### Task 3: Support — music dir
**Files:** Modify `Sources/YtdApp/Support.swift`.
**Interfaces:** `let musicDir` = `~/Downloads/ytd/Music`; `func targetDir(audioOnly: Bool) -> URL`; `ensureDownloadDir()` creates both dirs.

### Task 4: Store — queue, pause/resume, list ops, history, badge
**Files:** Modify `Sources/YtdApp/Store.swift`.
**Interfaces:**
- Public: `pause(_:)`, `resume(_:)`, `cancel(_:)` (queued rows only), `remove(_:)`, `clearCompleted()`, `openFile(_:)`; `add/retry/reveal/openFolder` unchanged; `retry` accepts `.failed` only, `resume` accepts `.paused` only.
- Private: `maxConcurrent = 2`; `launchOrQueue(_:)` (slot check → start or mark queued); `startQueuedIfNeeded()` (oldest queued first — `items` is newest-first); `setLive(_:id:)` replaces `setProgress`; `persist()`/`loadHistory()` with `historyURL` = `~/Library/Application Support/ytd/history.json`; `refreshDockBadge()` = avg active %, `NSApplication.shared.dockTile.badgeLabel`.
- `appWillTerminate`: terminate all, mark running → `paused`, `persist()`.

### Task 5: ContentView — row states, buttons, footer
**Files:** Modify `Sources/YtdApp/ContentView.swift`.
- Downloading row: bar + % + caption line `[speed · eta · size]` (nil parts skipped).
- Queued row: "Waiting…". Paused row: "Paused" + ▶.
- Trailing: running → pause button; queued → ✕; paused → ▶; failed → ↻ + trash; done → trash (+"Open" link next to "Show in Finder").
- Footer: + "Clear Completed" (only when a done row exists).

### Task 6: Tests + verify
**Files:** Modify `Tests/ytdTests/ParseTests.swift`.
- Real observed lines (probe 2026-11-07): full stats, `Unknown B/s|Unknown|N/A`, `NA|NA` postproc, bare `PROG: 42.5%`, clamp, garbage, TITLE/FILE, prefix-exact.
- `testItemCodableRoundTrip` pins synthesized Codable (persistence contract).
- Verify: `swift build` (0 warnings), `swift test` green, check no active yt-dlp
  under ytd before relaunch, `make-app.sh`, `open`, memory update.
