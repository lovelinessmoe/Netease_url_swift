import Foundation
import CommonCrypto

enum CryptoUtil {
    static let aesKey = "e82ckenh8dichen8".data(using: .utf8)!

    static func md5Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_MD5($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func aes128ECBEncrypt(_ plaintext: String) -> String {
        let data = Data(plaintext.utf8)
        let keyBytes = [UInt8](aesKey)
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesEncrypted = 0

        let status = data.withUnsafeBytes { dataPtr in
            CCCrypt(
                CCOperation(kCCEncrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                keyBytes, keyBytes.count,
                nil,
                dataPtr.baseAddress, data.count,
                &buffer, bufferSize,
                &numBytesEncrypted
            )
        }
        guard status == kCCSuccess else { return "" }
        return buffer.prefix(numBytesEncrypted).map { String(format: "%02x", $0) }.joined()
    }
}
