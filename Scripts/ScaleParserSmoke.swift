import Foundation

@main
enum ScaleParserSmoke {
    static func main() {
        verifyXiaomiWeightScale()
        verifyXiaomiBodyCompositionScale()
        verifyStandardScale()
        print("Scale parser smoke tests passed")
    }

    private static func verifyXiaomiWeightScale() {
        let packet = Data([0x22, 0x70, 0x30, 0, 0, 0, 0, 0, 0, 0])
        guard let reading = ScaleDataParser.parseXiaomiWeightAdvertisement(packet),
              reading.isStable,
              abs(reading.weightKg - 62) < 0.001
        else {
            fatalError("Failed to decode Xiaomi Weight Scale packet")
        }
    }

    private static func verifyXiaomiBodyCompositionScale() {
        let packet = Data([
            0x03, 0x26, 0xE3, 0x07, 0x04, 0x1E, 0x0B,
            0x32, 0x21, 0xD3, 0x01, 0x0E, 0x51
        ])
        guard let reading = ScaleDataParser.parseXiaomiBodyComposition(packet),
              reading.isStable,
              abs(reading.weightKg - 103.75) < 0.001
        else {
            fatalError("Failed to decode Xiaomi Body Composition Scale packet")
        }
    }

    private static func verifyStandardScale() {
        let packet = Data([0x00, 0x70, 0x30])
        guard let reading = ScaleDataParser.parseStandardWeightMeasurement(packet),
              abs(reading.weightKg - 62) < 0.001
        else {
            fatalError("Failed to decode standard Weight Measurement packet")
        }
    }
}
