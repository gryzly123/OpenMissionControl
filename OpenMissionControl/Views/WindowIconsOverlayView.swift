//
//  WindowIconsOverlayView.swift
//  OpenMissionControl
//

import CoreGraphics
import SwiftUI

struct WindowIconsOverlayView: View {
    @ObservedObject var model: IconOverlayDisplayModel
    @AppStorage(SettingsDefaults.Key.iconOverlaySize) private var iconSize: Double =
        SettingsDefaults.iconOverlaySize
    @AppStorage(SettingsDefaults.Key.showIconOverlayShadow) private var showIconShadow: Bool =
        SettingsDefaults.showIconOverlayShadow

    var body: some View {
        ZStack {
            ForEach(model.icons) { item in
                let size = CGFloat(iconSize)
                let position = ScreenCoordinates.iconCenterPosition(
                    bounds: item.bounds,
                    overlayFrame: model.overlayFrame
                )

                iconImage(item.image, size: size, shadow: showIconShadow)
                    .position(position)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func iconImage(_ image: NSImage, size: CGFloat, shadow: Bool) -> some View {
        let icon = Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)

        if shadow {
            icon.shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
        } else {
            icon
        }
    }
}
