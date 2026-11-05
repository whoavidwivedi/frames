//
//  NALParser.swift
//  frames
//
//  High-performance zero-copy NAL unit and codec parameter set parser
//  for H.264 (avcC/Annex-B) and HEVC/H.265 (hvcC/Annex-B).
//

import Foundation
import CoreMedia
import VideoToolbox

nonisolated public enum NALParser {
    
    // MARK: - AVC / H.264 Parameter Extraction
    
    /// Parses H.264 SPS and PPS parameter sets from an AVCDecoderConfigurationRecord (avcC box).
    public static func parseAVCDecoderConfigurationRecord(_ data: Data) -> (sps: [Data], pps: [Data], nalLengthSize: Int)? {
        guard data.count >= 7 else { return nil }
        
        return data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self)
            guard let base = ptr.baseAddress else { return nil }
            
            // Byte 0: configurationVersion (must be 1)
            guard base[0] == 1 else { return nil }
            
            // Byte 4: 0xFC | (nalLengthSizeMinusOne & 0x03)
            let nalLengthSize = Int(base[4] & 0x03) + 1
            
            // Byte 5: 0xE0 | (numOfSequenceParameterSets & 0x1F)
            let numSPS = Int(base[5] & 0x1F)
            var offset = 6
            var spsList: [Data] = []
            
            for _ in 0..<numSPS {
                guard offset + 2 <= data.count else { return nil }
                let spsLen = Int(UInt16(base[offset]) << 8 | UInt16(base[offset + 1]))
                offset += 2
                guard offset + spsLen <= data.count else { return nil }
                let spsData = Data(bytes: base + offset, count: spsLen)
                spsList.append(spsData)
                offset += spsLen
            }
            
            guard offset < data.count else { return nil }
            let numPPS = Int(base[offset])
            offset += 1
            var ppsList: [Data] = []
            
            for _ in 0..<numPPS {
                guard offset + 2 <= data.count else { return nil }
                let ppsLen = Int(UInt16(base[offset]) << 8 | UInt16(base[offset + 1]))
                offset += 2
                guard offset + ppsLen <= data.count else { return nil }
                let ppsData = Data(bytes: base + offset, count: ppsLen)
                ppsList.append(ppsData)
                offset += ppsLen
            }
            
            return (sps: spsList, pps: ppsList, nalLengthSize: nalLengthSize)
        }
    }
    
    // MARK: - HEVC / H.265 Parameter Extraction
    
    /// Parses HEVC VPS, SPS, and PPS parameter sets from an HEVCDecoderConfigurationRecord (hvcC box).
    public static func parseHEVCDecoderConfigurationRecord(_ data: Data) -> (vps: [Data], sps: [Data], pps: [Data], nalLengthSize: Int)? {
        guard data.count >= 23 else { return nil }
        
        return data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self)
            guard let base = ptr.baseAddress else { return nil }
            
            // Byte 0: configurationVersion (must be 1)
            guard base[0] == 1 else { return nil }
            
            // Byte 21: 0xFC | (lengthSizeMinusOne & 0x03)
            let nalLengthSize = Int(base[21] & 0x03) + 1
            
            // Byte 22: numOfArrays
            let numArrays = Int(base[22])
            var offset = 23
            
            var vpsList: [Data] = []
            var spsList: [Data] = []
            var ppsList: [Data] = []
            
            for _ in 0..<numArrays {
                guard offset + 3 <= data.count else { break }
                let nalType = base[offset] & 0x3F
                let numNalus = Int(UInt16(base[offset + 1]) << 8 | UInt16(base[offset + 2]))
                offset += 3
                
                for _ in 0..<numNalus {
                    guard offset + 2 <= data.count else { break }
                    let nalLen = Int(UInt16(base[offset]) << 8 | UInt16(base[offset + 1]))
                    offset += 2
                    guard offset + nalLen <= data.count else { break }
                    let nalData = Data(bytes: base + offset, count: nalLen)
                    offset += nalLen
                    
                    switch nalType {
                    case 32: // VPS
                        vpsList.append(nalData)
                    case 33: // SPS
                        spsList.append(nalData)
                    case 34: // PPS
                        ppsList.append(nalData)
                    default:
                        break
                    }
                }
            }
            
            return (vps: vpsList, sps: spsList, pps: ppsList, nalLengthSize: nalLengthSize)
        }
    }
    
    // MARK: - Annex-B Parameter Scanner (Fallback for raw streams)
    
    /// Determines whether the packet data starts with an Annex-B 3 or 4 byte start code.
    public static func isAnnexB(_ data: Data) -> Bool {
        let count = data.count
        guard count >= 4 else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            if base[0] == 0 && base[1] == 0 && base[2] == 0 && base[3] == 1 {
                // In AVCC, a 4-byte length prefix of 1 would mean only 1 payload byte (total 5 bytes).
                // Normal video frames are larger than 5 bytes, so count != 5 identifies Annex-B.
                return count != 5
            }
            if base[0] == 0 && base[1] == 0 && base[2] == 1 {
                // Disambiguate against AVCC packets where length prefix is in range 256..511
                let avccCandidateLen = (Int(base[2]) << 8) | Int(base[3])
                if count == 4 + avccCandidateLen {
                    return false
                }
                let forbiddenZeroBit = (base[3] & 0x80) == 0
                let nalType = base[3] & 0x1F
                return forbiddenZeroBit && nalType >= 1 && nalType <= 31
            }
            return false
        }
    }
    
    /// Translates an Annex-B stream into 4-byte big-endian length prefixed NAL units for VideoToolbox.
    public static func convertAnnexBToAVCC(_ data: Data) -> Data {
        let count = data.count
        guard count >= 4 else { return data }

        return data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return data }
            var startIndices: [Int] = []
            var i = 0

            while i < count - 2 {
                if base[i] == 0 && base[i + 1] == 0 {
                    if base[i + 2] == 1 {
                        startIndices.append(i + 3)
                        i += 3
                        continue
                    } else if i < count - 3 && base[i + 2] == 0 && base[i + 3] == 1 {
                        startIndices.append(i + 4)
                        i += 4
                        continue
                    }
                }
                i += 1
            }

            guard !startIndices.isEmpty else { return data }
        
        var output = Data()
            output.reserveCapacity(count + (startIndices.count * 4))

            for idx in 0..<startIndices.count {
                let start = startIndices[idx]
                let end: Int
                if idx + 1 < startIndices.count {
                    var prev = startIndices[idx + 1] - 3
                    while prev > start && base[prev - 1] == 0 {
                        prev -= 1
                    }
                    end = prev
                } else {
                    end = count
                }

                if end > start {
                    let len = end - start
                    var lengthBE = UInt32(len).bigEndian
                    withUnsafeBytes(of: &lengthBE) { output.append(contentsOf: $0) }
                    output.append(base + start, count: len)
                }
        }
        return output
    }
    }
    
    /// Extracts individual NAL units separated by 3 or 4-byte start codes (0x000001 or 0x00000001).
    public static func extractAnnexBNALUnits(from data: Data) -> [Data] {
        var nals: [Data] = []
        let count = data.count
        guard count >= 4 else { return nals }
        
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var startIndices: [Int] = []
            var i = 0
            
            while i < count - 2 {
                if base[i] == 0 && base[i + 1] == 0 {
                    if base[i + 2] == 1 {
                        startIndices.append(i + 3)
                        i += 3
                        continue
                    } else if i < count - 3 && base[i + 2] == 0 && base[i + 3] == 1 {
                        startIndices.append(i + 4)
                        i += 4
                        continue
                    }
                }
                i += 1
            }
            
            for idx in 0..<startIndices.count {
                let start = startIndices[idx]
                let end: Int
                if idx + 1 < startIndices.count {
                    // Back up past all leading zero bytes before start code prefix
                    var prev = startIndices[idx + 1] - 3
                    while prev > start && base[prev - 1] == 0 {
                        prev -= 1
                    }
                    end = prev
                } else {
                    end = count
                }
                
                if end > start {
                    nals.append(Data(bytes: base + start, count: end - start))
                }
            }
        }
        
        return nals
    }
    
    // MARK: - Format Description Factories
    
    /// Executes a closure with guaranteed valid pointer lifetimes for all parameter sets.
    private static func withParameterPointers(
        sets: [Data],
        _ body: ([UnsafePointer<UInt8>], [Int]) -> OSStatus
    ) -> OSStatus {
        func recurse(index: Int, ptrs: inout [UnsafePointer<UInt8>], sizes: inout [Int]) -> OSStatus {
            if index == sets.count {
                return body(ptrs, sizes)
            }
            return sets[index].withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                ptrs.append(base)
                sizes.append(sets[index].count)
                let res = recurse(index: index + 1, ptrs: &ptrs, sizes: &sizes)
                _ = ptrs.popLast()
                _ = sizes.popLast()
                return res
            }
        }
        var ptrs: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []
        ptrs.reserveCapacity(sets.count)
        sizes.reserveCapacity(sets.count)
        return recurse(index: 0, ptrs: &ptrs, sizes: &sizes)
    }

    /// Creates a CMVideoFormatDescription for H.264 from SPS & PPS parameter sets.
    public static func createH264FormatDescription(sps: [Data], pps: [Data]) -> CMVideoFormatDescription? {
        let allSets = sps + pps
        guard !allSets.isEmpty else { return nil }
        
        var formatDesc: CMVideoFormatDescription?
        let status = withParameterPointers(sets: allSets) { ptrs, sizes in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: ptrs.count,
                parameterSetPointers: ptrs,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &formatDesc
            )
        }
        
        return status == noErr ? formatDesc : nil
    }
    
    /// Creates a CMVideoFormatDescription for HEVC from VPS, SPS, & PPS parameter sets.
    public static func createHEVCFormatDescription(vps: [Data], sps: [Data], pps: [Data]) -> CMVideoFormatDescription? {
        let allSets = vps + sps + pps
        guard !allSets.isEmpty else { return nil }
        
        var formatDesc: CMVideoFormatDescription?
        let status = withParameterPointers(sets: allSets) { ptrs, sizes in
            CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: ptrs.count,
                parameterSetPointers: ptrs,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &formatDesc
            )
        }
        
        return status == noErr ? formatDesc : nil
    }
}
