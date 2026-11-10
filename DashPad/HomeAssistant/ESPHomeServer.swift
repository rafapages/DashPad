// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// ESPHomeServer.swift - makes this iPad look like an ESPHome device to Home Assistant.
// It listens on TCP 6053, announces itself over Bonjour (_esphomelib._tcp), and speaks the
// ESPHome native API with Noise encryption. It knows nothing about DashPad: it is given a
// device description, a list of entities and actions, and a stream of state values, and it
// reports commands back. HomeAssistantLink connects it to the app. See docs/home-assistant-link.md.

import Foundation
import Network

// MARK: - What the device exposes

struct ESPHomeDevice: Equatable {
    /// Hostname-style name (a-z, 0-9, hyphens). Home Assistant derives entity IDs from it.
    var name: String
    /// The name people see in Home Assistant.
    var friendlyName: String
    /// Twelve lowercase hex digits. Home Assistant uses it as the device's unique ID.
    var macAddress: String
    var model: String
    var appVersion: String
}

struct ESPHomeEntity {
    enum Kind {
        case binarySensor(deviceClass: String)
        case sensor(unit: String, deviceClass: String)
        case textSensor
        case select(options: [String])
        case button
    }

    /// Stable identifier, also the entity's object ID in Home Assistant.
    let id: String
    let name: String
    var icon = ""
    /// Diagnostic entities are listed apart from the main ones on the device page.
    var diagnostic = false
    let kind: Kind

    var key: UInt32 { ESPHomeServer.key(for: id) }
}

enum ESPHomeState: Equatable {
    case bool(Bool)
    case number(Float)
    case text(String)
}

/// A device action, which Home Assistant offers as `esphome.<device name>_<action name>`.
struct ESPHomeAction {
    enum ArgumentType: UInt32 {
        case bool = 0, int = 1, float = 2, string = 3
    }

    let name: String
    let arguments: [(name: String, type: ArgumentType)]

    var key: UInt32 { ESPHomeServer.key(for: "action:" + name) }
}

enum ESPHomeArgument: Equatable {
    case bool(Bool)
    case int(Int)
    case float(Float)
    case string(String)
}

enum ESPHomeCommand {
    case select(entityID: String, option: String)
    case press(entityID: String)
    case action(name: String, arguments: [ESPHomeArgument])
}

// MARK: - Server

final class ESPHomeServer {
    static let port: UInt16 = 6053
    /// The ESPHome release whose behaviour this server follows. Home Assistant shows it next
    /// to the DashPad version and uses it to decide which protocol features to expect.
    static let esphomeVersion = "2026.1.0"

    enum Status: Equatable {
        case stopped
        case starting
        case listening(clients: Int)
        case failed(String)
    }

    var onCommand: ((ESPHomeCommand) -> Void)?
    var onStatusChange: ((Status) -> Void)?
    private(set) var status: Status = .stopped {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    private let device: ESPHomeDevice
    private let key: Data
    private let entities: [ESPHomeEntity]
    private let actions: [ESPHomeAction]
    private var states: [String: ESPHomeState] = [:]

    private var listener: NWListener?
    private var connections: [ESPHomeConnection] = []
    private var housekeeping: Timer?
    private var retry: Timer?
    private var running = false

    /// More than Home Assistant ever opens (one, plus one more while it reconnects).
    private static let maxConnections = 4
    /// Home Assistant pings every 20 seconds; a client this quiet has gone away.
    private static let idleLimit: TimeInterval = 150

    /// Everything runs on the main queue: traffic is a few small messages a minute, and it
    /// keeps the server on the same thread as the app state it reports.
    init(device: ESPHomeDevice, key: Data, entities: [ESPHomeEntity], actions: [ESPHomeAction]) {
        self.device = device
        self.key = key
        self.entities = entities
        self.actions = actions
    }

    static func key(for id: String) -> UInt32 {
        // FNV-1, the hash ESPHome itself uses to turn an object ID into an entity key.
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash = hash &* 16_777_619
            hash ^= UInt32(byte)
        }
        return hash
    }

    // MARK: Lifecycle

    func start() {
        running = true
        openListener()
        housekeeping = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.dropSilentConnections()
        }
    }

    func stop() {
        running = false
        housekeeping?.invalidate()
        retry?.invalidate()
        listener?.cancel()
        listener = nil
        connections.forEach { $0.close(notify: false) }
        connections.removeAll()
        status = .stopped
    }

    /// Reopens the listener if it is not up, e.g. after the app was in the background.
    func ensureListening() {
        guard running, listener == nil else { return }
        openListener()
    }

    private func openListener() {
        retry?.invalidate()
        status = .starting
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)

            // What Home Assistant's discovery reads. `mac` is required; `api_encryption` tells
            // it to ask for the key.
            var txt = NWTXTRecord()
            txt["mac"] = device.macAddress
            txt["friendly_name"] = device.friendlyName
            txt["version"] = Self.esphomeVersion
            txt["api_encryption"] = "Noise_NNpsk0_25519_ChaChaPoly_SHA256"
            txt["project_name"] = "DashPad.\(device.model)"
            txt["project_version"] = device.appVersion
            listener.service = NWListener.Service(name: device.name, type: "_esphomelib._tcp",
                                                  domain: nil, txtRecord: txt)

            listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            listenerFailed(error.localizedDescription)
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            status = .listening(clients: readyClientCount)
        case .failed(let error):
            listenerFailed(error.localizedDescription)
        case .waiting(let error):
            // Usually Local Network access is off, or there is no network yet.
            status = .failed(error.localizedDescription)
        default:
            break
        }
    }

    private func listenerFailed(_ reason: String) {
        listener?.cancel()
        listener = nil
        status = .failed(reason)
        guard running else { return }
        retry = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.ensureListening()
        }
    }

    // MARK: Connections

    private var readyClientCount: Int { connections.filter(\.isReady).count }

    private func accept(_ nwConnection: NWConnection) {
        guard connections.count < Self.maxConnections else {
            nwConnection.cancel()
            return
        }
        let connection = ESPHomeConnection(nwConnection, key: key,
                                           name: device.name, macAddress: device.macAddress)
        connection.onMessage = { [weak self, weak connection] type, payload in
            guard let self, let connection else { return }
            self.handle(type, payload, from: connection)
        }
        connection.onReady = { [weak self] in self?.clientsChanged() }
        connection.onClose = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.connections.removeAll { $0 === connection }
            self.clientsChanged()
        }
        connections.append(connection)
        connection.start()
    }

    private func clientsChanged() {
        if case .listening = status { status = .listening(clients: readyClientCount) }
    }

    private func dropSilentConnections() {
        let cutoff = Date().addingTimeInterval(-Self.idleLimit)
        connections.filter { $0.lastActivity < cutoff }.forEach { $0.close() }
    }

    // MARK: State

    /// Records an entity's current value (nil: unknown) and tells subscribed clients if it changed.
    func setState(_ state: ESPHomeState?, for entityID: String) {
        guard states[entityID] != state else { return }
        states[entityID] = state
        guard let entity = entities.first(where: { $0.id == entityID }),
              let message = stateMessage(for: entity) else { return }
        for connection in connections where connection.subscribed {
            connection.send(message.type, message.payload)
        }
    }

    private func stateMessage(for entity: ESPHomeEntity) -> (type: UInt16, payload: Data)? {
        var w = ProtoWriter()
        w.fixed32(1, entity.key)
        let state = states[entity.id]
        let type: UInt16

        switch entity.kind {
        case .binarySensor:
            type = MessageType.binarySensorState
            if case .bool(let value) = state { w.bool(2, value) } else { w.bool(3, true) }
        case .sensor:
            type = MessageType.sensorState
            if case .number(let value) = state { w.float(2, value) } else { w.bool(3, true) }
        case .textSensor:
            type = MessageType.textSensorState
            if case .text(let value) = state { w.string(2, value) } else { w.bool(3, true) }
        case .select:
            type = MessageType.selectState
            if case .text(let value) = state { w.string(2, value) } else { w.bool(3, true) }
        case .button:
            return nil // Buttons have nothing to report.
        }
        return (type, w.data)
    }

    // MARK: Messages

    /// Message numbers from ESPHome's api.proto (the `option (id)` of each message).
    private enum MessageType {
        static let helloRequest: UInt16 = 1
        static let helloResponse: UInt16 = 2
        static let disconnectRequest: UInt16 = 5
        static let disconnectResponse: UInt16 = 6
        static let pingRequest: UInt16 = 7
        static let pingResponse: UInt16 = 8
        static let deviceInfoRequest: UInt16 = 9
        static let deviceInfoResponse: UInt16 = 10
        static let listEntitiesRequest: UInt16 = 11
        static let listBinarySensor: UInt16 = 12
        static let listSensor: UInt16 = 16
        static let listTextSensor: UInt16 = 18
        static let listEntitiesDone: UInt16 = 19
        static let subscribeStates: UInt16 = 20
        static let binarySensorState: UInt16 = 21
        static let sensorState: UInt16 = 25
        static let textSensorState: UInt16 = 27
        static let listAction: UInt16 = 41
        static let executeAction: UInt16 = 42
        static let listSelect: UInt16 = 52
        static let selectState: UInt16 = 53
        static let selectCommand: UInt16 = 54
        static let listButton: UInt16 = 61
        static let buttonCommand: UInt16 = 62
    }

    private func handle(_ type: UInt16, _ payload: Data, from connection: ESPHomeConnection) {
        switch type {
        case MessageType.helloRequest:
            var w = ProtoWriter()
            w.uint(1, 1)   // API version 1.10: the newest whose features this server implements
            w.uint(2, 10)
            w.string(3, "DashPad \(device.appVersion)")
            w.string(4, device.name)
            connection.send(MessageType.helloResponse, w.data)

        case MessageType.pingRequest:
            connection.send(MessageType.pingResponse, Data())

        case MessageType.disconnectRequest:
            connection.send(MessageType.disconnectResponse, Data(), thenClose: true)

        case MessageType.deviceInfoRequest:
            connection.send(MessageType.deviceInfoResponse, deviceInfo())

        case MessageType.listEntitiesRequest:
            for entity in entities {
                let message = listMessage(for: entity)
                connection.send(message.type, message.payload)
            }
            for action in actions {
                connection.send(MessageType.listAction, listMessage(for: action))
            }
            connection.send(MessageType.listEntitiesDone, Data())

        case MessageType.subscribeStates:
            connection.subscribed = true
            for entity in entities {
                if let message = stateMessage(for: entity) {
                    connection.send(message.type, message.payload)
                }
            }

        case MessageType.selectCommand:
            var reader = ProtoReader(payload)
            var key: UInt32 = 0
            var option = ""
            while let (field, value) = reader.next() {
                if field == 1, case .fixed32(let k) = value { key = k }
                if field == 2, let s = value.string { option = s }
            }
            guard let entity = entities.first(where: { $0.key == key }),
                  case .select(let options) = entity.kind, options.contains(option) else { return }
            onCommand?(.select(entityID: entity.id, option: option))

        case MessageType.buttonCommand:
            var reader = ProtoReader(payload)
            while let (field, value) = reader.next() {
                guard field == 1, case .fixed32(let key) = value,
                      let entity = entities.first(where: { $0.key == key }),
                      case .button = entity.kind else { continue }
                onCommand?(.press(entityID: entity.id))
            }

        case MessageType.executeAction:
            executeAction(payload)

        default:
            // Log, time and Home Assistant state subscriptions, and anything newer than this
            // server: a real device without those features ignores them too.
            break
        }
    }

    private func deviceInfo() -> Data {
        var w = ProtoWriter()
        w.string(2, device.name)
        w.string(3, stride(from: 0, to: 12, by: 2).map { i -> String in
            let start = device.macAddress.index(device.macAddress.startIndex, offsetBy: i)
            return device.macAddress[start..<device.macAddress.index(start, offsetBy: 2)].uppercased()
        }.joined(separator: ":"))
        w.string(4, Self.esphomeVersion)
        w.string(6, device.model)
        // Home Assistant splits this at the dot into manufacturer and model.
        w.string(8, "DashPad.\(device.model)")
        w.string(9, device.appVersion)
        w.string(12, "DashPad")
        w.string(13, device.friendlyName)
        w.bool(19, true) // api_encryption_supported
        return w.data
    }

    private func listMessage(for entity: ESPHomeEntity) -> (type: UInt16, payload: Data) {
        var w = ProtoWriter()
        w.string(1, entity.id)
        w.fixed32(2, entity.key)
        w.string(3, entity.name)
        let category: UInt32 = entity.diagnostic ? 2 : 0

        // The field numbers differ per entity type; they are the ones in api.proto.
        switch entity.kind {
        case .binarySensor(let deviceClass):
            w.string(5, deviceClass)
            w.string(8, entity.icon)
            w.uint(9, category)
            return (MessageType.listBinarySensor, w.data)
        case .sensor(let unit, let deviceClass):
            w.string(5, entity.icon)
            w.string(6, unit)
            w.string(9, deviceClass)
            w.uint(10, 1) // state_class: measurement
            w.uint(13, category)
            return (MessageType.listSensor, w.data)
        case .textSensor:
            w.string(5, entity.icon)
            w.uint(7, category)
            return (MessageType.listTextSensor, w.data)
        case .select(let options):
            w.string(5, entity.icon)
            options.forEach { w.bytes(6, Data($0.utf8)) }
            w.uint(8, category)
            return (MessageType.listSelect, w.data)
        case .button:
            w.string(5, entity.icon)
            w.uint(7, category)
            return (MessageType.listButton, w.data)
        }
    }

    private func listMessage(for action: ESPHomeAction) -> Data {
        var w = ProtoWriter()
        w.string(1, action.name)
        w.fixed32(2, action.key)
        for argument in action.arguments {
            w.message(3) { a in
                a.string(1, argument.name)
                a.uint(2, argument.type.rawValue)
            }
        }
        return w.data
    }

    private func executeAction(_ payload: Data) {
        var reader = ProtoReader(payload)
        var key: UInt32 = 0
        var rawArguments: [Data] = []
        while let (field, value) = reader.next() {
            if field == 1, case .fixed32(let k) = value { key = k }
            if field == 2, case .bytes(let data) = value { rawArguments.append(data) }
        }
        guard let action = actions.first(where: { $0.key == key }),
              rawArguments.count == action.arguments.count else { return }

        // Arguments arrive in declared order; each carries only the field for its type, and a
        // default value (false, 0, "") is not sent at all.
        let arguments = zip(action.arguments, rawArguments).map { declared, raw -> ESPHomeArgument in
            var reader = ProtoReader(raw)
            var result: ESPHomeArgument
            switch declared.type {
            case .bool: result = .bool(false)
            case .int: result = .int(0)
            case .float: result = .float(0)
            case .string: result = .string("")
            }
            while let (field, value) = reader.next() {
                switch (declared.type, field, value) {
                case (.bool, 1, .varint(let v)): result = .bool(v != 0)
                case (.int, 2, .varint(let v)): result = .int(Int(Int32(truncatingIfNeeded: v)))
                case (.int, 5, .varint(let v)): // sint32, zigzag-encoded
                    result = .int(Int(Int32(truncatingIfNeeded: v >> 1) ^ -Int32(truncatingIfNeeded: v & 1)))
                case (.float, 3, .fixed32(let v)): result = .float(Float(bitPattern: v))
                case (.string, 4, _): result = .string(value.string ?? "")
                default: break
                }
            }
            return result
        }
        onCommand?(.action(name: action.name, arguments: arguments))
    }
}

// MARK: - One client connection

/// Frames and encrypts one TCP connection. Every frame is `0x01`, a 16-bit big-endian length,
/// then that many bytes. The first frames carry the Noise handshake; after it, each frame is
/// one encrypted message: 16-bit type, 16-bit length, protobuf payload.
private final class ESPHomeConnection {
    private enum Phase { case clientHello, handshake, ready, rejecting, closed }

    var onMessage: ((UInt16, Data) -> Void)?
    var onReady: (() -> Void)?
    var onClose: (() -> Void)?
    /// Set once the client asks for state updates.
    var subscribed = false
    private(set) var lastActivity = Date()
    var isReady: Bool { phase == .ready }

    private let connection: NWConnection
    private let key: Data
    private let name: String
    private let macAddress: String
    private var phase = Phase.clientHello
    private var buffer: [UInt8] = []
    private var receiveCipher: NoiseCipher?
    private var sendCipher: NoiseCipher?

    init(_ connection: NWConnection, key: Data, name: String, macAddress: String) {
        self.connection = connection
        self.key = key
        self.name = name
        self.macAddress = macAddress
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func close(notify: Bool = true) {
        guard phase != .closed else { return }
        phase = .closed
        connection.stateUpdateHandler = nil
        connection.cancel()
        if notify { onClose?() }
    }

    /// `thenClose` hangs up once the message is on the wire, not before.
    func send(_ type: UInt16, _ payload: Data, thenClose: Bool = false) {
        guard phase == .ready, let sendCipher, payload.count <= 0xFFFF - 4 - 16 else { return }
        var message = Data([UInt8(type >> 8), UInt8(type & 0xFF),
                            UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)])
        message.append(payload)
        guard let encrypted = try? sendCipher.encrypt(message) else { return close() }
        sendFrame(encrypted, thenClose: thenClose)
    }

    private func sendFrame(_ body: Data, thenClose: Bool = false) {
        var frame = Data([0x01, UInt8(body.count >> 8), UInt8(body.count & 0xFF)])
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { [weak self] _ in
            if thenClose { self?.close() }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self, self.phase != .closed else { return }
            if let data, !data.isEmpty {
                self.lastActivity = Date()
                self.buffer.append(contentsOf: data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                self.close()
            } else if self.phase != .closed {
                self.receive()
            }
        }
    }

    private func processBuffer() {
        while phase != .closed, phase != .rejecting, buffer.count >= 3 {
            guard buffer[0] == 0x01 else {
                // 0x00 is an unencrypted client. This reply is how a real device says
                // "encryption required", which makes Home Assistant ask for the key.
                reject("Bad indicator byte")
                return
            }
            let length = Int(buffer[1]) << 8 | Int(buffer[2])
            guard buffer.count >= 3 + length else { return }
            let frame = Data(buffer[3..<(3 + length)])
            buffer.removeFirst(3 + length)
            handleFrame(frame)
        }
    }

    private func handleFrame(_ frame: Data) {
        switch phase {
        case .clientHello:
            // The client's hello carries nothing we need. Answer with the chosen protocol (1),
            // then our name and MAC address, each null-terminated.
            var hello = Data([0x01])
            hello.append(Data(name.utf8)); hello.append(0)
            hello.append(Data(macAddress.utf8)); hello.append(0)
            sendFrame(hello)
            phase = .handshake

        case .handshake:
            guard frame.first == 0x00 else { return reject("Bad handshake packet len") }
            var handshake = NoiseHandshake(prologue: Data("NoiseAPIInit".utf8) + [0, 0])
            do {
                try handshake.readClientMessage(Data(frame.dropFirst()), psk: key)
                let reply = try handshake.writeServerMessage()
                sendFrame(Data([0x00]) + reply)
                (receiveCipher, sendCipher) = handshake.split()
                phase = .ready
                onReady?()
            } catch {
                // The exact text Home Assistant recognises as "wrong encryption key".
                reject("Handshake MAC failure")
            }

        case .ready:
            guard let receiveCipher, let message = try? receiveCipher.decrypt(frame), message.count >= 4 else {
                return close()
            }
            let bytes = [UInt8](message)
            let type = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            let length = Int(bytes[2]) << 8 | Int(bytes[3])
            guard bytes.count >= 4 + length else { return close() }
            onMessage?(type, Data(bytes[4..<(4 + length)]))

        case .rejecting, .closed:
            break
        }
    }

    /// Sends a handshake failure (`0x01` then the reason) and hangs up once it is on the wire.
    private func reject(_ reason: String) {
        phase = .rejecting
        sendFrame(Data([0x01]) + Data(reason.utf8), thenClose: true)
    }
}
