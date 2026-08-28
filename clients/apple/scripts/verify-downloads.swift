import Foundation

// 编译并运行（在 clients/apple 目录）：
//
// swiftc -o .verify-downloads-bin \
//   MultiLiveTV/Models/DownloadRecord.swift \
//   MultiLiveTV/Services/Download/DownloadMediaKind.swift \
//   MultiLiveTV/Services/Download/DownloadEnqueuePolicy.swift \
//   MultiLiveTV/Services/Download/DownloadStore.swift \
//   MultiLiveTV/Services/Download/HLSPlaylistLocalizer.swift \
//   scripts/verify-downloads.swift \
// && ./.verify-downloads-bin

@main
enum VerifyDownloads {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("FAIL: \(message)\n", stderr)
            failures += 1
        }
    }

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        expect(actual == expected, "\(message) (got \(actual), expected \(expected))")
    }

    static func main() throws {
        testStableID()
        testMediaClassification()
        testEnqueuePolicy()
        testFinishAfterSuccess()
        try testStore()
        testLineDedup()
        testHLSPlaylistLocalizer()

        if failures > 0 {
            fputs("\(failures) failure(s)\n", stderr)
            exit(1)
        }
        print("VERIFY PASSED")
    }

    static func testStableID() {
        let idA = DownloadRecord.stableID(
            sourceId: 33,
            vodId: "100",
            playSourceKey: "33:wjm3u8",
            episodeURL: "https://cdn.example/1.m3u8"
        )
        let idB = DownloadRecord.stableID(
            sourceId: 33,
            vodId: "100",
            playSourceKey: "33:snm3u8",
            episodeURL: "https://cdn.example/1.m3u8"
        )
        expect(idA != idB, "不同 playSourceKey 同 url 必须是两个任务")
        expectEqual(idA.count, 64, "sha256 hex 长度")
        expectEqual(
            DownloadRecord.stableID(sourceId: 33, vodId: "100", playSourceKey: "33:wjm3u8", episodeURL: "https://cdn.example/1.m3u8"),
            idA,
            "同一输入必须得到同一 id"
        )
    }

    static func testMediaClassification() {
        expectEqual(DownloadMediaClassifier.classify("https://a.com/a.m3u8"), .hls, "m3u8 → hls")
        expectEqual(DownloadMediaClassifier.classify("https://a.com/a.M3U8?token=1"), .hls, "大写 m3u8")
        expectEqual(DownloadMediaClassifier.classify("https://a.com/a.mp4"), .progressive, "mp4 → progressive")
        expectEqual(DownloadMediaClassifier.classify("https://a.com/a.mov"), .progressive, "mov → progressive")
        expectEqual(DownloadMediaClassifier.classify("https://a.com/play.php?id=1"), .unsupported, "网页链")
        expectEqual(DownloadMediaClassifier.classify("https://a.com/a.mkv"), .unsupported, "mkv 不下载")
        expectEqual(DownloadMediaClassifier.classify("https://a.com/a.flv"), .unsupported, "flv 不下载")

        expect(DownloadRecord.fixture(status: .failed, localPath: nil).allowsNewDownload, "失败可重新下载")
        expect(DownloadRecord.fixture(status: .evicted, localPath: nil).allowsNewDownload, "被清理可重新下载")
        expect(DownloadRecord.fixture(status: .paused, localPath: nil).allowsNewDownload, "暂停可继续")
        expect(!DownloadRecord.fixture(status: .completed, localPath: "/tmp/x").allowsNewDownload, "已完成不应再入队")
        expect(!DownloadRecord.fixture(status: .downloading, localPath: nil).allowsNewDownload, "下载中不应再入队")
        expect(!DownloadRecord.fixture(status: .queued, localPath: nil).allowsNewDownload, "排队中不应再入队")
    }

    static func testEnqueuePolicy() {
        let oneGB: Int64 = 1_000_000_000

        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: nil, fileExists: false, freeDiskBytes: oneGB),
            .queued,
            "新任务磁盘足够应入队"
        )
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: nil, fileExists: false, freeDiskBytes: oneGB - 1),
            .insufficientDisk,
            "磁盘不足应拒绝"
        )

        let completed = DownloadRecord.fixture(status: .completed, localPath: "/tmp/x")
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: completed, fileExists: true, freeDiskBytes: oneGB),
            .alreadyCompleted,
            "已完成且文件在应忽略"
        )
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: completed, fileExists: false, freeDiskBytes: oneGB),
            .resetToQueued,
            "已完成但文件缺失应重新入队"
        )

        let failed = DownloadRecord.fixture(status: .failed, localPath: nil)
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: failed, fileExists: false, freeDiskBytes: oneGB),
            .resetToQueued,
            "failed 应重置为 queued"
        )
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: DownloadRecord.fixture(status: .evicted, localPath: nil), fileExists: false, freeDiskBytes: oneGB),
            .resetToQueued,
            "evicted 应重置为 queued"
        )
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: DownloadRecord.fixture(status: .paused, localPath: nil), fileExists: false, freeDiskBytes: oneGB),
            .resetToQueued,
            "paused 重新下载应入队"
        )
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: DownloadRecord.fixture(status: .queued, localPath: nil), fileExists: false, freeDiskBytes: oneGB),
            .alreadyInQueue,
            "已在队列"
        )
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: DownloadRecord.fixture(status: .downloading, localPath: nil), fileExists: false, freeDiskBytes: oneGB),
            .alreadyInQueue,
            "下载中"
        )
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: DownloadRecord.fixture(status: .resolving, localPath: nil), fileExists: false, freeDiskBytes: oneGB),
            .alreadyInQueue,
            "解析中"
        )
        expectEqual(
            DownloadEnqueuePolicy.outcome(existing: failed, fileExists: false, freeDiskBytes: 0),
            .insufficientDisk,
            "重试时磁盘不足仍拒绝"
        )
    }

    static func testFinishAfterSuccess() {
        expectEqual(
            DownloadEnqueuePolicy.actionAfterEngineSuccess(deleteRequested: false, pauseRequested: true),
            .complete,
            "文件已落地时暂停不能把任务卡在 downloading"
        )
        expectEqual(
            DownloadEnqueuePolicy.actionAfterEngineSuccess(deleteRequested: true, pauseRequested: false),
            .discard,
            "用户删除应丢掉刚下完的文件"
        )
        expectEqual(
            DownloadEnqueuePolicy.actionAfterEngineSuccess(deleteRequested: true, pauseRequested: true),
            .discard,
            "删除优先于暂停"
        )
        expectEqual(
            DownloadEnqueuePolicy.actionAfterEngineSuccess(deleteRequested: false, pauseRequested: false),
            .complete,
            "正常完成应标 completed"
        )
    }

    static func testStore() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mltv-download-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = DownloadStore(rootURL: tempRoot)
        expect(store.load().isEmpty, "空目录 load 应为空")

        var record = DownloadRecord.fixture(status: .completed, localPath: nil)
        let fileDir = store.filesDirectory(for: record.id)
        try FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true)
        let videoURL = fileDir.appendingPathComponent("video.mp4")
        try Data("fake".utf8).write(to: videoURL)
        record.localPath = videoURL.path
        record.mediaKind = .progressive
        try store.upsert(record)

        let loaded = store.load()
        expectEqual(loaded.count, 1, "upsert 后应有 1 条")
        expectEqual(loaded[0].id, record.id, "id 应一致")
        expectEqual(loaded[0].vodName, record.vodName, "vodName 应持久化")

        var reconciled = store.reconcileEvicted(loaded)
        expectEqual(reconciled[0].status, .completed, "文件存在时不应 evicted")

        try FileManager.default.removeItem(at: videoURL)
        reconciled = store.reconcileEvicted(store.load())
        expectEqual(reconciled[0].status, .evicted, "文件缺失应变 evicted")

        try store.delete(id: record.id)
        expect(store.load().isEmpty, "delete 后 index 应空")
        expect(!FileManager.default.fileExists(atPath: fileDir.path), "delete 应移除文件目录")
    }

    static func testLineDedup() {
        let vod = DownloadRecord.fixture(status: .queued, localPath: nil)
        let existingByID = [vod.id: vod]
        let episodes = [
            (url: "https://cdn.example/1.m3u8", name: "第1集"),
            (url: "https://cdn.example/1.m3u8", name: "第1集"),
            (url: "https://cdn.example/2.m3u8", name: "第2集"),
        ]
        let ids = episodes.map {
            DownloadRecord.stableID(sourceId: vod.sourceId, vodId: vod.vodId, playSourceKey: vod.playSourceKey, episodeURL: $0.url)
        }
        let uniqueNew = DownloadEnqueuePolicy.uniqueEpisodeIDs(ids, existing: existingByID)
        expectEqual(Set(uniqueNew).count, uniqueNew.count, "本线路入队 id 去重")
        expect(uniqueNew.contains(ids[2]), "未入队的第2集应留下")
        expect(!uniqueNew.contains(ids[0]), "已在队列的第1集应跳过")
    }

    static func testHLSPlaylistLocalizer() {
        expect(HLSPlaylistLocalizer.isMasterPlaylist("""
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000
        low.m3u8
        """), "含 STREAM-INF 的是 master")
        expect(!HLSPlaylistLocalizer.isMasterPlaylist("""
        #EXTM3U
        #EXTINF:4.0,
        a.ts
        """), "媒体列表不是 master")

        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000
        low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=3000000
        mid.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=8000000
        high.m3u8
        """
        let base = URL(string: "https://cdn.example/hls/master.m3u8")!
        let picked = HLSPlaylistLocalizer.pickVariantURL(playlist: master, base: base, maxBandwidth: 4_000_000)
        expectEqual(picked?.absoluteString, "https://cdn.example/hls/mid.m3u8", "应选不超过 4Mbps 的最高码率")

        let media = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="https://cdn.example/key.key"
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:4.0,
        seg1.ts
        #EXTINF:4.0,
        https://other.example/seg2.ts
        #EXT-X-ENDLIST
        """
        let plan = HLSPlaylistLocalizer.plan(mediaPlaylist: media, base: URL(string: "https://cdn.example/hls/index.m3u8")!)
        expect(plan.downloads.contains { $0.remote.absoluteString == "https://cdn.example/key.key" }, "应下载 KEY")
        expect(plan.downloads.contains { $0.remote.absoluteString == "https://cdn.example/hls/init.mp4" }, "相对 MAP 应解析")
        expect(plan.downloads.contains { $0.remote.absoluteString == "https://cdn.example/hls/seg1.ts" }, "相对分片应解析")
        expect(plan.downloads.contains { $0.remote.absoluteString == "https://other.example/seg2.ts" }, "绝对分片应保留")
        expect(plan.playlist.contains("URI=\"key_0.key\""), "KEY URI 应改成本地名")
        expect(plan.playlist.contains("URI=\"map_0.mp4\""), "MAP URI 应改成本地名")
        expect(plan.playlist.contains("seg_0000.ts"), "分片应改成本地名")
        expect(!plan.playlist.contains("https://other.example/seg2.ts"), "重写后不应再含远程分片 URL")
    }
}

extension DownloadRecord {
    static func fixture(status: DownloadStatus, localPath: String?) -> DownloadRecord {
        DownloadRecord(
            id: stableID(sourceId: 33, vodId: "100", playSourceKey: "33:wjm3u8", episodeURL: "https://cdn.example/1.m3u8"),
            sourceId: 33,
            vodId: "100",
            vodName: "测试片",
            posterURL: "https://cdn.example/poster.jpg",
            playSourceKey: "33:wjm3u8",
            playSourceName: "无忧 · 猫眼",
            episodeName: "第1集",
            originalURL: "https://cdn.example/1.m3u8",
            resolvedURL: nil,
            status: status,
            bytesWritten: 0,
            bytesExpected: 0,
            fraction: 0,
            mediaKind: nil,
            localPath: localPath,
            assetTitle: nil,
            errorMessage: nil
        )
    }
}
