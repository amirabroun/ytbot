import AppKit
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var store: DownloadStore
  @State private var urlText = ""
  @State private var audioOnly = false
  @State private var quality: Quality = .q1080
  @FocusState private var fieldFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      if store.ytdlpPath == nil {
        missingBanner
      }
      inputBar
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      Divider()
      list
      Divider()
      footer
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    .frame(minWidth: 440, minHeight: 480)
    .onAppear { fieldFocused = true }
  }

  // MARK: - input

  private var inputBar: some View {
    HStack(spacing: 8) {
      TextField("Paste a video URL…", text: $urlText)
        .textFieldStyle(.roundedBorder)
        .focused($fieldFocused)
        .onSubmit(add)

      if !audioOnly {
        Picker("Quality", selection: $quality) {
          ForEach(Quality.allCases) { q in
            Text(q.rawValue).tag(q)
          }
        }
        .pickerStyle(.menu)
        .fixedSize()
      }

      Toggle(isOn: $audioOnly) {
        Label("MP3", systemImage: "waveform")
      }
      .toggleStyle(.button)
      .help("Audio only (MP3)")

      Button("Download", action: add)
        .buttonStyle(.borderedProminent)
        .disabled(!canAdd)
    }
  }

  private var canAdd: Bool {
    store.ytdlpPath != nil && isPlausibleURL(urlText)
  }

  private func add() {
    guard canAdd else { return }
    store.add(url: urlText, audioOnly: audioOnly, quality: quality)
    urlText = ""
    fieldFocused = true
  }

  // MARK: - list

  private var list: some View {
    ZStack {
      if store.items.isEmpty {
        emptyState
      } else {
        List(store.items) { item in
          RowView(item: item)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
        .listStyle(.inset)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 44, weight: .light))
        .foregroundStyle(.tertiary)
      Text("No downloads yet")
        .font(.headline)
        .foregroundStyle(.secondary)
      Text("Paste a link above and press Return.")
        .font(.callout)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - missing engine

  private var missingBanner: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
      VStack(alignment: .leading, spacing: 2) {
        Text("yt-dlp is not installed")
          .font(.callout.weight(.medium))
        Text("brew install yt-dlp")
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.yellow.opacity(0.08))
    .overlay(Divider(), alignment: .bottom)
  }

  // MARK: - footer

  private var footer: some View {
    HStack {
      Button {
        store.openFolder()
      } label: {
        Label("Open Downloads Folder", systemImage: "folder")
      }
      .controlSize(.regular)
      Spacer()
      if store.items.contains(where: { $0.status.phase == .succeeded }) {
        Button("Clear Completed", action: store.clearCompleted)
          .controlSize(.regular)
      }
    }
  }
}

// MARK: - row

private struct RowView: View {
  let item: DownloadItem
  @EnvironmentObject private var store: DownloadStore

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      stateIcon
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(item.title)

        switch item.status {
        case .downloading(let live):
          liveRows(live)
        case .queued:
          Text("Waiting…")
            .font(.callout)
            .foregroundStyle(.secondary)
        case .paused:
          Text("Paused — resume to continue")
            .font(.callout)
            .foregroundStyle(.secondary)
        case .done(let path, let size):
          doneRow(path: path, size: size)
        case .failed(let message):
          Text(message)
            .font(.callout)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 0)

      trailingAction
    }
    .padding(.vertical, 2)
  }

  /// Pause ⏸ while running, ▶ while paused, ✕ while queued, ↻+trash on failed, trash on done.
  @ViewBuilder
  private var trailingAction: some View {
    switch item.status.phase {
    case .running:
      Button {
        store.pause(item)
      } label: {
        Image(systemName: "pause.circle.fill")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.tertiary)
      .help("Pause")
    case .queued:
      Button {
        store.cancel(item)
      } label: {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.tertiary)
      .help("Cancel")
    case .paused:
      Button {
        store.resume(item)
      } label: {
        Image(systemName: "play.circle.fill")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.tint)
      .help("Resume")
    case .failed:
      HStack(spacing: 2) {
        Button {
          store.retry(item)
        } label: {
          Image(systemName: "arrow.clockwise.circle.fill")
        }
        .buttonStyle(.borderless)
        .help("Retry")
        trashButton
      }
    case .succeeded:
      trashButton
    }
  }

  private var trashButton: some View {
    Button {
      store.remove(item)
    } label: {
      Image(systemName: "trash")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.tertiary)
    .help("Remove from list")
  }

  @ViewBuilder
  private var stateIcon: some View {
    switch item.status.phase {
    case .queued:
      Image(systemName: "hourglass")
        .foregroundStyle(.secondary)
        .font(.title3)
    case .running:
      Image(systemName: "arrow.down.circle")
        .foregroundStyle(.tint)
        .font(.title3)
    case .paused:
      Image(systemName: "pause.circle")
        .foregroundStyle(.secondary)
        .font(.title3)
    case .succeeded:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.title3)
    case .failed:
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
        .font(.title3)
    }
  }

  private func liveRows(_ live: Live) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        ProgressView(value: live.progress)
        Text("\(Int((live.progress * 100).rounded()))%")
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(minWidth: 42, alignment: .trailing)
      }
      if let stats = statsLine(live) {
        Text(stats)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
  }

  private func statsLine(_ live: Live) -> String? {
    let parts = [live.speed, live.eta, live.sizeEstimate].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  @ViewBuilder
  private func doneRow(path: String?, size: Int64?) -> some View {
    if let path {
      HStack(spacing: 8) {
        Text(size.map { "\(fileName(path)) · \(byteFormat($0))" } ?? fileName(path))
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(path)
        Button("Open") { store.openFile(item) }
          .controlSize(.small)
          .buttonStyle(.link)
        Button("Show in Finder") { store.reveal(item) }
          .controlSize(.small)
          .buttonStyle(.link)
      }
    } else {
      Text("Already downloaded")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private func fileName(_ path: String) -> String {
    (path as NSString).lastPathComponent
  }
}
