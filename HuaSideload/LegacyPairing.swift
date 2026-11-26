// Swift port of Gadgetbridge's "normal mode" pairing for Huawei watches without HiChain (support type 0),
// e.g. the first-generation Watch GT / GT Sport and older bands.
// Derived from HuaweiCrypto.java, DeviceConfig.java, GetAuthRequest.java, GetBondParamsRequest.java and
// GetBondRequest.java. Gadgetbridge copyright (C) 2024 Damien Gaignon, Martin.JM; AGPL-3.0-or-later.
// Upstream: https://codeberg.org/Freeyourgadget/Gadgetbridge
import Foundation

enum LegacyPairing {
    static let authCommand: UInt8 = 0x13
    static let bondParamsCommand: UInt8 = 0x0F
    static let bondCommand: UInt8 = 0x0E

    // HuaweiCrypto.SECRET_KEY_* (v1 for auth version 1, v23 otherwise)
    private static let secretKey1v1: [UInt8] = [0x6F, 0x75, 0x6A, 0x79, 0x6D, 0x77, 0x71, 0x34, 0x63, 0x6C, 0x76, 0x39, 0x33, 0x37, 0x38, 0x79]
    private static let secretKey2v1: [UInt8] = [0x62, 0x31, 0x30, 0x6A, 0x67, 0x66, 0x64, 0x39, 0x79, 0x37, 0x76, 0x73, 0x75, 0x64, 0x61, 0x39]
    private static let secretKey1v23: [UInt8] = [0x55, 0x53, 0x86, 0xFC, 0x63, 0x20, 0x07, 0xAA, 0x86, 0x49, 0x35, 0x22, 0xB8, 0x6A, 0xE2, 0x5C]
    private static let secretKey2v23: [UInt8] = [0x33, 0x07, 0x9B, 0xC5, 0x7A, 0x88, 0x6D, 0x3C, 0xF5, 0x61, 0x37, 0x09, 0x6F, 0x22, 0x80, 0x00]

    struct Authentication {
        let request: HuaweiTLV
        let expectedResponse: [UInt8]
    }

    // GetAuthRequest without a PIN: HuaweiCrypto.computeDigest over serverNonce + clientNonce
    static func authentication(authVersion: Int, serverNonce: [UInt8], clientNonce: [UInt8]) throws -> Authentication {
        guard serverNonce.count == 16, clientNonce.count == 16 else {
            throw HuaweiAuthError.unexpected("Legacy pairing: missing 16-byte server nonce")
        }
        let nonce = serverNonce + clientNonce
        let challengeMessage: [UInt8] = authVersion == 4 ? [0x04, 0x00] : [0x01, 0x00]
        let challenge = digest(message: challengeMessage, nonce: nonce, authVersion: authVersion)
        let response = digest(message: [0x01, 0x10], nonce: nonce, authVersion: authVersion)
        let version = UInt16(truncatingIfNeeded: authVersion)
        return Authentication(
            request: HuaweiTLV().with(0x01, Array(challenge.prefix(32)))
                .with(0x02, [UInt8(version >> 8), UInt8(version & 0xFF)] + clientNonce),
            expectedResponse: Array(response.prefix(32)))
    }

    private static func digest(message: [UInt8], nonce: [UInt8], authVersion: Int) -> [UInt8] {
        let first = HCrypto.hmac(key: PinCode.digestSecret(authVersion: authVersion) + message, nonce)
        return HCrypto.hmac(key: first, nonce) + first
    }

    // HuaweiCrypto.createSecretKey: the key that wraps the bonding key, derived from the WATCH's Bluetooth MAC
    static func wrappingKey(watchMAC: String, authVersion: Int) -> [UInt8] {
        let key1 = authVersion == 1 ? secretKey1v1 : secretKey1v23
        let key2 = authVersion == 1 ? secretKey2v1 : secretKey2v23
        let macKey = Array((watchMAC.replacingOccurrences(of: ":", with: "").uppercased() + "0000").utf8)
        let mixed = (0..<16).map { UInt8(truncatingIfNeeded: (Int(key1[$0]) << 4) ^ Int(key2[$0])) }
        let mixedHash = HCrypto.sha256(mixed)
        let final = (0..<16).map { UInt8(truncatingIfNeeded: (Int(mixedHash[$0]) >> 6) ^ Int(macKey[$0])) }
        return Array(HCrypto.sha256(final).prefix(16))
    }

    // ParamsProvider.getIv for support types other than 4: 12 random bytes + the incremented counter
    static func nextIV(counter: inout UInt32) -> [UInt8] {
        counter = counter == UInt32.max ? 1 : counter + 1
        return HCrypto.random(12) + [UInt8].bigEndian(counter)
    }

    static func bond(serial: [UInt8], secret: [UInt8], wrappingKey: [UInt8], iv: [UInt8], useGCM: Bool) throws -> HuaweiTLV {
        guard secret.count == 16, wrappingKey.count == 16, iv.count == 16 else {
            throw HuaweiAuthError.unexpected("Legacy pairing: invalid bonding key/IV")
        }
        let wrapped = useGCM ? try HCrypto.gcmSeal(secret, key: wrappingKey, nonce: iv)
                             : try HCrypto.cbcEncrypt(secret, key: wrappingKey, iv: iv)
        return HuaweiTLV().with(0x01).with(0x03, [0x00]).with(0x05, serial).with(0x06, wrapped).with(0x07, iv)
    }

    // "9C:56:36:D0:CC:B8", "9c5636d0ccb8" or "9C-56-…" -> "9C:56:36:D0:CC:B8"; nil when it isn't a MAC
    static func normalizedMAC(_ text: String) -> String? {
        let hex = text.uppercased().filter { $0.isHexDigit }
        guard hex.count == 12, text.filter({ !$0.isHexDigit && !":- ".contains($0) }).isEmpty else { return nil }
        return stride(from: 0, to: 12, by: 2).map { i -> String in
            let start = hex.index(hex.startIndex, offsetBy: i)
            return String(hex[start..<hex.index(start, offsetBy: 2)])
        }.joined(separator: ":")
    }

    // Huawei names end in the MAC's last three hex digits ("HUAWEI WATCH GT 3 SE-CB8" for …:CC:B8).
    // Looks for a MAC in the advertisement's manufacturer data that matches that suffix, in either byte order.
    static func macFromAdvertisement(_ data: [UInt8], name: String?) -> String? {
        guard data.count >= 6 else { return nil }
        let suffix = name.flatMap { n -> String? in
            guard let dash = n.lastIndex(of: "-") else { return nil }
            let s = n[n.index(after: dash)...].uppercased()
            return s.count == 3 && s.allSatisfy(\.isHexDigit) ? s : nil
        }
        guard let suffix else { return nil }
        for start in 0...(data.count - 6) {
            let window = Array(data[start..<start + 6])
            for bytes in [window, window.reversed()] {
                let mac = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
                if mac.replacingOccurrences(of: ":", with: "").hasSuffix(suffix) { return mac }
            }
        }
        return nil
    }
}
