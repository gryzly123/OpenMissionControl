//
//  ColoredMinimalOverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 25/3/2026.
//

import SwiftUI

struct ColoredMinimalOverlayView: View {
    @ObservedObject private var openMissionControlCore = OpenMissionControlCore.shared

    @AppStorage(SettingsDefaults.Key.showQuitButton) private var showQuitButton: Bool =
        SettingsDefaults.showQuitButton
    @AppStorage(SettingsDefaults.Key.showCloseButton) private var showCloseButton: Bool =
        SettingsDefaults.showCloseButton
    @AppStorage(SettingsDefaults.Key.showMinimizeButton) private var showMinimizeButton: Bool =
        SettingsDefaults.showMinimizeButton
    @AppStorage(SettingsDefaults.Key.showZoomButton) private var showZoomButton: Bool =
        SettingsDefaults.showZoomButton

    var body: some View {
        HStack(spacing: 8) {
            if showQuitButton {
                overlayIcon(color: .purple, icon: "power", iconSize: 10)
            }

            if showCloseButton {
                overlayIcon(color: .red, icon: "xmark", iconSize: 12)
            }

            if showMinimizeButton {
                overlayIcon(color: .yellow, icon: "minus", iconSize: 15)
            }

            if showZoomButton {
                overlayIcon(color: .green, icon: "arrow.up.backward.and.arrow.down.forward", iconSize: 12)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func overlayIcon(color: Color, icon: String, iconSize: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .bold))
            .foregroundColor(color)
            .frame(width: 24, height: 24)
    }
}
