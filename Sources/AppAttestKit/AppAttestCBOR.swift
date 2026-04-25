//
//  AppAttestCBOR.swift
//  AppAttestDemo
//

import Foundation

nonisolated enum AppAttestCBORValue: Sendable {
    case unsigned(UInt64)
    case negative(Int64)
    case bytes(Data)
    case text(String)
    case array([AppAttestCBORValue])
    case map([AppAttestCBORPair])
    case boolean(Bool)
    case null
}

nonisolated struct AppAttestCBORDecoder: Sendable {
    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    mutating func decode() throws -> AppAttestCBORValue {
        try readValue()
    }

    private mutating func readValue() throws -> AppAttestCBORValue {
        let initial = try readByte()
        let majorType = initial >> 5
        let additionalInfo = initial & 0x1f

        switch majorType {
        case 0:
            return .unsigned(try readArgument(additionalInfo))
        case 1:
            let value = try readArgument(additionalInfo)
            guard value <= UInt64(Int64.max) else {
                throw AppAttestCBORError.integerOutOfRange
            }
            return .negative(-1 - Int64(value))
        case 2:
            let count = try checkedCount(try readArgument(additionalInfo))
            return .bytes(try readData(count: count))
        case 3:
            let count = try checkedCount(try readArgument(additionalInfo))
            let data = try readData(count: count)
            guard let string = String(data: data, encoding: .utf8) else {
                throw AppAttestCBORError.invalidUTF8
            }
            return .text(string)
        case 4:
            let count = try checkedCount(try readArgument(additionalInfo))
            var values: [AppAttestCBORValue] = []
            values.reserveCapacity(count)
            for _ in 0..<count {
                values.append(try readValue())
            }
            return .array(values)
        case 5:
            let count = try checkedCount(try readArgument(additionalInfo))
            var map: [AppAttestCBORPair] = []
            map.reserveCapacity(count)
            for _ in 0..<count {
                let key = try readValue()
                map.append(AppAttestCBORPair(key: key, value: try readValue()))
            }
            return .map(map)
        case 7:
            switch additionalInfo {
            case 20:
                return .boolean(false)
            case 21:
                return .boolean(true)
            case 22:
                return .null
            default:
                throw AppAttestCBORError.unsupportedSimpleValue
            }
        default:
            throw AppAttestCBORError.unsupportedMajorType
        }
    }

    private mutating func readArgument(_ additionalInfo: UInt8) throws -> UInt64 {
        switch additionalInfo {
        case 0...23:
            return UInt64(additionalInfo)
        case 24:
            return UInt64(try readByte())
        case 25:
            return UInt64(try readUInt16())
        case 26:
            return UInt64(try readUInt32())
        case 27:
            return try readUInt64()
        default:
            throw AppAttestCBORError.indefiniteLengthUnsupported
        }
    }

    private mutating func readByte() throws -> UInt8 {
        guard offset < bytes.count else {
            throw AppAttestCBORError.truncatedData
        }
        defer { offset += 1 }
        return bytes[offset]
    }

    private mutating func readUInt16() throws -> UInt16 {
        let data = try readRawBytes(count: 2)
        return data.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    private mutating func readUInt32() throws -> UInt32 {
        let data = try readRawBytes(count: 4)
        return data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private mutating func readUInt64() throws -> UInt64 {
        let data = try readRawBytes(count: 8)
        return data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    private mutating func readData(count: Int) throws -> Data {
        Data(try readRawBytes(count: count))
    }

    private mutating func readRawBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else {
            throw AppAttestCBORError.truncatedData
        }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    private func checkedCount(_ value: UInt64) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw AppAttestCBORError.integerOutOfRange
        }
        return Int(value)
    }
}

nonisolated struct AppAttestCBORPair: Sendable {
    let key: AppAttestCBORValue
    let value: AppAttestCBORValue
}

nonisolated extension Array where Element == AppAttestCBORPair {
    subscript(text key: String) -> AppAttestCBORValue? {
        first { pair in
            if case .text(key) = pair.key {
                return true
            }
            return false
        }?.value
    }
}

nonisolated enum AppAttestCBORError: Error, LocalizedError, Sendable {
    case truncatedData
    case invalidUTF8
    case integerOutOfRange
    case indefiniteLengthUnsupported
    case unsupportedMajorType
    case unsupportedSimpleValue

    var errorDescription: String? {
        switch self {
        case .truncatedData:
            return "The CBOR data ended unexpectedly."
        case .invalidUTF8:
            return "The CBOR text string is not valid UTF-8."
        case .integerOutOfRange:
            return "The CBOR integer is too large."
        case .indefiniteLengthUnsupported:
            return "Indefinite-length CBOR values are not supported."
        case .unsupportedMajorType:
            return "The CBOR value uses an unsupported major type."
        case .unsupportedSimpleValue:
            return "The CBOR value uses an unsupported simple value."
        }
    }
}
