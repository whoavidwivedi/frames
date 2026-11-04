import Foundation

/// Fast zero-allocation EBML Variable-Length Integer (VINT) parser.
/// In Matroska/EBML, integers are encoded with a variable number of bytes (1 to 8),
/// where the number of leading zero bits in the first byte indicates total byte length.
nonisolated public struct EBMLVint: Sendable, Equatable {
    /// The decoded integer value (with length descriptor bit masked out if parseValue was true).
    public let value: UInt64
    /// Total byte length of this VINT (1 to 8 bytes).
    public let length: Int
    /// Raw unmasked value (useful for Element IDs).
    public let rawValue: UInt64

    public init(value: UInt64, length: Int, rawValue: UInt64) {
        self.value = value
        self.length = length
        self.rawValue = rawValue
    }

    /// Parses an EBML Element ID from buffer at offset.
    /// In Element IDs, the length descriptor bit is preserved as part of the ID.
    @inline(__always)
    public static func parseElementID(from buffer: UnsafeRawBufferPointer, offset: Int) -> EBMLVint? {
        guard offset < buffer.count else { return nil }
        let firstByte = buffer[offset]
        guard firstByte != 0 else { return nil }

        let leadingZeros = firstByte.leadingZeroBitCount
        let length = leadingZeros + 1
        guard length <= 8, offset + length <= buffer.count else { return nil }

        var raw: UInt64 = 0
        for i in 0..<length {
            raw = (raw << 8) | UInt64(buffer[offset + i])
        }

        return EBMLVint(value: raw, length: length, rawValue: raw)
    }

    /// Parses an EBML Data Size / Value from buffer at offset.
    /// In Data Sizes, the length descriptor bit is masked out.
    @inline(__always)
    public static func parseDataSize(from buffer: UnsafeRawBufferPointer, offset: Int) -> EBMLVint? {
        guard offset < buffer.count else { return nil }
        let firstByte = buffer[offset]
        guard firstByte != 0 else { return nil }

        let leadingZeros = firstByte.leadingZeroBitCount
        let length = leadingZeros + 1
        guard length <= 8, offset + length <= buffer.count else { return nil }

        // Mask out the length descriptor bit
        let mask: UInt8 = (1 << (7 - leadingZeros)) - 1
        var val = UInt64(firstByte & mask)
        var raw = UInt64(firstByte)

        for i in 1..<length {
            let b = buffer[offset + i]
            val = (val << 8) | UInt64(b)
            raw = (raw << 8) | UInt64(b)
        }

        return EBMLVint(value: val, length: length, rawValue: raw)
    }

    /// Parses an unsigned big-endian integer of specific byte length (1 to 8 bytes).
    @inline(__always)
    public static func parseUInt(from buffer: UnsafeRawBufferPointer, offset: Int, length: Int) -> UInt64? {
        guard length >= 0, length <= 8, offset + length <= buffer.count else { return nil }
        if length == 0 { return 0 }

        var result: UInt64 = 0
        for i in 0..<length {
            result = (result << 8) | UInt64(buffer[offset + i])
        }
        return result
    }

    /// Parses a signed big-endian integer of specific byte length (two's complement).
    @inline(__always)
    public static func parseInt(from buffer: UnsafeRawBufferPointer, offset: Int, length: Int) -> Int64? {
        guard let uVal = parseUInt(from: buffer, offset: offset, length: length) else { return nil }
        if length == 0 { return 0 }

        let bits = length * 8
        if bits >= 64 {
            return Int64(bitPattern: uVal)
        }
        let signBit: UInt64 = UInt64(1) << (bits - 1)
        if (uVal & signBit) != 0 {
            // Negative: sign-extend to 64 bits
            let mask: UInt64 = ~((UInt64(1) << bits) - 1)
            return Int64(bitPattern: uVal | mask)
        } else {
            return Int64(uVal)
        }
    }

    /// Parses an IEEE 754 floating point number (4-byte float or 8-byte double).
    @inline(__always)
    public static func parseFloat(from buffer: UnsafeRawBufferPointer, offset: Int, length: Int) -> Double? {
        guard offset + length <= buffer.count else { return nil }
        if length == 4 {
            guard let u = parseUInt(from: buffer, offset: offset, length: 4) else { return nil }
            let f = Float(bitPattern: UInt32(u))
            return Double(f)
        } else if length == 8 {
            guard let u = parseUInt(from: buffer, offset: offset, length: 8) else { return nil }
            return Double(bitPattern: u)
        }
        return nil
    }

    /// Parses a UTF-8 string of specific length.
    @inline(__always)
    public static func parseString(from buffer: UnsafeRawBufferPointer, offset: Int, length: Int) -> String? {
        guard offset + length <= buffer.count else { return nil }
        if length == 0 { return "" }
        let slice = buffer.baseAddress!.advanced(by: offset)
        // Trim null terminators if present
        var actualLength = length
        while actualLength > 0 && slice.advanced(by: actualLength - 1).load(as: UInt8.self) == 0 {
            actualLength -= 1
        }
        return String(bytes: UnsafeRawBufferPointer(start: slice, count: actualLength), encoding: .utf8)
    }

    /// Indicates if a data size indicates "unknown / stream" length (all bits 1).
    public var isUnknownSize: Bool {
        let maxVal = (UInt64(1) << (length * 7)) - 1
        return value == maxVal
    }
}
