import Foundation

enum DownloadService {

    // MARK: - Download single song to destination folder

    static func downloadSong(_ song: SongInfo, to folder: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let audioData = try await downloadData(from: song.url, progress: progress)
        let ext = fileExtension(from: song.url)
        let safeName = sanitize("\(song.artist) - \(song.name)")
        let destURL = folder.appendingPathComponent("\(safeName).\(ext)")

        try audioData.write(to: destURL)

        if ext == "mp3" {
            var coverData: Data? = nil
            if let picUrl = song.picUrl {
                coverData = try? await downloadData(from: picUrl, progress: { _ in })
            }
            writeID3Tags(to: destURL, song: song, coverData: coverData)
        }

        return destURL
    }

    // MARK: - Build SongInfo from API

    nonisolated static func buildSongInfo(urlData: SongUrlData, detail: SongDetail, lyric: LyricResponse) -> SongInfo {
        let rawUrl = urlData.url ?? ""
        let httpsUrl = rawUrl.replacingOccurrences(of: "http://", with: "https://")
        let combinedLyric = combineLyrics(
            original: lyric.lrc?.lyric ?? "",
            translated: lyric.tlyric?.lyric ?? ""
        )
        return SongInfo(
            id: detail.id,
            name: detail.name,
            artist: detail.ar.map(\.name).joined(separator: "/"),
            album: detail.al.name,
            picUrl: detail.al.picUrl,
            url: httpsUrl,
            level: levelDisplayName(urlData.level),
            size: formatSize(urlData.size),
            lyric: combinedLyric.isEmpty ? lyric.lrc?.lyric : combinedLyric,
            tlyric: lyric.tlyric?.lyric
        )
    }

    // MARK: - Private helpers

    private static func downloadData(from urlString: String, progress: @escaping (Double) -> Void) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "DownloadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效URL"])
        }
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = ProgressDelegate(progress: progress, continuation: continuation)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            session.dataTask(with: url).resume()
        }
    }

    private static func fileExtension(from urlString: String) -> String {
        let path = urlString.split(separator: "?").first.map(String.init) ?? urlString
        let ext = (path as NSString).pathExtension.lowercased()
        return ["mp3", "flac"].contains(ext) ? ext : "mp3"
    }

    private static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: illegal).joined(separator: "_")
    }

    // MARK: - ID3 Tag writing (MP3)

    private static func writeID3Tags(to fileURL: URL, song: SongInfo, coverData: Data?) {
        guard var data = try? Data(contentsOf: fileURL) else { return }

        // Remove existing ID3 tag
        if data.count > 10, data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 {
            let size = id3Size(data)
            if size < data.count { data = data.subdata(in: size..<data.count) }
        }

        var frames = Data()
        frames.append(id3TextFrame("TIT2", text: song.name))
        frames.append(id3TextFrame("TPE1", text: song.artist))
        frames.append(id3TextFrame("TALB", text: song.album))
        if let lyric = song.lyric, !lyric.isEmpty {
            frames.append(id3LyricFrame(lyric))
        }
        if let cover = coverData {
            frames.append(id3CoverFrame(cover))
        }

        var tag = Data()
        tag.append(contentsOf: [0x49, 0x44, 0x33, 0x03, 0x00, 0x00]) // ID3v2.3 header
        tag.append(id3SyncSafeSize(frames.count))
        tag.append(frames)

        try? (tag + data).write(to: fileURL)
    }

    private static func id3Size(_ data: Data) -> Int {
        let b0 = Int(data[6]) << 21
        let b1 = Int(data[7]) << 14
        let b2 = Int(data[8]) << 7
        let b3 = Int(data[9])
        return 10 + b0 + b1 + b2 + b3
    }

    private static func id3SyncSafeSize(_ size: Int) -> Data {
        Data([
            UInt8((size >> 21) & 0x7F),
            UInt8((size >> 14) & 0x7F),
            UInt8((size >> 7) & 0x7F),
            UInt8(size & 0x7F)
        ])
    }

    private static func id3FrameSize(_ size: Int) -> Data {
        Data([
            UInt8((size >> 24) & 0xFF),
            UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF),
            UInt8(size & 0xFF)
        ])
    }

    private static func id3TextFrame(_ id: String, text: String) -> Data {
        let textData = Data([0x03]) + Data(text.utf8) // UTF-8 encoding flag
        var frame = Data(id.utf8)
        frame.append(id3FrameSize(textData.count))
        frame.append(contentsOf: [0x00, 0x00]) // flags
        frame.append(textData)
        return frame
    }

    private static func id3LyricFrame(_ lyric: String) -> Data {
        // USLT frame: encoding(1) + language(3) + content descriptor(1) + text
        var content = Data([0x03])           // UTF-8
        content.append(contentsOf: [0x65, 0x6E, 0x67]) // "eng"
        content.append(0x00)                 // empty descriptor
        content.append(Data(lyric.utf8))

        var frame = Data("USLT".utf8)
        frame.append(id3FrameSize(content.count))
        frame.append(contentsOf: [0x00, 0x00])
        frame.append(content)
        return frame
    }

    private static func id3CoverFrame(_ imageData: Data) -> Data {
        // APIC frame: encoding(1) + mime(n) + null(1) + type(1) + desc(1) + data
        var content = Data([0x00])           // ISO-8859-1
        content.append(Data("image/jpeg".utf8))
        content.append(0x00)                 // null terminator
        content.append(0x03)                 // cover type
        content.append(0x00)                 // empty description
        content.append(imageData)

        var frame = Data("APIC".utf8)
        frame.append(id3FrameSize(content.count))
        frame.append(contentsOf: [0x00, 0x00])
        frame.append(content)
        return frame
    }

    // MARK: - Combine bilingual lyrics

    static func combineLyrics(original: String, translated: String) -> String {
        guard !translated.isEmpty else { return "" }

        var lrcMap: [String: String] = [:]
        for line in original.split(separator: "\n", omittingEmptySubsequences: false) {
            if let m = parseLrcLine(String(line)) { lrcMap[m.time] = m.text }
        }

        var result: [String] = []
        for line in translated.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if let m = parseLrcLine(s), let orig = lrcMap[m.time] {
                result.append("[\(m.time)]\(orig.trimmingCharacters(in: .whitespaces)) \(m.text.trimmingCharacters(in: .whitespaces))")
            } else {
                result.append(s)
            }
        }
        return result.joined(separator: "\n")
    }

    private static func parseLrcLine(_ line: String) -> (time: String, text: String)? {
        let pattern = #"^\[(\d{2}:\d{2}\.\d{2,3})\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let timeRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[timeRange]), String(line[textRange]))
    }
}

// MARK: - URLSession delegate for download progress

private class ProgressDelegate: NSObject, URLSessionDataDelegate {
    private let progressHandler: (Double) -> Void
    private let continuation: CheckedContinuation<Data, Error>
    private var data = Data()
    private var totalBytes: Int64 = 0

    init(progress: @escaping (Double) -> Void, continuation: CheckedContinuation<Data, Error>) {
        self.progressHandler = progress
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        totalBytes = response.expectedContentLength
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.data.append(data)
        if totalBytes > 0 {
            progressHandler(Double(self.data.count) / Double(totalBytes))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: data)
        }
    }
}
