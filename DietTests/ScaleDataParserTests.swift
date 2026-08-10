import Foundation
import XCTest
@testable import Diet

final class ScaleDataParserTests: XCTestCase {
    func testParsesStableXiaomiWeightAdvertisement() throws {
        // 0x3070 / 200 = 62.0 kg; kg + stable flags.
        let data = Data([0x22, 0x70, 0x30, 0, 0, 0, 0, 0, 0, 0])
        let reading = try XCTUnwrap(ScaleDataParser.parseXiaomiWeightAdvertisement(data))

        XCTAssertEqual(reading.weightKg, 62, accuracy: 0.001)
        XCTAssertTrue(reading.isStable)
    }

    func testParsesStandardMetricWeightMeasurement() throws {
        // 12,400 * 0.005 kg = 62 kg.
        let data = Data([0x00, 0x70, 0x30])
        let reading = try XCTUnwrap(ScaleDataParser.parseStandardWeightMeasurement(data))

        XCTAssertEqual(reading.weightKg, 62, accuracy: 0.001)
        XCTAssertTrue(reading.isStable)
    }

    func testRejectsImpossibleWeight() {
        XCTAssertNil(ScaleDataParser.parseStandardWeightMeasurement(Data([0, 1, 0])))
    }
}
