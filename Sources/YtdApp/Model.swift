import Foundation

enum Quality: String, CaseIterable, Identifiable, Codable {
  case q480 = "480p"
  case q720 = "720p"
  case q1080 = "1080p"
  case q2160 = "4K"

  var id: String { rawValue }

  var maxHeight: Int {
    switch self {
    case .q480: 480
    case .q720: 720
    case .q1080: 1080
    case .q2160: 2160
    }
  }
}

/// Live numbers shown under the progress bar; strings come pre-formatted from yt-dlp.
struct Live: Equatable, Codable {
  var progress: Double // 0...1
  var speed: String?
  var eta: String?
  var sizeEstimate: String?
}

enum Status: Equatable, Codable {
  case queued
  case downloading(Live)
  case paused // .part on disk; resume continues it
  case done(path: String?, sizeBytes: Int64?) // path nil = already existed (yt-dlp skip)
  case failed(message: String)

  /// Same cases without the payload, for icon/button switches.
  var phase: Phase {
    switch self {
    case .queued: .queued
    case .downloading: .running
    case .paused: .paused
    case .done: .succeeded
    case .failed: .failed
    }
  }
}

enum Phase {
  case queued, running, paused, succeeded, failed
}

struct DownloadItem: Identifiable, Equatable, Codable {
  let id: UUID
  let url: String
  let audioOnly: Bool
  let quality: Quality
  var title: String // starts as url, replaced by the TITLE line
  var status: Status
}
