import TVServices

@objc(ContentProvider)
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let items = TopShelfStore.load().compactMap(Self.makeItem)
        completionHandler(items.isEmpty ? nil : TVTopShelfInsetContent(items: items))
    }

    private static func makeItem(from snapshot: TopShelfSnapshot) -> TVTopShelfItem? {
        guard let imageURL = RemoteMediaURL.parse(snapshot.vodPic),
              let actionURL = AppDeepLink.vodURL(sourceId: snapshot.sourceId, vodId: snapshot.vodId)
        else { return nil }

        let item = TVTopShelfItem(identifier: "\(snapshot.sourceId):\(snapshot.vodId)")
        item.title = snapshot.vodName
        item.displayAction = TVTopShelfAction(url: actionURL)
        item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
        return item
    }
}
