//
//  WindowIconsOverlayView.swift
//  OpenMissionControl
//

import SwiftUI

struct WindowIconsOverlayView: View {
    @ObservedObject var core: OpenMissionControlCore
    @AppStorage("iconOverlaySize") private var iconSize: Double = 128

    var body: some View {
        let unionFrame = ScreenCoordinates.unionFrame

        GeometryReader { geometry in
            ZStack {
                ForEach(core.trackedWindows) { window in
                    if window.windowNumber != core.hoveredWindow?.windowNumber {
                        let size = CGFloat(iconSize)
                        let icon = core.iconCache.icon(for: window.pid)
                        let position = ScreenCoordinates.iconCenterPosition(
                            bounds: window.bounds,
                            unionFrame: unionFrame
                        )

                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: size, height: size)
                            .position(position)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
