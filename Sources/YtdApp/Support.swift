import Foundation

let downloadDir: URL = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Downloads/ytd")
let musicDir: URL = downloadDir.appendingPathComponent("Music")

func targetDir(audioOnly: Bool) -> URL {
  audioOnly ? musicDir : downloadDir
}

func ensureDownloadDir() {
  try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
}

private var ytdlpCache: String?

func locateYtdlp() -> String? {
  if let ytdlpCache { return ytdlpCache }
  for p in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
  where FileManager.default.isExecutableFile(atPath: p) {
    ytdlpCache = p
    return p
  }
  let which = runSync("/bin/zsh", ["-lc", "which yt-dlp"])
  if let which, !which.isEmpty {
    ytdlpCache = which
    return which
  }
  return nil
}

func isPlausibleURL(_ s: String) -> Bool {
  let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
  return t.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil
}

func byteFormat(_ bytes: Int64) -> String {
  ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// Runs a short command synchronously, returns trimmed stdout (nil on any failure).
private func runSync(_ path: String, _ args: [String]) -> String? {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: path)
  p.arguments = args
  let out = Pipe()
  p.standardOutput = out
  p.standardError = Pipe()
  do {
    try p.run()
    p.waitUntilExit()
  } catch {
    return nil
  }
  guard p.terminationStatus == 0 else { return nil }
  let data = out.fileHandleForReading.readDataToEndOfFile()
  return String(data: data, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines)
}
