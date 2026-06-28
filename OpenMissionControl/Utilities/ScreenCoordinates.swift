//
//  ScreenCoordinates.swift
//  OpenMissionControl
//

import AppKit
import CoreGraphics

enum ScreenCoordinates {
    static var unionFrame: CGRect {
        NSScreen.screens.reduce(.null) { $0.union($1.frame) }
    }

    static var maxAppKitY: CGFloat {
        NSScreen.screens.map(\.frame.maxY).max() ?? 0
    }

    static func cgTopLeftToAppKitBottomLeft(cgY: CGFloat, height: CGFloat) -> CGFloat {
        maxAppKitY - cgY - height
    }

    /// Center of a CG-window rect in the icon overlay's SwiftUI coordinate space (top-left origin).
    static func iconCenterPosition(bounds: CGRect, unionFrame: CGRect) -> CGPoint {
        let cgUnionTop = maxAppKitY - unionFrame.maxY
        return CGPoint(
            x: bounds.midX - unionFrame.origin.x,
            y: bounds.midY - cgUnionTop
        )
    }
}
