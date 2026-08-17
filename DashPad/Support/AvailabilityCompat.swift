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

// MARK: - Container-relative sizing

/// Carries a container's measured height down to descendants that need to size themselves
/// against it on iOS 16. Unused on iOS 17+, where `containerRelativeFrame` does this natively.
struct ContainerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Publishes this view's height under `ContainerHeightKey` so a descendant can size itself
    /// relative to it via `relativeContainerHeight(_:measuredContainerHeight:)` on iOS 16.
    /// No-ops on iOS 17+, where `containerRelativeFrame` measures its own container and the
    /// GeometryReader would be laying out and publishing a value nothing reads.
    @ViewBuilder
    func measureContainerHeight() -> some View {
        if #available(iOS 17.0, *) {
            self
        } else {
            background(
                GeometryReader { geo in
                    Color.clear.preference(key: ContainerHeightKey.self, value: geo.size.height)
                }
            )
        }
    }

    /// Sizes the view to `fraction` of its scroll container's height.
    /// `containerRelativeFrame(_:alignment:_:)` is iOS 17+; on iOS 16 the caller passes the
    /// height it measured with `measureContainerHeight()`. Before the first measurement lands
    /// the view keeps its natural size rather than collapsing to zero.
    @ViewBuilder
    func relativeContainerHeight(_ fraction: CGFloat, measuredContainerHeight: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            containerRelativeFrame(.vertical) { height, _ in height * fraction }
        } else if measuredContainerHeight > 0 {
            frame(height: measuredContainerHeight * fraction)
        } else {
            self
        }
    }
}

// MARK: - ContentUnavailableView

/// Stand-in for `ContentUnavailableView`, which is iOS 17+. The fallback reproduces the
/// system layout closely enough for the one placeholder this app shows (the empty
/// settings detail pane), without trying to be a general-purpose replacement.
struct EmptyStatePlaceholder: View {
    let title: String
    let systemImage: String

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(title, systemImage: systemImage)
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
