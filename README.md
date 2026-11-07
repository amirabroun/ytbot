# ytbot

[![CI](https://github.com/amirabroun/ytbot/actions/workflows/ci.yml/badge.svg)](https://github.com/amirabroun/ytbot/actions/workflows/ci.yml)

A native macOS downloader for video and music, powered by
[yt-dlp](https://github.com/yt-dlp/yt-dlp). Paste a link, pick a quality, done —
files land in `~/Downloads/ytd` (music in `~/Downloads/ytd/Music`).

## Features

- **Video** — 480p / 720p / 1080p / 4K, merged to mp4
- **Music** — MP3 at best quality (VBR), cover art embedded, saved to a
  separate `Music/` folder
- **Live rows** — progress bar plus speed, ETA and estimated size
- **Pause / resume** — pausing keeps the partial file; resuming continues
  where it stopped
- **Queue** — at most two downloads run at once, the rest wait
- **History** — the list survives restarts
  (`~/Library/Application Support/ytd/history.json`)
- **Dock badge** — average progress while downloads are active
- **Notifications** when a download finishes or fails
- Reveal in Finder, open the file, clear finished rows

## Requirements

- macOS 13+
- yt-dlp and ffmpeg on your PATH:

  ```bash
  brew install yt-dlp ffmpeg
  ```

- Xcode or Command Line Tools (Swift 5.9+)

## Build & run

```bash
swift build                # debug binary
bash scripts/make-app.sh   # release build + build/ytd.app bundle
open build/ytd.app
```

The executable and app bundle are named `ytd`.

## Tests

```bash
swift test
```

`ParseTests` pins the yt-dlp stdout contract (progress / title / file lines,
placeholders like `Unknown`, `NA`, `N/A`) and the JSON history encoding.

## How it works

One download = one `yt-dlp` process. The app reads a machine-readable stdout
contract built from `--print` and `--progress-template`, so there is no
screen-scraping:

```
PROG: 42.5%| 3.22MiB/s| 00:12| ~120.34MiB
TITLE:Some Video Title
FILE:/Users/you/Downloads/ytd/Some Video [abc123].mp4
```

- `Sources/YtdApp/Model.swift` — download items and statuses
  (`queued / downloading / paused / done / failed`)
- `Runner.swift` — spawns yt-dlp, pure line parser
- `Store.swift` — MainActor state machine: queue, pause/resume, persistence,
  dock badge
- `ContentView.swift` — the window UI

Interrupted downloads keep their `.part` file on disk — resuming continues
instead of restarting.

## License

[MIT](LICENSE)
