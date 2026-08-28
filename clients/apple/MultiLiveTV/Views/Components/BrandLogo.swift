import SwiftUI

struct BrandLogo: View {
    var height: CGFloat = 28

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("MultiLiveTV")
    }
}
