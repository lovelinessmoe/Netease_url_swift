import SwiftUI
import Combine
import UserNotifications

@MainActor
class ViewModel: ObservableObject {
    @Published var input = "https://music.163.com/playlist?id=362613622"
    @Published var selectedLevel: MusicLevel = .jymaster
    @Published var songs: [SongInfo] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var selectedSongIds: Set<Int> = []
    @Published var cookieStatus: String = ""
    @Published var showCookieSheet = false
    @Published var cookieInput: String = ""

    private let pageSize = 20
    @Published var allIds: [Int] = []
    private var currentPage = 0
    var hasMore: Bool { currentPage * pageSize < allIds.count }

    init() { checkCookie() }

    func checkCookie() {
        cookieStatus = CookieUtil.hasCookie() ? "✓ Cookie 已设置" : "⚠ 未设置 Cookie"
    }

    func saveCookie() {
        CookieUtil.saveCookie(cookieInput)
        checkCookie()
        showCookieSheet = false
    }

    func search() async {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        songs = []
        selectedSongIds = []
        allIds = []
        currentPage = 0

        do {
            let ids = try await MusicService.parseIds(from: input)
            allIds = ids
            statusMessage = "共 \(ids.count) 首，正在加载第 1 页..."
            await loadPage()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        await loadPage()
        isLoadingMore = false
    }

    private func loadPage() async {
        let cookies = (try? CookieUtil.readCookie()).map { CookieUtil.parseCookie($0) } ?? [:]
        let start = currentPage * pageSize
        let end = min(start + pageSize, allIds.count)
        let pageIds = Array(allIds[start..<end])
        currentPage += 1

        let results = await withTaskGroup(of: (Int, SongInfo?).self) { group in
            for (i, id) in pageIds.enumerated() {
                group.addTask {
                    do {
                        let urlData = try await MusicService.getSongUrl(id: id, level: self.selectedLevel.rawValue, cookies: cookies)
                        let detail = try await MusicService.getSongDetail(id: urlData.id)
                        let lyric = try await MusicService.getLyric(id: urlData.id, cookies: cookies)
                        return (i, DownloadService.buildSongInfo(urlData: urlData, detail: detail, lyric: lyric))
                    } catch { return (i, nil) }
                }
            }

            var all: [(Int, SongInfo?)] = []
            for await result in group { all.append(result) }
            return all.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        }

        songs.append(contentsOf: results)
        statusMessage = "已加载 \(songs.count)/\(allIds.count) 首"
    }

    @Published var downloadProgress: Double = 0   // 0.0 ~ 1.0
    @Published var isDownloading = false

    func downloadSelected() async {
        let toDownload = songs.filter { selectedSongIds.contains($0.id) }
        guard !toDownload.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "选择保存位置"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isDownloading = true
        downloadProgress = 0
        var success = 0

        for (i, song) in toDownload.enumerated() {
            downloadProgress = 0
            statusMessage = "下载中 \(i + 1)/\(toDownload.count)：\(song.name)"
            do {
                _ = try await DownloadService.downloadSong(song, to: folder) { [weak self] p in
                    Task { @MainActor in self?.downloadProgress = p }
                }
                success += 1
            } catch { }
        }

        isDownloading = false
        statusMessage = "下载完成：\(success)/\(toDownload.count) 首"
        notify(title: "下载完成", body: "已成功下载 \(success) 首歌曲")
    }

    private func notify(title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func downloadAll() async {
        selectedSongIds = Set(songs.map(\.id))
        await downloadSelected()
    }
}

// MARK: - Theme
private let sakura = Color(red: 1.0, green: 0.43, blue: 0.65)
private let sakuraLight = Color(red: 1.0, green: 0.82, blue: 0.90)
private let sakuraDark = Color(red: 0.85, green: 0.25, blue: 0.50)

struct PinkButtonStyle: ButtonStyle {
    var filled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(filled ? sakura.opacity(configuration.isPressed ? 0.7 : 1) : Color.clear)
            .foregroundStyle(filled ? .white : sakura)
            .clipShape(Capsule())
            .overlay(filled ? nil : Capsule().stroke(sakura, lineWidth: 1.2))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @StateObject private var vm = ViewModel()

    var body: some View {
        ZStack {
            // Soft pink gradient background
            LinearGradient(colors: [sakuraLight.opacity(0.35), Color(red: 0.98, green: 0.93, blue: 0.97)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("🌸").font(.title2)
                        Text("音乐下载器").font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(sakuraDark)
                        Text("🎀").font(.title2)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.clear)
                    .gesture(WindowDragGesture())

                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(sakura)
                                .font(.system(size: 13))
                            TextField("输入歌曲ID、链接或歌单链接～", text: $vm.input)
                                .font(.system(size: 13, design: .rounded))
                                .onSubmit { Task { await vm.search() } }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.8))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(sakura.opacity(0.4), lineWidth: 1))

                        Picker("", selection: $vm.selectedLevel) {
                            ForEach(MusicLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .frame(width: 120)
                        .background(.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button("搜索 ✨") { Task { await vm.search() } }
                            .buttonStyle(PinkButtonStyle())
                            .disabled(vm.isLoading)
                            .keyboardShortcut(.return)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white.opacity(0.5))

                // Song list
                if vm.songs.isEmpty {
                    Spacer()
                    if vm.isLoading {
                        VStack(spacing: 10) {
                            ProgressView().tint(sakura)
                            Text("少女祈祷中…").font(.system(size: 13, design: .rounded)).foregroundStyle(sakura)
                        }
                    } else {
                        VStack(spacing: 6) {
                            Text("🎵").font(.system(size: 36))
                            Text(vm.errorMessage ?? "输入歌曲ID或链接后点击搜索～")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(sakura.opacity(0.8))
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(vm.songs) { song in
                                SongRow(song: song, isSelected: vm.selectedSongIds.contains(song.id))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if vm.selectedSongIds.contains(song.id) {
                                            vm.selectedSongIds.remove(song.id)
                                        } else {
                                            vm.selectedSongIds.insert(song.id)
                                        }
                                    }
                            }
                            if vm.hasMore {
                                HStack {
                                    Spacer()
                                    if vm.isLoadingMore {
                                        ProgressView().tint(sakura)
                                    } else {
                                        Button("加载更多 ✦ 已加载 \(vm.songs.count)/\(vm.allIds.count)") {
                                            Task { await vm.loadNextPage() }
                                        }
                                        .buttonStyle(PinkButtonStyle(filled: false))
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .onAppear { Task { await vm.loadNextPage() } }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }

                // Bottom bar
                VStack(spacing: 0) {
                    if vm.isDownloading {
                        ProgressView(value: vm.downloadProgress)
                            .tint(sakura)
                            .padding(.horizontal)
                            .padding(.top, 6)
                    }
                    HStack(spacing: 10) {
                        Button(vm.cookieStatus) { vm.showCookieSheet = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(vm.cookieStatus.hasPrefix("✓") ? Color(red: 0.2, green: 0.75, blue: 0.5) : Color.orange)

                        Spacer()

                        if let status = vm.statusMessage {
                            Text(status).font(.system(size: 11, design: .rounded)).foregroundStyle(sakura.opacity(0.8))
                        }

                        if !vm.songs.isEmpty {
                            Button("全选") { vm.selectedSongIds = Set(vm.songs.map(\.id)) }
                                .buttonStyle(PinkButtonStyle(filled: false))
                            Button("下载选中 (\(vm.selectedSongIds.count)) 💾") {
                                Task { await vm.downloadSelected() }
                            }
                            .buttonStyle(PinkButtonStyle())
                            .disabled(vm.selectedSongIds.isEmpty || vm.isDownloading)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.5))
                }
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .sheet(isPresented: $vm.showCookieSheet) {
            ZStack {
                LinearGradient(colors: [sakuraLight.opacity(0.4), .white], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("🍪").font(.title2); Text("设置 Cookie").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(sakuraDark) }
                    Text("从浏览器开发者工具中复制网易云音乐的 Cookie 粘贴到此处")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(sakura.opacity(0.8))
                    TextEditor(text: $vm.cookieInput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(sakura.opacity(0.4), lineWidth: 1))
                    HStack {
                        Spacer()
                        Button("取消") { vm.showCookieSheet = false }.buttonStyle(PinkButtonStyle(filled: false))
                        Button("保存 ✨") { vm.saveCookie() }.buttonStyle(PinkButtonStyle())
                            .disabled(vm.cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
            }
            .frame(width: 480)
            .onAppear { vm.cookieInput = (try? CookieUtil.readCookie()) ?? "" }
        }
    }
}

struct SongRow: View {
    let song: SongInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "heart.fill" : "heart")
                .foregroundStyle(isSelected ? sakura : sakura.opacity(0.3))
                .font(.system(size: 15))
                .animation(.spring(duration: 0.2), value: isSelected)

            AsyncImage(url: URL(string: song.picUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                sakuraLight
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(sakura.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(song.artist).font(.system(size: 11, design: .rounded)).foregroundStyle(sakura.opacity(0.7))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(song.album).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(song.level)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(sakura.opacity(0.15))
                        .foregroundStyle(sakuraDark)
                        .clipShape(Capsule())
                    Text(song.size).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? sakura.opacity(0.1) : Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? sakura.opacity(0.5) : Color.clear, lineWidth: 1))
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
