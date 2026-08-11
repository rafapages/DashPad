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
}
