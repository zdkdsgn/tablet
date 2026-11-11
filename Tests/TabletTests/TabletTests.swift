import XCTest
@testable import Tablet

/// Real reports from the Intuos Pro M (PTH-651) as logged in ~/Library/Logs/Tablet-hid.log.
final class WacomReportTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] { hex.split(separator: " ").map { UInt8($0, radix: 16)! } }

    func testPenGeneralReport() {
        guard case .pen(let s) = WacomReport.decode(bytes("02 e0 27 c8 1f 3e 00 2a 27 56"), enhanced: true) else {
            return XCTFail("not a pen report")
        }
        XCTAssertEqual(s.mm.x, 20369.0 / 200, accuracy: 0.001)
        XCTAssertEqual(s.mm.y, 15996.0 / 200, accuracy: 0.001)
        XCTAssertEqual(s.pressure, 0)
        XCTAssertEqual(s.tiltX, 20)
        XCTAssertEqual(s.tiltY, -25)
        XCTAssertEqual(s.distance, 21.0 / 63, accuracy: 0.0001)
    }

    func testPenEnterGivesToolAndSerial() {
        // Grip Pen 0x10802, serial 4780E947 (the user's pen)
        XCTAssertEqual(WacomReport.decode(bytes("02 c0 80 24 78 0e 94 71 00 00"), enhanced: true),
                       .penEnter(tool: 0x10802, serial: 0x4780E947))
    }

    func testPenExit() {
        XCTAssertEqual(WacomReport.decode(bytes("02 80 00 00 00 00 00 00 00 00"), enhanced: true), .penExit)
    }

    func testPadReport() {
        guard case .pad(let ring, let button, let keys, let touch, let flags) =
                WacomReport.decode(bytes("03 80 00 00 08 08 00 00 00 00"), enhanced: true) else { return XCTFail() }
        XCTAssertNil(ring)
        XCTAssertFalse(button)
        XCTAssertEqual(keys.firstIndex(of: true), 3)
        XCTAssertEqual(touch?.firstIndex(of: true), 3)
        XCTAssertEqual(flags, 0x80)
        if case .pad(let ring, _, _, _, _) = WacomReport.decode(bytes("03 80 a3 00 00 00"), enhanced: true) {
            XCTAssertEqual(ring, 0x23)   // finger on the ring at position 35
        } else { XCTFail() }
    }

    func testStatusBatteryAndSwitch() {
        let full = WacomReport.status(bytes("c0 00 00 01 10 b7 e7 5b 1f 03"))
        XCTAssertEqual(full, .init(wireless: true, level: 100, charging: false, touchSwitchOn: true))
        let low = WacomReport.status(bytes("c0 00 00 01 10 b7 e7 5b 03 03"))
        XCTAssertEqual(low?.level, 9)
        XCTAssertEqual(WacomReport.status(bytes("c0 00 00 01 10 b7 e7 5b 9f 01"))?.charging, true)
        XCTAssertEqual(WacomReport.status(bytes("c0 00 00 01 10 b7 e7 5b 5f 03"))?.touchSwitchOn, false)
        XCTAssertEqual(WacomReport.status(bytes("c0 00 00 01 10 b7 e7 5b 1f 01"))?.wireless, false)
    }

    func testBatteryFlickerIsNotLogged() {
        XCTAssertEqual(WacomReport.statusSignature(bytes("c0 00 00 01 10 b7 e7 5b 1f 03")),
                       WacomReport.statusSignature(bytes("c0 00 00 01 10 b7 e7 5b 03 03")))
        XCTAssertNotEqual(WacomReport.statusSignature(bytes("c0 00 00 01 10 b7 e7 5b 1f 03")),
                          WacomReport.statusSignature(bytes("c0 00 00 01 10 b7 e7 5b 5f 03")))
    }

    func testTouchChunks() {
        var r = [UInt8](repeating: 0, count: 64)
        r[0] = 0x0C; r[1] = 2   // not 0x02 / 0x03 (pen, pad)
        // finger id 2 → slot 0 at x = 0x123, y = 0x456, size 10 × 12
        r[2] = 2; r[3] = 0x01; r[4] = 0x12; r[5] = 0x45; r[6] = 0x36; r[7] = 10; r[8] = 12
        // finger id 3 → slot 1 lifted
        r[10] = 3; r[11] = 0x20
        guard case .touch(.chunks(let f)) = WacomReport.decode(r, enhanced: true) else { return XCTFail() }
        XCTAssertEqual(f.count, 2)
        XCTAssertEqual(f[0], .init(id: 0, up: false, x: 0x123, y: 0x456, w: 10, h: 12))
        XCTAssertTrue(f[1].up)
        r[2] = 0x81; r[3] = 0x01; r[4] = 0x00
        XCTAssertEqual(WacomReport.decode(r, enhanced: true), .touch(.stillDown(mask: 1)))
    }
}

final class LogicTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(OTDStore.isNewer("1.3.1", than: "1.3"))
        XCTAssertTrue(OTDStore.isNewer("1.10", than: "1.9"))
        XCTAssertFalse(OTDStore.isNewer("1.3", than: "1.3.0"))
        XCTAssertFalse(OTDStore.isNewer("1.2.9", than: "1.3"))
    }

    func testPressureCurve() {
        XCTAssertEqual(PenFilters.curve(0.5, gamma: 1, maxInput: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PenFilters.curve(0.5, gamma: 1, maxInput: 0.5), 1, accuracy: 1e-9)
        XCTAssertLessThan(PenFilters.curve(0.5, gamma: 1.8, maxInput: 1), 0.5)
        XCTAssertGreaterThan(PenFilters.curve(0.5, gamma: 0.55, maxInput: 1), 0.5)
        XCTAssertEqual(PenFilters.curve(2, gamma: 1, maxInput: 1), 1)
    }

    func testTapClicksAboveThreshold() {
        let t = Tap(time: Date(), duration: 0.1, peak: 0.2, x: 0, y: 0, threshold: 0.05)
        XCTAssertTrue(t.clicked)
        XCTAssertFalse(Tap(time: Date(), duration: 0.1, peak: 0.04, x: 0, y: 0, threshold: 0.05).clicked)
    }
}

@MainActor
final class StrokeFileTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tablet-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    func testStrokesRoundTrip() {
        let url = dir.appendingPathComponent("day.strokes")
        let a = Stroke(time: Date(timeIntervalSince1970: 1_800_000_000), points: [SIMD3(1, 2, 0.5), SIMD3(3, 4, 0.75)])
        let b = Stroke(time: Date(timeIntervalSince1970: 1_800_000_060), points: [SIMD3(5, 6, 1), SIMD3(7, 8, 0.25), SIMD3(9, 9, 0.1)])
        StrokeLog.append(a, to: url)
        StrokeLog.append(b, to: url)
        let back = StrokeLog.read(url)
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[1].points, b.points)
        XCTAssertEqual(back[0].time, a.time)
    }

    func testTapsRoundTrip() {
        let url = dir.appendingPathComponent("day.taps")
        let t = Tap(time: Date(timeIntervalSince1970: 1_800_000_000.5), duration: 0.12, peak: 0.34, x: 100, y: 50, threshold: 0.05)
        StrokeLog.append(t, to: url)
        StrokeLog.append(t, to: url)
        XCTAssertEqual(StrokeLog.readTaps(url), [t, t])
    }

    func testTruncatedFileIsSafe() throws {
        let url = dir.appendingPathComponent("broken.taps")
        try Data([1, 2, 3, 4, 5]).write(to: url)
        XCTAssertEqual(StrokeLog.readTaps(url), [])
    }
}

/// Every Czech UI text in the source has an English translation.
final class TranslationTests: XCTestCase {
    func testCzechStringsAreTranslated() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let strings = try String(contentsOf: root.appendingPathComponent("Resources/en.lproj/Localizable.strings"), encoding: .utf8)
        let keyRe = try NSRegularExpression(pattern: #"^"((?:[^"\\]|\\.)*)" = "#, options: .anchorsMatchLines)
        let keys = Set(keyRe.matches(in: strings, range: NSRange(strings.startIndex..., in: strings)).map {
            String(strings[Range($0.range(at: 1), in: strings)!]).replacingOccurrences(of: #"\""#, with: "\"")
        })
        // UI calls whose first argument is a literal shown to the user
        let callRe = try NSRegularExpression(pattern: #"\b(?:L|Text|Button|Toggle|Label|Picker|Section|SettingRow\(title: L)\("((?:[^"\\]|\\.)*)""#)
        let czech = CharacterSet(charactersIn: "ěščřžýáíéůúťďňóĚŠČŘŽÝÁÍÉŮÚŤĎŇÓ")
        var missing: [String] = []
        var checked = 0
        let files = FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            for m in callRe.matches(in: src, range: NSRange(src.startIndex..., in: src)) {
                let s = String(src[Range(m.range(at: 1), in: src)!])
                guard s.rangeOfCharacter(from: czech) != nil, !s.contains("\\(") else { continue }
                checked += 1
                if !keys.contains(s.replacingOccurrences(of: #"\""#, with: "\"")) { missing.append("\(url.lastPathComponent): \(s)") }
            }
        }
        XCTAssertGreaterThan(checked, 300, "the scan found too few texts – is the pattern still right?")
        XCTAssert(missing.isEmpty, "Missing English for:\n" + Set(missing).sorted().joined(separator: "\n"))
    }
}
