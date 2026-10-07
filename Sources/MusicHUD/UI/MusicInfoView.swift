import AppKit
import MusicHUDCore
import SwiftUI

/// The upper block: artwork, then the title and the "来自 <artist>" line.
///
/// Matches the reference hierarchy exactly — a small centred cover with the
/// text block beneath it, all in low-contrast type.
///
/// When Music.app is unreachable the same two text slots carry the reason
/// instead ("Music is not running", "No music playing", "Music access
/// required"), so no new UI element had to be introduced for Phase 2 and the
/// Phase 1 layout is untouched.
struct MusicInfoView: View {
    let snapshot: NowPlayingSnapshot
    let availability: MusicAvailability
    let artworkImage: NSImage?
    /// Procedural fallback art is only legitimate in demo mode.
    let allowsProceduralArtwork: Bool
    let showArtwork: Bool
    let showTrackInfo: Bool
    let metrics: HUDMetrics

    private var isIdle: Bool { availability.showsIdleState }

    var body: some View {
        VStack(spacing: metrics.spacingAfterArtwork) {
            if showArtwork {
                ArtworkView(
                    image: artworkImage,
                    seed: snapshot.metadata?.artworkSeed ?? 0,
                    allowsProceduralFallback: allowsProceduralArtwork,
                    hasTrack: !isIdle,
                    size: metrics.artworkSize,
                    cornerRadius: metrics.artworkCornerRadius
                )
            }

            if showTrackInfo {
                VStack(spacing: metrics.spacingAfterTitle) {
                    Text(titleText)
                        .font(.system(size: metrics.titleFontSize, weight: .bold))
                        .tracking(metrics.titleTracking)
                        .foregroundStyle(isIdle ? HUDTheme.secondaryText : HUDTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !subtitleText.isEmpty {
                        Text(subtitleText)
                            .font(.system(size: metrics.subtitleFontSize, weight: .regular))
                            .foregroundStyle(HUDTheme.tertiaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The track title, or the reason there is no track.
    private var titleText: String {
        if let headline = (availability.headlineKey.map { L($0) } ?? availability.headline) { return headline }
        guard let metadata = snapshot.metadata, !metadata.isEmpty else { return L("hud.notPlaying") }
        return metadata.title
    }

    /// Mirrors the reference's `来自 3WA · 圣迭戈 Pacific` construction, and
    /// carries the actionable hint when idle.
    private var subtitleText: String {
        if isIdle { return (availability.detailKey.isEmpty ? "" : L(availability.detailKey)) }

        guard let metadata = snapshot.metadata, !metadata.isEmpty else { return "" }
        var text = metadata.artist.isEmpty ? "" : String(format: L("hud.byArtist"), metadata.artist)
        if !metadata.subtitle.isEmpty {
            text += text.isEmpty ? metadata.subtitle : " · \(metadata.subtitle)"
        }
        return text
    }
}
