//
//  ScreenCoordinates.swift
//  OpenMissionControl
//

import AppKit
import CoreGraphics

enum ScreenCoordinates {
    static var maxAppKitY: CGFloat {
        NSScreen.screens.map(\.frame.maxY).max() ?? 0
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
            return 0
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    static func appKitFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        NSScreen.screens.first { self.displayID(of: $0) == displayID }?.frame
    }

    static func displayID(containingWindowBounds bounds: CGRect) -> CGDirectDisplayID? {
        var bestID: CGDirectDisplayID?
        var bestArea: CGFloat = 0

        for screen in NSScreen.screens {
            let id = displayID(of: screen)
            let intersection = bounds.intersection(CGDisplayBounds(id))
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestID = id
            }
        }

        return bestID
    }

    static func cgTopLeftToAppKitBottomLeft(cgY: CGFloat, height: CGFloat) -> CGFloat {
        maxAppKitY - cgY - height
    }

    /// Center of a CG-window rect in an overlay's SwiftUI coordinate space (top-left origin).
    static func iconCenterPosition(bounds: CGRect, overlayFrame: CGRect) -> CGPoint {
        let cgOverlayTop = maxAppKitY - overlayFrame.maxY
        return CGPoint(
            x: bounds.midX - overlayFrame.origin.x,
            y: bounds.midY - cgOverlayTop
        )
    }
}
