import XCTest
@testable import ytd

final class ParseTests: XCTestCase {
  func testProgressFullStats() {
    XCTAssertEqual(
      YtdlpRunner.parse("PROG: 42.5%| 3.22MiB/s| 00:12| ~120.34MiB"),
      .progress(Live(progress: 0.425, speed: "3.22MiB/s", eta: "00:12", sizeEstimate: "~120.34MiB")))
  }

  func testProgressPlaceholdersBecomeNil() {
    // First lines before speed/eta/size are known (observed live 2026-11-07).
    XCTAssertEqual(
      YtdlpRunner.parse("PROG: 20.0%| Unknown B/s|Unknown|       N/A"),
      .progress(Live(progress: 0.2, speed: nil, eta: nil, sizeEstimate: nil)))
  }

  func testProgressPostProcessingNA() {
    // Post-processing lines report NA (observed live 2026-11-07).
    XCTAssertEqual(
      YtdlpRunner.parse("PROG:100.0%|212.86KiB/s|NA|NA"),
      .progress(Live(progress: 1, speed: "212.86KiB/s", eta: nil, sizeEstimate: nil)))
  }

  func testProgressBarePercentStillParses() {
    XCTAssertEqual(
      YtdlpRunner.parse("PROG: 42.5%"),
      .progress(Live(progress: 0.425, speed: nil, eta: nil, sizeEstimate: nil)))
  }

  func testProgressClamped() {
    XCTAssertEqual(
      YtdlpRunner.parse("PROG: 100.0%"),
      .progress(Live(progress: 1, speed: nil, eta: nil, sizeEstimate: nil)))
    XCTAssertEqual(
      YtdlpRunner.parse("PROG: 0.0%"),
      .progress(Live(progress: 0, speed: nil, eta: nil, sizeEstimate: nil)))
  }

  func testProgressGarbageIgnored() {
    XCTAssertNil(YtdlpRunner.parse("PROG: Unknown"))
  }

  func testTitleAndFile() {
    XCTAssertEqual(YtdlpRunner.parse("TITLE:Some Video Title"),
                   .title("Some Video Title"))
    XCTAssertEqual(YtdlpRunner.parse("FILE:/Users/x/Downloads/ytd/Some Video [abc].mp4"),
                   .filePath("/Users/x/Downloads/ytd/Some Video [abc].mp4"))
  }

  func testUnknownLineIgnored() {
    XCTAssertNil(YtdlpRunner.parse("[download] Destination: /tmp/x.mp4"))
    XCTAssertNil(YtdlpRunner.parse(""))
  }

  func testPrefixMustMatchExactly() {
    XCTAssertNil(YtdlpRunner.parse("PROGRESS: 50%"))
    XCTAssertNil(YtdlpRunner.parse("TITLE2:x"))
  }

  func testItemCodableRoundTrip() throws {
    let item = DownloadItem(
      id: UUID(), url: "https://x.example/v", audioOnly: true, quality: .q2160,
      title: "T",
      status: .downloading(Live(progress: 0.5, speed: "1MiB/s", eta: "00:10", sizeEstimate: "~10MiB")))
    let data = try JSONEncoder().encode([item])
    XCTAssertEqual(try JSONDecoder().decode([DownloadItem].self, from: data), [item])
  }
}
