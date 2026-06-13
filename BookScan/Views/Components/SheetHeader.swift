//
//  SheetHeader.swift
//  BookScan
//
//  Created by Marian Mihailescu on 12/6/2026.
//
//  The shared header used by every sheet and tab in the app: a flat, edge-to-edge
//  bar in the same color as the surface beneath it (so it reads as one seamless
//  region, no divider), with circular icon buttons at the edges — matching the
//  current iOS system look (e.g. the CloudKit share sheet). Content scrolls
//  underneath and disappears at the bar's straight bottom edge.
//

import SwiftUI

enum SheetStyle {
    /// Corner radius for large sheets and the floating header bar. Single source of
    /// truth so it can be tuned in one place.
    static let cornerRadius: CGFloat = 36
    /// Height of the header bar's content (excluding the top safe area). Snug around
    /// the 48pt circular buttons.
    static let headerHeight: CGFloat = 64
}

// MARK: - Circular icon button

/// A circular icon button for sheet headers. The `prominent` variant fills with the
/// accent color (the ✓ "Done" button); the plain variant uses a material fill (✕, ‹,
/// and the action icons like share / add / reset).
struct CircularIconButton: View {
    let systemName: String
    var prominent: Bool = false
    /// Optical-centering nudge for glyphs whose bounding box isn't visually centered
    /// (e.g. `square.and.arrow.up`, which otherwise sits low). Negative = up.
    var glyphYOffset: CGFloat = 0
    var accessibilityLabel: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    // A 48pt disc with a 20pt glyph. The plain fill is a TRANSLUCENT system fill, not
    // an absolute gray: it darkens (light) / lightens (dark) whatever surface it sits
    // on by a constant amount, so the disc reads with the same contrast on the white
    // sheet background AND the light-gray tab header — an absolute gray (systemGray5)
    // pops on white but blends into the gray header. (A material can't be used: it
    // blurs to match a light background and the disc vanishes.)
    private let diameter: CGFloat = 48

    var body: some View {
        Button(action: action) {
            ZStack {
                if prominent {
                    Circle().fill(Color.accentColor)
                } else {
                    Circle().fill(Color(.tertiarySystemFill))
                }
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(prominent ? Color.white : Color.primary)
                    .offset(y: glyphYOffset)
            }
            .frame(width: diameter, height: diameter)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Header bar

/// The header bar: a centered title with optional leading and trailing controls,
/// on a flat edge-to-edge background. No divider, no shadow, no rounding of its own
/// (inside a sheet the sheet's corners round the top; the bottom is a straight line).
///
/// `background` defaults to the system background — which resolves to the elevated
/// sheet color inside sheets — so the bar is indistinguishable from the content
/// surface; content scrolling up simply disappears beneath it. Pass a different
/// style where the surface differs (Library's gray, Scan's camera material).
struct SheetHeaderBar<Leading: View, Trailing: View>: View {
    let title: String
    var background: AnyShapeStyle = AnyShapeStyle(Color(.systemBackground))
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 56)   // keep the title clear of the edge buttons

            HStack {
                leading
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 16)
        .frame(height: SheetStyle.headerHeight)
        .frame(maxWidth: .infinity)
        .background {
            // `ignoresSafeArea` extends the fill up through the status-bar region on
            // full-screen tabs (a no-op inside sheets, where the top inset is zero),
            // so content can never show above the bar.
            Rectangle()
                .fill(background)
                .ignoresSafeArea(edges: .top)
        }
    }
}

extension SheetHeaderBar where Leading == EmptyView {
    init(
        title: String,
        background: AnyShapeStyle = AnyShapeStyle(Color(.systemBackground)),
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title: title, background: background, leading: { EmptyView() }, trailing: trailing)
    }
}

extension SheetHeaderBar where Trailing == EmptyView {
    init(
        title: String,
        background: AnyShapeStyle = AnyShapeStyle(Color(.systemBackground)),
        @ViewBuilder leading: () -> Leading
    ) {
        self.init(title: title, background: background, leading: leading, trailing: { EmptyView() })
    }
}

// MARK: - Container

/// Lays out a `SheetHeaderBar` pinned over `content`. The content extends under the
/// bar; pair with `.scrollsBehindHeader()` on the inner ScrollView so rows start
/// below the bar and slide beneath it when scrolled (non-scrolling content should
/// add a static top padding of `SheetStyle.headerHeight` instead).
struct SheetHeaderContainer<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            content
            header
        }
    }
}

extension View {
    /// Insets a ScrollView's content below the header bar so it starts clear of it
    /// but still scrolls underneath when the user scrolls up (same mechanic as the
    /// floating tab bar's bottom margin). `extra` is breathing room between the
    /// bar's bottom edge and the first row.
    func scrollsBehindHeader(extra: CGFloat = 8) -> some View {
        contentMargins(.top, SheetStyle.headerHeight + extra, for: .scrollContent)
    }

    /// Standard presentation styling for the app's full sheets: the shared corner
    /// radius plus an explicit background using the SAME dynamic color as the header
    /// bar. The explicit background matters on iPad: page sheets there paint their
    /// default canvas at the base elevation level while the bar's color resolves
    /// elevated, leaving a visible band (seen on Search / Enter ISBN). Setting both
    /// to one color resolved in one environment keeps them seamless everywhere.
    func standardSheetPresentation() -> some View {
        self
            .presentationCornerRadius(SheetStyle.cornerRadius)
            .presentationBackground(Color(.systemBackground))
    }
}
