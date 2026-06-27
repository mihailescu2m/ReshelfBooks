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

/// A circular icon button for sheet headers, matching the share-sheet's circular
/// buttons. The `prominent` variant is the filled accent circle (✓ "Done"); the plain
/// variant is the neutral circle (✕, ‹, share / add / switch-camera).
///
/// On **iOS 26+** it uses the native Liquid Glass button styles (`.glass` /
/// `.glassProminent`), so it gets the real frosted-glass material and Apple's fluid
/// interactive press animation. On **iOS 18–25** it falls back to a hand-rolled style
/// (`CircularButtonStyle`) that flat-fills the circle and animates a ~10% grow + lighten
/// on press — see docs/custom-circular-button-animation.md.
struct CircularIconButton: View {
    let systemName: String
    var prominent: Bool = false
    /// Optical-centering nudge for glyphs whose bounding box isn't visually centered
    /// (e.g. `square.and.arrow.up`, which otherwise sits low). Negative = up.
    var glyphYOffset: CGFloat = 0
    var accessibilityLabel: String
    let action: () -> Void

    /// Circle diameter for the iOS 26 glass buttons — matches the ~48pt share-sheet
    /// buttons (and the legacy fallback size). Single knob for fine-tuning.
    private static let glassDiameter: CGFloat = 48

    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .semibold))
            .offset(y: glyphYOffset)
    }

    var body: some View {
        // The action fires immediately (non-blocking) on every path.
        if #available(iOS 26.0, *) {
            // Explicit-size glass circle (not the .glass button style, whose controlSize
            // steps jump from too-small to too-big) with the native interactive press.
            Button(action: action) {
                glyph
                    .foregroundStyle(prominent ? Color.white : Color.primary)
                    .frame(width: Self.glassDiameter, height: Self.glassDiameter)
                    .glassEffect(
                        prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: .circle
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        } else {
            Button(action: action) { glyph }
                .buttonStyle(CircularButtonStyle(prominent: prominent))
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

/// Shared timing for the circular-button press bounce.
enum CircularButtonPress {
    /// Minimum time the button stays enlarged after the press begins, so even a quick
    /// tap (where the finger lifts almost immediately) still shows the grow before it
    /// springs back.
    static let holdDuration: Double = 0.13
}

/// Draws the circular fill (accent when prominent, neutral gray otherwise) and the
/// press feedback: a ~10% grow plus a translucent-white blend over the fill (so the
/// color reads lighter while the glyph itself stays crisp). The fixed 48pt frame keeps
/// every button the same circle regardless of its glyph's bounding box.
struct CircularButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PressableCircle(prominent: prominent, configuration: configuration)
    }
}

/// The rendered circle. Latches the press state so the grow is visible for at least
/// `holdDuration` even on a sub-frame tap, then springs back over `returnDuration`.
private struct PressableCircle: View {
    let prominent: Bool
    let configuration: ButtonStyleConfiguration

    /// Diameter at rest — matches the ~48pt of the system share-sheet buttons.
    private let diameter: CGFloat = 48
    /// Press grow factor (medium).
    private let pressedScale: CGFloat = 1.10
    /// White blend applied to the fill while pressed.
    private let pressedLighten: Double = 0.30

    @State private var visualPressed = false
    @State private var pressStarted: Date?

    var body: some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(width: diameter, height: diameter)
            .background {
                ZStack {
                    (prominent ? Color.accentColor : Color(.systemGray5))
                    // Lighten the fill (under the glyph, so the symbol stays crisp).
                    Color.white.opacity(visualPressed ? pressedLighten : 0)
                }
                .clipShape(Circle())
            }
            .scaleEffect(visualPressed ? pressedScale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: visualPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    visualPressed = true
                    pressStarted = Date()
                } else {
                    // Hold the enlarge for the remainder of the minimum duration so a
                    // quick tap's grow doesn't vanish the instant the finger lifts.
                    let elapsed = pressStarted.map { Date().timeIntervalSince($0) } ?? CircularButtonPress.holdDuration
                    let remaining = max(0, CircularButtonPress.holdDuration - elapsed)
                    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                        visualPressed = false
                    }
                }
            }
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
            headerBackground
                .ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if #available(iOS 26.0, *) {
            // Translucent on iOS 26: content scrolling beneath frosts through the bar
            // and the Liquid Glass buttons refract it, for the full glass look. (Older
            // iOS keeps the opaque, seamless bar that matches the surface below.)
            Rectangle().fill(.ultraThinMaterial)
        } else {
            Rectangle().fill(background)
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
            // ignoresSafeArea so the opaque fill reaches the bottom edge (the plain
            // ShapeStyle form leaves the home-indicator strip uncovered).
            .presentationBackground { Color(.systemBackground).ignoresSafeArea() }
    }
}
