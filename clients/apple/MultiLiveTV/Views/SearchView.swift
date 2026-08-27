import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var api: APIClient
    @State private var keyword = ""
    @State private var results: [VodItem] = []
    @State private var errorMessage: String?
    @State private var selectedItem: VodItem?
    @State private var detail: DetailResponse?
    @FocusState private var focusedId: String?

    var body: some View {
        NavigationStack {
            VStack {
                #if os(tvOS)
                TextField("搜索影片", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                Button("搜索") { Task { await search() } }
                    .keyboardShortcut(.defaultAction)
                #else
                HStack {
                    TextField("搜索影片", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                    Button("搜索") { Task { await search() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                #endif

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                #if os(tvOS)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 32)], spacing: 32) {
                        ForEach(results) { item in
                            VodCard(item: item, isFocused: focusedId == item.id) {
                                selectedItem = item
                            }
                            .focused($focusedId, equals: item.id)
                        }
                    }
                    .padding(48)
                }
                #else
                List(results) { item in
                    Button(item.vodName) { selectedItem = item }
                }
                #endif
            }
            .navigationTitle("搜索")
            .sheet(item: $selectedItem) { item in
                DetailView(item: item, detail: detail, onAppear: {
                    Task { await loadDetail(for: item) }
                })
            }
        }
    }

    private func search() async {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        errorMessage = nil
        do {
            results = try await api.search(keyword)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDetail(for item: VodItem) async {
        do {
            detail = try await api.detail(sourceId: item.resolvedSourceId, vodId: item.vodId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
