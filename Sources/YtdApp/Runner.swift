import Foundation

struct RunOutcome {
  let exitCode: Int32
  let errorText: String
}

/// One parsed stdout line from yt-dlp.
enum ParsedLine: Equatable {
  case progress(Live)
  case title(String)
  case filePath(String)
}

@MainActor
final class YtdlpRunner {
  private(set) var process: Process?
  private let ytdlpPath: String

  init(ytdlpPath: String) {
    self.ytdlpPath = ytdlpPath
  }

  /// One download = one yt-dlp process. All callbacks fire on MainActor.
  func run(url: String,
           audioOnly: Bool,
           quality: Quality,
           onTitle: @escaping @MainActor (String) -> Void,
           onProgress: @escaping @MainActor (Live) -> Void,
           onFilePath: @escaping @MainActor (String) -> Void) async -> RunOutcome {
    let p = Process()
    process = p
    p.executableURL = URL(fileURLWithPath: ytdlpPath)
    var args = [
      "--newline", "--no-playlist", "--progress",
      "-o", targetDir(audioOnly: audioOnly).path + "/%(title).120B [%(id)s].%(ext)s",
      "--progress-template",
      "PROG:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_estimate_str)s",
      "--print", "video:TITLE:%(title)s",
      "--print", "after_move:FILE:%(filepath)s",
    ]
    if audioOnly {
      // Best source stream, best mp3 VBR, cover art embedded.
      args += ["-f", "ba/b", "-x", "--audio-format", "mp3",
               "--audio-quality", "0", "--embed-thumbnail"]
    } else {
      let h = quality.maxHeight
      args += [
        "-f", "bv*[height<=\(h)]+ba/b[height<=\(h)]/b",
        "--merge-output-format", "mp4",
      ]
    }
    args.append(url)
    p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
    p.environment = env

    let out = Pipe()
    let err = Pipe()
    p.standardOutput = out
    p.standardError = err

    do {
      try p.run()
    } catch {
      return RunOutcome(exitCode: -1, errorText: clip("spawn failed: \(error.localizedDescription)"))
    }

    // Line-buffer stdout; decode per line so a multibyte char split across
    // chunks survives (\n never appears inside a UTF-8 sequence).
    let buffer = LineBuffer()
    out.fileHandleForReading.readabilityHandler = { handle in
      let chunk = handle.availableData
      if chunk.isEmpty {
        handle.readabilityHandler = nil
        return
      }
      buffer.data.append(chunk)
      while let nl = buffer.data.firstIndex(of: 0x0A) {
        let lineData = buffer.data.prefix(upTo: nl)
        buffer.data = Data(buffer.data[(nl + 1)...])
        // Parse here, off MainActor; only matching lines pay the Task hop.
        if let line = String(data: lineData, encoding: .utf8),
           let parsed = Self.parse(line) {
          Task { @MainActor in
            switch parsed {
            case .progress(let v): onProgress(v)
            case .title(let t): onTitle(t)
            case .filePath(let p): onFilePath(p)
            }
          }
        }
      }
    }

    let errHandle = err.fileHandleForReading
    let errTask = Task.detached(priority: .utility) { () -> String in
      var s = String(decoding: errHandle.readDataToEndOfFile(), as: UTF8.self)
      if s.count > 2000 { s = String(s.suffix(2000)) }
      return s
    }

    let exitCode = await Task.detached(priority: .utility) { () -> Int32 in
      p.waitUntilExit()
      return p.terminationStatus
    }.value

    let stderrText = await errTask.value
    let errorText = firstErrorLine(stderrText) ?? lastLine(stderrText) ?? ""
    return RunOutcome(exitCode: exitCode, errorText: errorText)
  }

  /// stdout parse contract: PROG:/TITLE:/FILE: prefixes, everything else ignored.
  /// PROG fields are pipe-separated: percent|speed|eta|size-estimate (observed live
  /// 2026-11-07; yt-dlp pads with spaces and uses Unknown/NA/N/A placeholders).
  /// Pure so it stays testable; called from the pipe's readability handler.
  nonisolated static func parse(_ line: String) -> ParsedLine? {
    let t = line.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("PROG:") {
      let parts = t.dropFirst(5).split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
      let raw = (parts.first ?? "").replacingOccurrences(of: "%", with: "")
      if let v = Double(raw) {
        return .progress(Live(
          progress: min(max(v / 100, 0), 1),
          speed: parts.count > 1 ? cleanStat(parts[1]) : nil,
          eta: parts.count > 2 ? cleanStat(parts[2]) : nil,
          sizeEstimate: parts.count > 3 ? cleanStat(parts[3]) : nil
        ))
      }
      return nil
    }
    if t.hasPrefix("TITLE:") { return .title(String(t.dropFirst(6))) }
    if t.hasPrefix("FILE:") { return .filePath(String(t.dropFirst(5))) }
    return nil
  }

  /// nil for yt-dlp placeholders ("Unknown B/s", "NA", "N/A", "--:--") — nothing worth showing.
  nonisolated private static func cleanStat(_ s: String) -> String? {
    let v = s.trimmingCharacters(in: .whitespaces)
    if v.isEmpty || v == "NA" || v == "N/A" || v.contains("Unknown") || v == "--:--" {
      return nil
    }
    return v
  }

  private func firstErrorLine(_ s: String) -> String? {
    for line in s.split(separator: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      if t.hasPrefix("ERROR") { return clip(t) }
    }
    return nil
  }

  private func lastLine(_ s: String) -> String? {
    for line in s.split(separator: "\n").reversed() {
      let t = line.trimmingCharacters(in: .whitespaces)
      if !t.isEmpty { return clip(t) }
    }
    return nil
  }
}

private func clip(_ s: String) -> String {
  String(s.prefix(100))
}

/// Accumulates pipe bytes until a full line is available; the readability
/// handler is the only reader/writer, so no locking is needed.
private final class LineBuffer {
  var data = Data()
}
