import Foundation

struct ParsedScaleReading: Equatable {
    let weightKg: Double
    let isStable: Bool
}
enum ScaleDataParser {
    /// Xiaomi Mi Smart Scale advertisements carried by the Weight Scale service (0x181D).
    static func parseXiaomiWeightAdvertisement(_ data: Data) -> ParsedScaleReading? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3 else { return nil }

        let flags = bytes[0]
        let hasWeight = flags & 0x80 == 0
        let isStable = flags & 0x20 != 0
        guard hasWeight else { return nil }

        let raw = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        let weightKg: Double

        if flags & 0x04 != 0 {
            // Scale is displaying lb. Xiaomi sends hundredths of a pound.
            weightKg = Double(raw) / 100 * 0.453_592_37
        } else {
            // Xiaomi's kg and 斤 payloads both resolve to 0.005 kg.
            weightKg = Double(raw) / 200
        }

        return validated(weightKg: weightKg, isStable: isStable)
    }

    /// Xiaomi Body Composition Scale packets are 13 bytes:
    /// control, unit/status, timestamp, impedance, then weight.
    static func parseXiaomiBodyComposition(_ data: Data) -> ParsedScaleReading? {
        let bytes = [UInt8](data)
        guard bytes.count >= 13 else { return nil }

        let status = bytes[1]
        let isStable = status & 0x20 != 0
        let hasWeight = status & 0x80 == 0
        guard hasWeight else { return nil }

        let raw = UInt16(bytes[11]) | UInt16(bytes[12]) << 8
        let weightKg = Double(raw) / 200
        return validated(weightKg: weightKg, isStable: isStable)
    }

    /// Bluetooth SIG Weight Measurement characteristic (0x2A9D).
    static func parseStandardWeightMeasurement(_ data: Data) -> ParsedScaleReading? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3 else { return nil }

        let flags = bytes[0]
        let raw = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        let usesImperialUnits = flags & 0x01 != 0
        let weightKg = usesImperialUnits
            ? Double(raw) * 0.01 * 0.453_592_37
            : Double(raw) * 0.005

        return validated(weightKg: weightKg, isStable: true)
    }

    /// Bluetooth SIG Body Composition Measurement characteristic (0x2A9C).
    /// Weight is optional and appears after all fields preceding bit 10.
    static func parseStandardBodyComposition(_ data: Data) -> ParsedScaleReading? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }

        let flags = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        guard flags & (1 << 10) != 0 else { return nil }

        var index = 4 // flags + mandatory body-fat percentage
        if flags & (1 << 1) != 0 { index += 7 } // timestamp
        if flags & (1 << 2) != 0 { index += 1 } // user ID
        if flags & (1 << 3) != 0 { index += 2 } // basal metabolism
        if flags & (1 << 4) != 0 { index += 2 } // muscle percentage
        if flags & (1 << 5) != 0 { index += 2 } // muscle mass
        if flags & (1 << 6) != 0 { index += 2 } // fat-free mass
        if flags & (1 << 7) != 0 { index += 2 } // soft lean mass
        if flags & (1 << 8) != 0 { index += 2 } // body water mass
        if flags & (1 << 9) != 0 { index += 2 } // impedance

        guard bytes.indices.contains(index + 1) else { return nil }
        let raw = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
        let usesImperialUnits = flags & 0x01 != 0
        let weightKg = usesImperialUnits
            ? Double(raw) * 0.01 * 0.453_592_37
            : Double(raw) * 0.005

        return validated(weightKg: weightKg, isStable: true)
    }

    private static func validated(weightKg: Double, isStable: Bool) -> ParsedScaleReading? {
        guard weightKg >= 10, weightKg <= 350, weightKg.isFinite else { return nil }
        return ParsedScaleReading(weightKg: weightKg, isStable: isStable)
    }
}
