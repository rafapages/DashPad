// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// ProtoWire.swift - just enough Protocol Buffers to speak the ESPHome native API: varints,
// length-delimited fields and 32-bit fixed fields. Hand-written so the app keeps no dependencies.
// Like proto3, the writer leaves out fields that hold their default value.

import Foundation

struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private mutating func tag(_ field: Int, wireType: UInt64) {
        varint(UInt64(field) << 3 | wireType)
    }

    mutating func string(_ field: Int, _ value: String) {
        guard !value.isEmpty else { return }
        bytes(field, Data(value.utf8))
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, wireType: 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func bool(_ field: Int, _ value: Bool) {
        guard value else { return }
        tag(field, wireType: 0)
        varint(1)
    }

    mutating func uint(_ field: Int, _ value: UInt32) {
        guard value != 0 else { return }
        tag(field, wireType: 0)
        varint(UInt64(value))
    }

    /// `int32`: negative values are sign-extended to 64 bits, as protobuf requires.
    mutating func int(_ field: Int, _ value: Int32) {
        guard value != 0 else { return }
        tag(field, wireType: 0)
        varint(UInt64(bitPattern: Int64(value)))
    }

    /// Always written: ESPHome uses `fixed32` for entity keys, which are never optional.
    mutating func fixed32(_ field: Int, _ value: UInt32) {
        tag(field, wireType: 5)
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func float(_ field: Int, _ value: Float) {
        fixed32(field, value.bitPattern)
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var writer = ProtoWriter()
        build(&writer)
        bytes(field, writer.data)
    }
}

enum ProtoValue {
    case varint(UInt64)
    case fixed32(UInt32)
    case fixed64(UInt64)
    case bytes(Data)

    var string: String? {
        if case .bytes(let data) = self { return String(data: data, encoding: .utf8) }
        return nil
    }
}

/// Walks the fields of one message. Stops (returns nil) at the end or at anything malformed.
struct ProtoReader {
    private let bytes: [UInt8]
    private var position = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    mutating func next() -> (field: Int, value: ProtoValue)? {
        guard position < bytes.count, let key = readVarint() else { return nil }
        let field = Int(key >> 3)
        switch key & 0x7 {
        case 0:
            guard let value = readVarint() else { return nil }
            return (field, .varint(value))
        case 1:
            guard let value = readFixed(8) else { return nil }
            return (field, .fixed64(value))
        case 2:
            guard let length = readVarint(), length <= UInt64(bytes.count - position) else { return nil }
            let start = position
            position += Int(length)
            return (field, .bytes(Data(bytes[start..<position])))
        case 5:
            guard let value = readFixed(4) else { return nil }
            return (field, .fixed32(UInt32(value)))
        default:
            return nil
        }
    }

    private mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while position < bytes.count, shift < 64 {
            let byte = bytes[position]
            position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    private mutating func readFixed(_ count: Int) -> UInt64? {
        guard bytes.count - position >= count else { return nil }
        var result: UInt64 = 0
        for i in 0..<count {
            result |= UInt64(bytes[position + i]) << UInt64(8 * i)
        }
        position += count
        return result
    }
}
