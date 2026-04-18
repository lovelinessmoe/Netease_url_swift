import Foundation

enum MusicService {
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154"

    // MARK: - Get Song URL

    static func getSongUrl(id: Int, level: String, cookies: [String: String]) async throws -> SongUrlData {
        let apiUrl = "https://interface3.music.163.com/eapi/song/enhance/player/url/v1"
        let apiPath = "/api/song/enhance/player/url/v1"

        let requestId = Int.random(in: 20_000_000..<30_000_000)
        let config: [String: Any] = [
            "os": "pc", "appver": "", "osver": "",
            "deviceId": "pyncm!", "requestId": "\(requestId)"
        ]

        var payload: [String: Any] = [
            "ids": [id],
            "level": level,
            "encodeType": "flac",
            "header": (try? JSONSerialization.data(withJSONObject: config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        ]
        if level == "sky" { payload["immerseType"] = "c51" }

        let payloadJson = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let digest = CryptoUtil.md5Hex("nobody\(apiPath)use\(payloadJson)md5forencrypt")
        let params = "\(apiPath)-36cd479b6b5-\(payloadJson)-36cd479b6b5-\(digest)"
        let encrypted = CryptoUtil.aes128ECBEncrypt(params)

        var request = URLRequest(url: URL(string: apiUrl)!)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("", forHTTPHeaderField: "Referer")
        request.setValue(CookieUtil.cookieHeader(from: cookies), forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "params=\(encrypted)".data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SongUrlResponse.self, from: data)

        guard let urlData = response.data.first, urlData.url != nil else {
            throw NSError(domain: "MusicService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取音乐URL，可能需要会员或版权限制"])
        }
        return urlData
    }

    // MARK: - Get Song Detail

    static func getSongDetail(id: Int) async throws -> SongDetail {
        let url = URL(string: "https://interface3.music.163.com/api/v3/song/detail")!
        let body = "c=\(encodeURIComponent("[{\"id\":\(id),\"v\":0}]"))"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SongDetailResponse.self, from: data)
        guard let song = response.songs.first else {
            throw NSError(domain: "MusicService", code: -2, userInfo: [NSLocalizedDescriptionKey: "歌曲信息获取失败"])
        }
        return song
    }

    // MARK: - Get Lyric

    static func getLyric(id: Int, cookies: [String: String]) async throws -> LyricResponse {
        let url = URL(string: "https://interface3.music.163.com/api/song/lyric")!
        let body = "id=\(id)&cp=false&tv=0&lv=0&rv=0&kv=0&yv=0&ytv=0&yrv=0"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(CookieUtil.cookieHeader(from: cookies), forHTTPHeaderField: "Cookie")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(LyricResponse.self, from: data)
    }

    // MARK: - Parse IDs from URL or raw IDs

    static func parseIds(from input: String) async throws -> [Int] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Playlist URL
        if trimmed.contains("playlist") || trimmed.contains("album") {
            return try await fetchPlaylistIds(from: trimmed)
        }

        // Single song URL
        if trimmed.contains("song") || trimmed.contains("id=") {
            if let id = extractId(from: trimmed) { return [id] }
        }

        // Raw IDs (comma separated)
        let ids = trimmed.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if !ids.isEmpty { return ids }

        // Single numeric ID
        if let id = Int(trimmed) { return [id] }

        throw NSError(domain: "MusicService", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法解析输入，请输入歌曲ID或链接"])
    }

    private static func extractId(from urlString: String) -> Int? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idItem = components.queryItems?.first(where: { $0.name == "id" }),
              let idStr = idItem.value else { return nil }
        return Int(idStr)
    }

    private static func fetchPlaylistIds(from urlString: String) async throws -> [Int] {
        guard let id = extractId(from: urlString) else {
            throw NSError(domain: "MusicService", code: -4, userInfo: [NSLocalizedDescriptionKey: "无法解析歌单ID"])
        }

        let isAlbum = urlString.contains("album")
        let apiUrl = isAlbum
            ? "https://music.163.com/api/album/\(id)"
            : "https://music.163.com/api/v6/playlist/detail?id=\(id)"

        let (data, _) = try await URLSession.shared.data(from: URL(string: apiUrl)!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        if isAlbum {
            let songs = (json["songs"] as? [[String: Any]]) ?? []
            return songs.compactMap { $0["id"] as? Int }
        } else {
            let playlist = json["playlist"] as? [String: Any]
            // trackIds contains all song IDs; tracks only has partial detail
            let trackIds = (playlist?["trackIds"] as? [[String: Any]]) ?? []
            return trackIds.compactMap { $0["id"] as? Int }
        }
    }

    private static func encodeURIComponent(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}
