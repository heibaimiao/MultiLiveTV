import SwiftUI

struct DetailView: View {
    let item: VodItem
    let detail: DetailResponse?
    var onAppear: (() -> Void)?

    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSourceIndex = 0
    @State private var playEpisode: Episode?
    @State private var playSourceId = 0
    @State private var favoriteMessage: String?
    @FocusState private var focusedEpisode: String?

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    detailContent(detail)
                } else {
                    ProgressView("加载中…")
                }
            }
            .navigationTitle(item.vodName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("收藏") { Task { await toggleFavorite() } }
                        .disabled(!api.isLoggedIn)
                }
            }
            .onAppear { onAppear?() }
            .fullScreenCover(item: $playEpisode) { episode in
                PlayerView(sourceId: playSourceId, episode: episode)
            }
            .alert("收藏", isPresented: .constant(favoriteMessage != nil)) {
                Button("好") { favoriteMessage = nil }
            } message: {
                Text(favoriteMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: DetailResponse) -> some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 24) {
            sourcePicker(detail.playSources)
            episodeGrid(detail.playSources)
        }
        .padding(48)
        #else
        List {
            sourcePicker(detail.playSources)
            if selectedSourceIndex < detail.playSources.count {
                let source = detail.playSources[selectedSourceIndex]
                Section(source.name) {
                    ForEach(source.episodes) { ep in
                        Button(ep.name) {
                            playSourceId = episodeSourceId(detail)
                            playEpisode = ep
                        }
                    }
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private func sourcePicker(_ sources: [PlaySource]) -> some View {
        #if os(tvOS)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    Button(source.name) { selectedSourceIndex = index }
                        .buttonStyle(.bordered)
                        .tint(selectedSourceIndex == index ? .accentColor : .secondary)
                }
            }
        }
        #else
        Picker("线路", selection: $selectedSourceIndex) {
            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                Text(source.name).tag(index)
            }
        }
        .pickerStyle(.segmented)
        #endif
    }

    #if os(tvOS)
    @ViewBuilder
    private func episodeGrid(_ sources: [PlaySource]) -> some View {
        if selectedSourceIndex < sources.count {
            let source = sources[selectedSourceIndex]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                ForEach(source.episodes) { ep in
                    Button(ep.name) {
                        playSourceId = episodeSourceId(detail)
                        playEpisode = ep
                    }
                        .buttonStyle(.bordered)
                        .focused($focusedEpisode, equals: ep.id)
                }
            }
        }
    }
    #endif

    private func episodeSourceId(_ detail: DetailResponse?) -> Int {
        guard let detail, selectedSourceIndex < detail.playSources.count else {
            return item.resolvedSourceId
        }
        return detail.playSources[selectedSourceIndex].sourceId ?? item.resolvedSourceId
    }

    private func toggleFavorite() async {
        do {
            _ = try await api.addFavorite(item: item)
            favoriteMessage = "已加入收藏"
        } catch {
            favoriteMessage = error.localizedDescription
        }
    }
}
