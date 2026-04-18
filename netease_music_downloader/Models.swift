import Foundation

// MARK: - API Response Models

struct SongUrlResponse: Decodable {
    let code: Int
    let data: [SongUrlData]
}

struct SongUrlData: Decodable {
    let id: Int
    let url: String?
    let size: Int?
    let level: String?
}

struct SongDetailResponse: Decodable {
    let songs: [SongDetail]
}

struct SongDetail: Decodable {
    let id: Int
    let name: String
    let ar: [Artist]
    let al: Album
    let no: Int
    let publishTime: Int64?
}

struct Artist: Decodable {
    let name: String
}

struct Album: Decodable {
    let name: String
    let picUrl: String?
}

struct LyricResponse: Decodable {
    let lrc: LyricContent?
    let tlyric: LyricContent?
}

struct LyricContent: Decodable {
    let lyric: String?
}

// MARK: - App Models

struct SongInfo: Identifiable {
    let id: Int
    let name: String
    let artist: String
    let album: String
    let picUrl: String?
    let url: String
    let level: String
    let size: String
    var lyric: String?
    var tlyric: String?
}

// MARK: - Constants

enum MusicLevel: String, CaseIterable {
    case standard = "standard"
    case exhigh = "exhigh"
    case lossless = "lossless"
    case hires = "hires"
    case sky = "sky"
    case jyeffect = "jyeffect"
    case jymaster = "jymaster"

    var displayName: String {
        switch self {
        case .standard: return "标准音质"
        case .exhigh: return "极高音质"
        case .lossless: return "无损音质"
        case .hires: return "Hires音质"
        case .sky: return "沉浸环绕声"
        case .jyeffect: return "高清环绕声"
        case .jymaster: return "超清母带"
        }
    }
}

func formatSize(_ bytes: Int?) -> String {
    guard let bytes = bytes, bytes > 0 else { return "未知" }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.2f MB", mb)
}

func levelDisplayName(_ level: String?) -> String {
    MusicLevel(rawValue: level ?? "")?.displayName ?? "未知音质"
}
