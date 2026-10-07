import MusicHUDCore
import SwiftUI

/// The `标题 · 值` list from the reference design.
///
/// The block is horizontally centred while the rows themselves stay
/// left-aligned, which is what gives the reference its tidy but not rigid look.
struct TrackDetailView: View {
    let metadata: TrackMetadata?
    let metrics: HUDMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(label: L("hud.detail.title"), value: metadata?.title)
            row(label: L("hud.detail.artist"), value: metadata?.artist)
            row(label: L("hud.detail.album"), value: metadata?.album)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func row(label: String, value: String?) -> some View {
        HStack(spacing: metrics.detailFontSize * 0.46) {
            Text(label)
                .foregroundStyle(HUDTheme.quaternaryText)
            Text("·")
                .foregroundStyle(HUDTheme.quaternaryText.opacity(0.75))
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                .foregroundStyle(HUDTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: metrics.detailFontSize, weight: .regular))
        .frame(height: metrics.detailRowHeight, alignment: .leading)
    }
}
