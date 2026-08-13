//
//  IconOverlayController.swift
//  OpenMissionControl
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI

struct IconOverlayItem: Identifiable {
    let id: CGWindowID
    let image: NSImage
    let bounds: CGRect
}

final class IconOverlayDisplayModel: ObservableObject {
    let displayID: CGDirectDisplayID
    @Published var overlayFrame: CGRect
    @Published var icons: [IconOverlayItem] = []

    init(displayID: CGDirectDisplayID, overlayFrame: CGRect) {
        self.displayID = displayID
        self.overlayFrame = overlayFrame
    }
}

final class IconOverlayController {
    private var overlayWindows: [CGDirectDisplayID: NSWindow] = [:]
    private var displayModels: [CGDirectDisplayID: IconOverlayDisplayModel] = [:]
    private var currentWindowsByDisplay: [CGDirectDisplayID: [TrackedWindow]] = [:]
    private var previousWindowsByDisplay: [CGDirectDisplayID: [TrackedWindow]] = [:]
    private var stableDisplayIDs: Set<CGDirectDisplayID> = []
    private var hoveredWindowNumber: CGWindowID?
    private let iconCache = AppIconCache()
    private var isShown = false

    private static let boundsStabilityThreshold: CGFloat = 1

    func show(
        windows: [TrackedWindow],
        hoveredWindow: TrackedWindow?,
        below actionOverlayWindow: NSWindow?
    ) {
        isShown = true
        syncOverlayWindows(below: actionOverlayWindow)
        update(windows: windows, hoveredWindow: hoveredWindow, below: actionOverlayWindow)
    }

    func update(
        windows: [TrackedWindow],
        hoveredWindow: TrackedWindow?,
        below actionOverlayWindow: NSWindow?
    ) {
        guard isShown else { return }

        syncOverlayWindows(below: actionOverlayWindow)
        updateWindowSnapshot(windows: windows, hoveredWindow: hoveredWindow)
    }

    func updateHoveredWindow(_ hoveredWindow: TrackedWindow?) {
        guard isShown else { return }

        hoveredWindowNumber = hoveredWindow?.windowNumber
        renderIcons()
    }

    func hide() {
        isShown = false

        for window in overlayWindows.values {
            window.orderOut(nil)
            window.close()
        }

        overlayWindows.removeAll()
        displayModels.removeAll()
        currentWindowsByDisplay.removeAll()
        previousWindowsByDisplay.removeAll()
        stableDisplayIDs.removeAll()
        hoveredWindowNumber = nil
        iconCache.clear()
    }

    func orderBelow(_ actionOverlayWindow: NSWindow?) {
        guard let actionOverlayWindow else { return }

        for window in overlayWindows.values {
            window.order(.below, relativeTo: actionOverlayWindow.windowNumber)
        }
    }

    private func syncOverlayWindows(below actionOverlayWindow: NSWindow?) {
        var activeIDs: Set<CGDirectDisplayID> = []

        for screen in NSScreen.screens {
            let id = ScreenCoordinates.displayID(of: screen)
            activeIDs.insert(id)

            let model = displayModel(for: id, overlayFrame: screen.frame)
            model.overlayFrame = screen.frame

            if overlayWindows[id] == nil {
                overlayWindows[id] = makeOverlayWindow(on: screen, model: model)
            }

            overlayWindows[id]?.setFrame(screen.frame, display: true)
            overlayWindows[id]?.orderFront(nil)
        }

        let staleIDs = overlayWindows.keys.filter { !activeIDs.contains($0) }
        for id in staleIDs {
            overlayWindows[id]?.orderOut(nil)
            overlayWindows[id]?.close()
            overlayWindows.removeValue(forKey: id)
            displayModels.removeValue(forKey: id)
            currentWindowsByDisplay.removeValue(forKey: id)
            previousWindowsByDisplay.removeValue(forKey: id)
            stableDisplayIDs.remove(id)
        }

        orderBelow(actionOverlayWindow)
    }

    private func displayModel(
        for displayID: CGDirectDisplayID,
        overlayFrame: CGRect
    ) -> IconOverlayDisplayModel {
        if let model = displayModels[displayID] {
            return model
        }

        let model = IconOverlayDisplayModel(displayID: displayID, overlayFrame: overlayFrame)
        displayModels[displayID] = model
        return model
    }

    private func makeOverlayWindow(
        on screen: NSScreen,
        model: IconOverlayDisplayModel
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: WindowIconsOverlayView(model: model))
        return window
    }

    private func updateWindowSnapshot(
        windows: [TrackedWindow],
        hoveredWindow: TrackedWindow?
    ) {
        let windowsByDisplay = groupWindowsByDisplay(windows)
        var nextStableDisplayIDs: Set<CGDirectDisplayID> = []

        for displayID in displayModels.keys {
            let currentWindows = windowsByDisplay[displayID] ?? []
            let previousWindows = previousWindowsByDisplay[displayID] ?? []

            if areWindowsStable(from: previousWindows, to: currentWindows) {
                nextStableDisplayIDs.insert(displayID)
            }

            previousWindowsByDisplay[displayID] = currentWindows
        }

        currentWindowsByDisplay = windowsByDisplay
        stableDisplayIDs = nextStableDisplayIDs
        hoveredWindowNumber = hoveredWindow?.windowNumber
        renderIcons()
    }

    private func renderIcons() {
        for (displayID, model) in displayModels {
            guard stableDisplayIDs.contains(displayID) else {
                model.icons = []
                continue
            }

            let currentWindows = currentWindowsByDisplay[displayID] ?? []
            model.icons = currentWindows.compactMap { window in
                guard window.windowNumber != hoveredWindowNumber else { return nil }

                return IconOverlayItem(
                    id: window.windowNumber,
                    image: iconCache.icon(for: window.pid),
                    bounds: window.bounds
                )
            }
        }
    }

    private func groupWindowsByDisplay(_ windows: [TrackedWindow]) -> [CGDirectDisplayID: [TrackedWindow]] {
        var windowsByDisplay: [CGDirectDisplayID: [TrackedWindow]] = [:]

        for window in windows {
            guard let displayID = ScreenCoordinates.displayID(containingWindowBounds: window.bounds) else {
                continue
            }

            windowsByDisplay[displayID, default: []].append(window)
        }

        return windowsByDisplay
    }

    private func areWindowsStable(
        from previous: [TrackedWindow],
        to current: [TrackedWindow]
    ) -> Bool {
        guard !previous.isEmpty, !current.isEmpty, previous.count == current.count else {
            return false
        }

        var previousById: [CGWindowID: TrackedWindow] = [:]
        for window in previous {
            previousById[window.windowNumber] = window
        }

        return current.allSatisfy { window in
            guard let prior = previousById[window.windowNumber] else { return false }

            let deltaX = abs(prior.bounds.midX - window.bounds.midX)
            let deltaY = abs(prior.bounds.midY - window.bounds.midY)
            return deltaX <= Self.boundsStabilityThreshold
                && deltaY <= Self.boundsStabilityThreshold
        }
    }
}
