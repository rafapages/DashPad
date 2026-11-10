// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// NoiseHandshake.swift - the encryption ESPHome's native API uses: the Noise protocol
// Noise_NNpsk0_25519_ChaChaPoly_SHA256, responder side, built on CryptoKit.
//
// "NNpsk0" means neither side has a long-term key pair; both prove they hold the same
// pre-shared key (the "encryption key" shown in Settings) and then agree fresh session keys
// with an ephemeral X25519 exchange:
//
//     -> psk, e        client: mixes in the key, sends its ephemeral public key
//     <- e, ee         device: sends its ephemeral public key, both sides do Diffie-Hellman
//
// After that each direction has its own ChaCha20-Poly1305 key. See https://noiseprotocol.org/noise.html

import CryptoKit
import Foundation

enum NoiseError: Error {
    /// The client's first message did not authenticate: it was made with a different key.
    case wrongKey
    case malformed
}

struct NoiseHandshake {
    private static let protocolName = Data("Noise_NNpsk0_25519_ChaChaPoly_SHA256".utf8)

    private var chainingKey: Data
    private var hash: Data
    private var key: SymmetricKey?
    private var nonce: UInt64 = 0
    private var remoteEphemeral: Curve25519.KeyAgreement.PublicKey?

    init(prologue: Data) {
        // The name is longer than a SHA-256 digest, so it is hashed rather than zero-padded.
        hash = Data(SHA256.hash(data: Self.protocolName))
        chainingKey = hash
        mixHash(prologue)
    }

    /// Reads `-> psk, e` plus its (empty) payload. Throws `.wrongKey` if the client's key differs.
    mutating func readClientMessage(_ message: Data, psk: Data) throws {
        let message = Data(message)
        guard message.count >= 32 + 16 else { throw NoiseError.malformed }

        mixKeyAndHash(psk)

        let ephemeral = message.prefix(32)
        guard let publicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral) else {
            throw NoiseError.malformed
        }
        remoteEphemeral = publicKey
        mixHash(ephemeral)
        mixKey(ephemeral) // psk handshakes also mix every ephemeral key into the chaining key

        _ = try decryptAndHash(Data(message.dropFirst(32)))
    }

    /// Writes `<- e, ee` plus an empty payload.
    mutating func writeServerMessage() throws -> Data {
        guard let remoteEphemeral else { throw NoiseError.malformed }
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = ephemeral.publicKey.rawRepresentation
        mixHash(publicKey)
        mixKey(publicKey)

        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: remoteEphemeral)
        mixKey(shared.withUnsafeBytes { Data($0) })

        return publicKey + (try encryptAndHash(Data()))
    }

    /// The two transport ciphers. The first key carries client-to-device traffic.
    func split() -> (receive: NoiseCipher, send: NoiseCipher) {
        let keys = hkdf(chainingKey, Data(), outputs: 2)
        return (NoiseCipher(key: keys[0]), NoiseCipher(key: keys[1]))
    }

    // MARK: - Symmetric state

    private mutating func mixHash(_ data: Data) {
        hash = Data(SHA256.hash(data: hash + data))
    }

    private mutating func mixKey(_ material: Data) {
        let out = hkdf(chainingKey, material, outputs: 2)
        chainingKey = out[0]
        key = SymmetricKey(data: out[1])
        nonce = 0
    }

    private mutating func mixKeyAndHash(_ material: Data) {
        let out = hkdf(chainingKey, material, outputs: 3)
        chainingKey = out[0]
        mixHash(out[1])
        key = SymmetricKey(data: out[2])
        nonce = 0
    }

    private mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
        guard let key else { throw NoiseError.malformed }
        let ciphertext = try NoiseCipher.seal(plaintext, key: key, nonce: nonce, authenticating: hash)
        nonce += 1
        mixHash(ciphertext)
        return ciphertext
    }

    private mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
        guard let key else { throw NoiseError.malformed }
        guard let plaintext = try? NoiseCipher.open(ciphertext, key: key, nonce: nonce, authenticating: hash) else {
            throw NoiseError.wrongKey
        }
        nonce += 1
        mixHash(ciphertext)
        return plaintext
    }

    /// Noise's HKDF: HMAC-SHA256 with the chaining key as salt, up to three 32-byte outputs.
    private func hkdf(_ chainingKey: Data, _ material: Data, outputs: Int) -> [Data] {
        func hmac(_ key: Data, _ data: Data) -> Data {
            Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
        }
        let tempKey = hmac(chainingKey, material)
        var result: [Data] = []
        var previous = Data()
        for i in 1...outputs {
            previous = hmac(tempKey, previous + [UInt8(i)])
            result.append(previous)
        }
        return result
    }
}

/// One direction of an established session: ChaCha20-Poly1305 with a counter nonce.
final class NoiseCipher {
    private let key: SymmetricKey
    private var nonce: UInt64 = 0

    init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        defer { nonce += 1 }
        return try Self.seal(plaintext, key: key, nonce: nonce, authenticating: Data())
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        defer { nonce += 1 }
        return try Self.open(ciphertext, key: key, nonce: nonce, authenticating: Data())
    }

    /// Noise's ChaChaPoly nonce: four zero bytes, then the counter as 64-bit little-endian.
    private static func nonceData(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: counter.littleEndian) { bytes.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: bytes)
    }

    /// Returns ciphertext followed by the 16-byte tag.
    static func seal(_ plaintext: Data, key: SymmetricKey, nonce: UInt64, authenticating: Data) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonceData(nonce), authenticating: authenticating)
        return box.ciphertext + box.tag
    }

    static func open(_ sealed: Data, key: SymmetricKey, nonce: UInt64, authenticating: Data) throws -> Data {
        let sealed = Data(sealed)
        guard sealed.count >= 16 else { throw NoiseError.malformed }
        let box = try ChaChaPoly.SealedBox(nonce: nonceData(nonce),
                                           ciphertext: sealed.dropLast(16),
                                           tag: sealed.suffix(16))
        return try ChaChaPoly.open(box, using: key, authenticating: authenticating)
    }
}
