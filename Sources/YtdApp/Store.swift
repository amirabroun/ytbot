import AppKit
import Combine
import UserNotifications

@MainActor
final class DownloadStore: NSObject, ObservableObject {
  @Published private(set) var items: [DownloadItem] = [] // newest first
  @Published private(set) var ytdlpPath: String? = locateYtdlp()

  /// More than this many at once and new rows wait in the queue.
  private let maxConcurrent = 2
  private var runners: [UUID: YtdlpRunner] = [:]
  private var pendingPath: [UUID: String] = [:] // FILE line arrives before process exit
  private var askedNotificationAuth = false

  private static let historyURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ytd/history.json")

  override init() {
    super.init()
    ensureDownloadDir()
    try? FileManager.default.createDirectory(
      at: Self.historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    loadHistory()
    // Selector-based on purpose: no closure isolation puzzles; kills yt-dlp on any quit path.
    NotificationCenter.default.addObserver(
      self, selector: #selector(appWillTerminate),
      name: NSApplication.willTerminateNotification, object: nil)
  }

  @objc private func appWillTerminate() {
    for (id, runner) in runners {
      runner.process?.terminate()
      patch(id) { $0.status = .paused }
    }
    runners.removeAll()
    persist()
  }

  func add(url raw: String, audioOnly: Bool = false, quality: Quality = .q1080) {
    let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard ytdlpPath != nil, isPlausibleURL(url) else { return }
    askNotificationAuthIfNeeded()

    let id = UUID()
    items.insert(DownloadItem(id: id, url: url, audioOnly: audioOnly, quality: quality,
                              title: url, status: .queued),
                 at: 0)
    launchOrQueue(id: id, url: url, audioOnly: audioOnly, quality: quality)
    persist()
  }

  /// Restarts a failed row in place with the same URL and options.
  func retry(_ item: DownloadItem) {
    guard ytdlpPath != nil, case .failed = item.status,
          items.contains(where: { $0.id == item.id }) else { return }
    launchOrQueue(id: item.id, url: item.url, audioOnly: item.audioOnly, quality: item.quality)
    persist()
  }

  /// Continues a paused row; yt-dlp resumes the .part file instead of restarting.
  func resume(_ item: DownloadItem) {
    guard ytdlpPath != nil, case .paused = item.status,
          items.contains(where: { $0.id == item.id }) else { return }
    launchOrQueue(id: item.id, url: item.url, audioOnly: item.audioOnly, quality: item.quality)
    persist()
  }

  /// Stops a running download but keeps its .part for resume().
  /// finish() then no-ops for this id (runner already removed).
  func pause(_ item: DownloadItem) {
    guard runners[item.id] != nil else { return }
    runners[item.id]?.process?.terminate()
    runners[item.id] = nil
    pendingPath[item.id] = nil
    patch(item.id) { $0.status = .paused }
    refreshDockBadge()
    persist()
    startQueuedIfNeeded()
  }

  /// Drops a waiting (queued) row from the queue.
  func cancel(_ item: DownloadItem) {
    guard case .queued = item.status,
          let i = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[i].status = .failed(message: "Cancelled")
    persist()
  }

  /// Deletes a row from the list (terminating its process first if still running).
  func remove(_ item: DownloadItem) {
    runners[item.id]?.process?.terminate()
    runners[item.id] = nil
    pendingPath[item.id] = nil
    items.removeAll { $0.id == item.id }
    refreshDockBadge()
    persist()
    startQueuedIfNeeded()
  }

  /// Removes every finished row.
  func clearCompleted() {
    items.removeAll { $0.status.phase == .succeeded }
    persist()
  }

  func reveal(_ item: DownloadItem) {
    guard case .done(let path, _) = item.status, let path else { return }
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }

  func openFile(_ item: DownloadItem) {
    guard case .done(let path, _) = item.status, let path else { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
  }

  func openFolder() {
    NSWorkspace.shared.open(downloadDir)
  }

  // MARK: - private

  private func patch(_ id: UUID, _ change: (inout DownloadItem) -> Void) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    change(&items[i])
  }

  /// Late stdout lines can arrive after pause()/finish() removed the runner;
  /// without the guard a stale PROG would resurrect a settled row.
  private func setTitle(_ title: String, id: UUID) {
    guard runners[id] != nil else { return }
    patch(id) { $0.title = title }
  }

  private func setLive(_ live: Live, id: UUID) {
    guard runners[id] != nil else { return }
    patch(id) { $0.status = .downloading(live) }
    refreshDockBadge()
  }

  private func setFilePath(_ path: String, id: UUID) {
    guard runners[id] != nil else { return }
    pendingPath[id] = path
  }

  private func start(id: UUID, url: String, audioOnly: Bool, quality: Quality) {
    guard let path = ytdlpPath else { return }
    let runner = YtdlpRunner(ytdlpPath: path)
    runners[id] = runner
    Task { [weak self] in
      let outcome = await runner.run(
        url: url,
        audioOnly: audioOnly,
        quality: quality,
        onTitle: { [weak self] title in self?.setTitle(title, id: id) },
        onProgress: { [weak self] live in self?.setLive(live, id: id) },
        onFilePath: { [weak self] path in self?.setFilePath(path, id: id) }
      )
      self?.finish(id: id, outcome: outcome)
    }
  }

  /// Starts the download when a slot is free, otherwise parks the row as queued.
  private func launchOrQueue(id: UUID, url: String, audioOnly: Bool, quality: Quality) {
    if runners.count < maxConcurrent {
      patch(id) { $0.status = .downloading(Live(progress: 0)) }
      start(id: id, url: url, audioOnly: audioOnly, quality: quality)
    } else {
      patch(id) { $0.status = .queued }
    }
  }

  /// Fills free slots with the oldest queued rows (items is newest-first).
  private func startQueuedIfNeeded() {
    guard runners.count < maxConcurrent else { return }
    let queued = items.reversed().filter { $0.status.phase == .queued }
    for item in queued where runners.count < maxConcurrent {
      launchOrQueue(id: item.id, url: item.url, audioOnly: item.audioOnly, quality: item.quality)
    }
  }

  private func finish(id: UUID, outcome: RunOutcome) {
    // Paused/cancelled rows are already settled; their runner is gone.
    guard runners.removeValue(forKey: id) != nil else { return }
    if outcome.exitCode == 0 {
      let path = pendingPath.removeValue(forKey: id)
      let size = path.flatMap { fileSize($0) }
      patch(id) { $0.status = .done(path: path, sizeBytes: size) }
      notify(title: "Download complete",
             body: path.map { ($0 as NSString).lastPathComponent } ?? "Already downloaded")
    } else {
      let msg = outcome.errorText.isEmpty ? "Unknown error" : outcome.errorText
      patch(id) { $0.status = .failed(message: msg) }
      notify(title: "Download failed", body: msg)
    }
    refreshDockBadge()
    persist()
    startQueuedIfNeeded()
  }

  /// Average percent of active downloads on the Dock icon; nil when idle.
  private func refreshDockBadge() {
    let ps = items.compactMap {
      if case .downloading(let live) = $0.status { return live.progress } else { return nil }
    }
    NSApplication.shared.dockTile.badgeLabel =
      ps.isEmpty ? nil : "\(Int(ps.reduce(0, +) / Double(ps.count) * 100))%"
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(items) {
      try? data.write(to: Self.historyURL, options: .atomic)
    }
  }

  private func loadHistory() {
    guard let data = try? Data(contentsOf: Self.historyURL),
          let saved = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
    // Anything mid-flight last session is interrupted → paused (resumable via .part).
    items = saved.map { item in
      var it = item
      if it.status.phase == .running || it.status.phase == .queued { it.status = .paused }
      return it
    }
  }

  private func fileSize(_ path: String) -> Int64? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
  }

  private func askNotificationAuthIfNeeded() {
    guard !askedNotificationAuth else { return }
    askedNotificationAuth = true
    UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  private func notify(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let request = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }
}
