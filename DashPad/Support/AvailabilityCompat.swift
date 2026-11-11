// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// AvailabilityCompat.swift - Back-deployment shims for APIs newer than the deployment target.
// Each helper applies the modern modifier where available and falls back to the system default otherwise.

import SwiftUI

extension View {
    /// Clears the background of a navigation container so the sheet's material shows through.
    /// `containerBackground(_:for:)` with navigation placements is iOS 18+; earlier releases
    /// keep the standard opaque background.
    @ViewBuilder
    func clearNavigationBackground() -> some View {
        if #available(iOS 18.0, *) {
            containerBackground(.clear, for: .navigation)
        } else {
            self
        }
    }

    /// Split-view counterpart of `clearNavigationBackground()`.
    @ViewBuilder
    func clearNavigationSplitViewBackground() -> some View {
        if #available(iOS 18.0, *) {
            containerBackground(.clear, for: .navigationSplitView)
        } else {
            self
        }
    }

    /// Pins a sheet to the centred panel size the app has always presented, rather than
    /// letting each iPadOS release pick for it. iPadOS 18 made the narrow *form* sheet the
    /// default, iPadOS 27 applies that default to sheets that used to come up page-sized, and
    /// `.page` itself now fills the screen. A form sheet is narrow enough to report a compact
    /// horizontal size class, which collapses `NavigationSplitView` into a single column.
    /// `presentationSizing(_:)` is iOS 18+; on 15 to 17 the page-sized sheet is the default
    /// and already close to this size.
    @ViewBuilder
    func centredSheetSizing() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(CentredSheetSizing())
        } else {
            self
        }
    }

    /// Draws a list row's badge as a filled capsule rather than plain secondary text.
    /// `badgeProminence(_:)` is iOS 17+; earlier releases keep the standard text badge.
    @ViewBuilder
    func increasedBadgeProminence() -> some View {
        if #available(iOS 17.0, *) {
            badgeProminence(.increased)
        } else {
            self
        }
    }

    /// `onChange(of:)` without the old value, which no call site in this app needs.
    /// The two-parameter closure is iOS 17+; the single-parameter `perform:` overload it
    /// replaced is deprecated there, so each is used only on the release that prefers it.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

// MARK: - Sheet sizing

/// The size behind `centredSheetSizing()`: the classic iPad page sheet, roughly two thirds of
/// an 11-inch screen in landscape. Comfortably wider than the ~640pt where iPadOS switches a
/// presentation to the compact horizontal size class, so the settings split view keeps its
/// sidebar beside the detail pane.
///
/// The size is stated in points rather than as a fraction of the screen because
/// `PresentationSizingContext` carries nothing about the container. The system clamps the
/// proposal to the space it has, so smaller iPads and portrait orientation get less than this
/// without the sheet overflowing.
@available(iOS 18.0, *)
struct CentredSheetSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        ProposedViewSize(width: 800, height: 640)
    }
}

// MARK: - ContentUnavailableView

/// Stand-in for `ContentUnavailableView`, which is iOS 17+. The fallback reproduces the
/// system layout closely enough for the placeholders this app shows (the empty settings
/// detail pane, the dashboard load failure), without trying to be a general-purpose replacement.
struct EmptyStatePlaceholder: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    /// An optional button below the description, e.g. a way out of the dashboard load failure.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let description { Text(description) }
            } actions: {
                actionButton
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                actionButton
                    .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            if #available(iOS 26, *) {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - iOS 15 fallbacks

extension View {
    /// Hides a scrolling container's opaque background so the sheet's material shows through.
    /// `scrollContentBackground(_:)` is iOS 16+; iOS 15 keeps the standard grouped background.
    @ViewBuilder
    func hiddenScrollContentBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

extension Color {
    /// The colour's subtle system gradient, as used by the Settings app's icon badges.
    /// `Color.gradient` is iOS 16+; iOS 15 fills with the flat colour.
    var gradientCompat: AnyShapeStyle {
        if #available(iOS 16.0, *) {
            AnyShapeStyle(gradient)
        } else {
            AnyShapeStyle(self)
        }
    }
}

/// `LabeledContent` for a title paired with trailing content. It is iOS 16+; on iOS 15 the
/// same leading-title, trailing-content form row is laid out by hand.
struct LabeledRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            LabeledContent(title) { content }
        } else {
            HStack {
                Text(title)
                Spacer(minLength: 16)
                content
            }
        }
    }
}

/// `NavigationStack`, which is iOS 16+. iOS 15 gets the stack-style `NavigationView` it replaced.
struct NavigationStackCompat<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

/// `UnevenRoundedRectangle`, which is iOS 16+, with the same per-corner initialiser so call
/// sites read identically. iOS 15 draws the outline itself with circular rather than
/// continuous corners, a difference too small to notice at the radii this app uses.
struct UnevenRoundedRectangleCompat: InsettableShape {
    var topLeadingRadius: CGFloat
    var bottomLeadingRadius: CGFloat
    var bottomTrailingRadius: CGFloat
    var topTrailingRadius: CGFloat
    private var insetAmount: CGFloat = 0

    init(topLeadingRadius: CGFloat, bottomLeadingRadius: CGFloat,
         bottomTrailingRadius: CGFloat, topTrailingRadius: CGFloat) {
        self.topLeadingRadius = topLeadingRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.topTrailingRadius = topTrailingRadius
    }

    func path(in rect: CGRect) -> Path {
        if #available(iOS 16.0, *) {
            return UnevenRoundedRectangle(
                topLeadingRadius: topLeadingRadius, bottomLeadingRadius: bottomLeadingRadius,
                bottomTrailingRadius: bottomTrailingRadius, topTrailingRadius: topTrailingRadius
            )
            .inset(by: insetAmount)
            .path(in: rect)
        }

        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let tl = max(0, topLeadingRadius - insetAmount)
        let bl = max(0, bottomLeadingRadius - insetAmount)
        let br = max(0, bottomTrailingRadius - insetAmount)
        let tr = max(0, topTrailingRadius - insetAmount)

        var path = Path()
        path.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: tr)
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: br)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: bl)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: tl)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Self {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
