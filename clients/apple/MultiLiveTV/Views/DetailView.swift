import SwiftUI

struct DetailView: View {
    let item: VodItem

    @EnvironmentObject private var vod: VodService
    @State private var detail: DetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSourceIndex = 0
    @State private var playbackRequest: PlaybackRequest?
    @FocusState private var focusedEpisode: String?
    @FocusState private var focusedSource: Int?

    var body: some View {
        Group {
            if isLoading {
                AppLoadingView()
            } else if let errorMessage {
                AppErrorView(message: errorMessage) {
                    Task { await loadDetail() }
                }
            } else if let detail {
                detailContent(detail)
            }
        }
        .navigationTitle(displayTitle)
        .task { await loadDetail() }
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerView(sourceId: request.sourceId, episode: request.episode)
                .environmentObject(vod)
        }
    }

    private var displayTitle: String {
        detail?.vod.vodName ?? item.vodName
    }

    @ViewBuilder
    private func detailContent(_ detail: DetailResponse) -> some View {
        #if os(tvOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                cinematicHeader(detail.vod)
                sourcePicker(detail.playSources)
                episodeSection(detail.playSources, detail: detail)
            }
            .padding(.bottom, TVDesign.screenPadding)
        }
        #else
        List {
            headerSection(detail.vod)
            sourcePicker(detail.playSources)
            if selectedSourceIndex < detail.playSources.count {
                let source = detail.playSources[selectedSourceIndex]
                Section(source.name) {
                    ForEach(source.episodes) { ep in
                        Button(ep.name) {
                            playbackRequest = PlaybackRequest(
                                sourceId: episodeSourceId(detail),
                                episode: ep
                            )
                        }
                    }
                }
            }
        }
        #endif
    }

    #if os(tvOS)
    @ViewBuilder
    private func cinematicHeader(_ vod: VodItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: vod.vodPic)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.25)
                }
            }
            .frame(height: 480)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 480)

            HStack(alignment: .bottom, spacing: 32) {
                AsyncImage(url: URL(string: vod.vodPic)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.25)
                    }
                }
                .frame(width: 220, height: 330)
                .clipShape(RoundedRectangle(cornerRadius: TVDesign.cornerRadius))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

                VStack(alignment: .leading, spacing: 14) {
                    if let typeName = vod.typeName {
                        Text(typeName.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .tracking(1.2)
                    }

                    Text(vod.vodName)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)

                    if let remarks = vod.displayRemarks {
                        Text(remarks)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    if let blurb = vod.displayBlurb {
                        Text(blurb)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(4)
                            .frame(maxWidth: 700, alignment: .leading)
                    }
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, TVDesign.screenPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: TVDesign.cornerRadius))
        .padding(.horizontal, TVDesign.screenPadding)
    }

    @ViewBuilder
    private func episodeSection(_ sources: [PlaySource], detail: DetailResponse) -> some View {
        if selectedSourceIndex < sources.count {
            let source = sources[selectedSourceIndex]
            VStack(alignment: .leading, spacing: 20) {
                Text("选集 · \(source.name)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVDesign.screenPadding)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(source.episodes) { ep in
                        EpisodeButton(
                            title: ep.name,
                            isFocused: focusedEpisode == ep.id
                        ) {
                            playbackRequest = PlaybackRequest(
                                sourceId: episodeSourceId(detail),
                                episode: ep
                            )
                        }
                        .focused($focusedEpisode, equals: ep.id)
                    }
                }
                .padding(.horizontal, TVDesign.screenPadding)
            }
        }
    }
    #endif

    @ViewBuilder
    private func headerSection(_ vod: VodItem) -> some View {
        HStack(alignment: .top, spacing: 24) {
            AsyncImage(url: URL(string: vod.vodPic)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.25)
                }
            }
            .frame(width: posterWidth, height: posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let blurb = vod.displayBlurb {
                Text(blurb)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
        }
        #if os(iOS)
        .listRowInsets(EdgeInsets())
        #endif
    }

    @ViewBuilder
    private func sourcePicker(_ sources: [PlaySource]) -> some View {
        #if os(tvOS)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    CategoryTabButton(
                        label: source.name,
                        isActive: selectedSourceIndex == index,
                        isFocused: focusedSource == index
                    ) {
                        selectedSourceIndex = index
                    }
                    .focused($focusedSource, equals: index)
                }
            }
            .padding(.horizontal, TVDesign.screenPadding)
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

    private var posterWidth: CGFloat {
        #if os(tvOS)
        240
        #else
        120
        #endif
    }

    private var posterHeight: CGFloat {
        #if os(tvOS)
        360
        #else
        180
        #endif
    }

    private func episodeSourceId(_ detail: DetailResponse) -> Int {
        guard selectedSourceIndex < detail.playSources.count else {
            return item.resolvedSourceId
        }
        return detail.playSources[selectedSourceIndex].sourceId ?? item.resolvedSourceId
    }

    private func preferredSourceIndex(for sources: [PlaySource]) -> Int {
        if let index = sources.firstIndex(where: { source in
            source.episodes.contains { PlaybackSupport.isDirectMediaURL($0.url) }
        }) {
            return index
        }
        return 0
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await vod.detail(sourceId: item.resolvedSourceId, vodId: item.vodId)
            selectedSourceIndex = preferredSourceIndex(for: detail?.playSources ?? [])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if os(tvOS)
private struct EpisodeButton: View {
    let title: String
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    isFocused ? Color.white.opacity(0.22) : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isFocused ? Color.white : Color.clear, lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
        .tvFocusScale(isFocused)
    }
}
#endif
