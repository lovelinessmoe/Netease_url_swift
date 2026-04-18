import Foundation

enum CookieUtil {
    private static let key = "netease_cookie"

    static func readCookie() throws -> String {
        guard let cookie = UserDefaults.standard.string(forKey: key), !cookie.isEmpty else {
            throw NSError(domain: "CookieUtil", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cookie 未设置"])
        }
        return cookie
    }

    static func saveCookie(_ text: String) {
        UserDefaults.standard.set(text.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
    }

    static func hasCookie() -> Bool {
        !(UserDefaults.standard.string(forKey: key) ?? "").isEmpty
    }

    static func parseCookie(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        text.split(separator: ";").forEach { part in
            let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1])
            }
        }
        return result
    }

    static func cookieHeader(from dict: [String: String]) -> String {
        let base = ["os": "pc", "appver": "", "osver": "", "deviceId": "pyncm!"]
        return base.merging(dict) { _, new in new }
            .map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}
