//
//  OpenMissionControlCore.swift
//  OpenMissionControl
//
//  Created by Travis XU on 13/3/2026.
//

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import os
import SwiftUI

@_silgen_name("CoreDockSendNotification")
func CoreDockSendNotification(_ notification: CFString, _ unknown: Int32) -> CGError

protocol DisplayNameable {
    var displayName: String { get }
}

enum WindowAction: Int, CaseIterable, DisplayNameable {
    case none = 0
    case minimize = 1
    case zoom = 2
    case close = 3
    case quit = 4

    var displayName: String {
        switch self {
        case .none: return "None"
        case .minimize: return "Minimize"
        case .zoom: return "Maximize"
        case .close: return "Close"
        case .quit: return "Quit"
        }
    }
}

enum Instigator: Int, CaseIterable, DisplayNameable {
    case overlay
    case keyboard
    case mouse

    var displayName: String {
        switch self {
        case .overlay: return "Overlay Click"
        case .keyboard: return "Keyboard Shortcut"
        case .mouse: return "Mouse Shortcut"
        }
    }
}

final class OpenMissionControlCore: ObservableObject {
    static let shared = OpenMissionControlCore()
    private let logger = Logger(
        subsystem: "dev.travisxu.OpenMissionControl", category: "OpenMissionControlCore"
    )

    // MARK: - Window State

    @Published private(set) var trackedWindows: [TrackedWindow] = []
    let iconCache = AppIconCache()
    private var windowFetchTimer: Timer?
    @AppStorage("showAppIcons") private var showAppIcons: Bool = true
    @AppStorage("updateDuration") private var updateDuration: Double = 0.25
    @AppStorage("shortcutQuit") private var shortcutQuit: Bool = false
    @AppStorage("shortcutClose") private var shortcutClose: Bool = false
    @AppStorage("shortcutMinimize") private var shortcutMinimize: Bool = false
    @AppStorage("shortcutMaximize") private var shortcutMaximize: Bool = false
    @AppStorage("rightClickAction") private var rightClickAction: WindowAction = .none
    @AppStorage("middleClickAction") private var middleClickAction: WindowAction = .none

    // MARK: - Lifecycle

    @Published private(set) var isRunning: Bool = false
    private var axTrustedTimer: Timer?
    private var wasAXTrusted: Bool = AXIsProcessTrusted()

    func start() {
        guard !isRunning else { return }

        isRunning = true

        wasAXTrusted = AXIsProcessTrusted()
        axTrustedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            let isTrusted = AXIsProcessTrusted()
            if let self = self {
                if !self.wasAXTrusted, isTrusted {
                    self.restartApp()
                }
                self.wasAXTrusted = isTrusted
            }
        }

        // Configure Mission Control monitor
        MissionControlMonitor.shared.setHandler { [weak self] state in
            DispatchQueue.main.async {
                self?.handleMissionControlStateChange(state)
            }
        }
        MissionControlMonitor.shared.start()

        // Configure mouse event monitor
        MouseEventMonitor.shared.setClickHandler { [weak self] location, button in
            guard let self = self else { return true }

            self.logger.debug("Mouse clicked at: \(location.x), \(location.y) (button: \(button.rawValue))")
            return self.handleMouseClick(at: location, with: button)
        }
        MouseEventMonitor.shared.setMoveHandler { [weak self] location in
            guard let self = self else { return }

            self.logger.debug("Mouse moved to: \(location.x), \(location.y)")
            self.handleMouseMove(to: location)
        }
        MouseEventMonitor.shared.setKeyHandler { [weak self] flags, keyCode in
            guard let self = self else { return true }

            return self.handleKeyPress(flags: flags, keyCode: keyCode)
        }

        // Listen for active space changes to refresh window list and overlay
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        logger.info("OpenMissionControlCore started.")
    }

    func stop() {
        axTrustedTimer?.invalidate()
        axTrustedTimer = nil
        MissionControlMonitor.shared.stop()
        MouseEventMonitor.shared.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        hideOverlay()
        isRunning = false

        logger.info("OpenMissionControlCore stopped.")
    }

    deinit {
        stop()
    }

    // MARK: - Mission Control State

    private func handleMissionControlStateChange(_ state: MissionControlState) {
        logger.info("Mission Control state changed: \(state.rawValue)")

        if state.isActive {
            isOverlayShown = true
            showOverlay()
        } else {
            isOverlayShown = false
            hideOverlay()
        }
    }

    // MARK: - Active Space Change Handling

    @objc private func activeSpaceDidChange() {
        guard isOverlayShown else { return }

        logger.info("Active space changed, hiding icons until transition completes.")
        beginIconOverlaySpaceTransition()
    }

    // MARK: - Mouse Event Handling

    @discardableResult
    private func handleMouseClick(at location: CGPoint, with button: CGMouseButton) -> Bool {
        guard isOverlayShown else { return true }

        if let rect = overlayRect, rect.contains(location) {
            if button == .left {
                logger.debug("Captured left click inside overlayRect at (\(location.x), \(location.y)).")
                handleOverlayClick(at: location)
                return false
            } else {
                logger.debug("Captured non-left click inside overlayRect at (\(location.x), \(location.y)), skipping.")
                return true
            }
        }

        if let window = hoveredWindow {
            switch(button) {
            case .left:
                logger.debug("Captured left click on hovered window at (\(location.x), \(location.y)).")
                hideOverlay()
                return true
            case .right:
                logger.debug("Captured right click on hovered window at (\(location.x), \(location.y)).")
                performWindowAction(window: window, action: rightClickAction, instigator: .mouse)
                return rightClickAction == .none
            case .center:
                logger.debug("Captured middle click on hovered window at (\(location.x), \(location.y)).")
                performWindowAction(window: window, action: middleClickAction, instigator: .mouse)
                return middleClickAction == .none
            default:
                logger.debug("Captured non-default click (id \(button.rawValue)) on hovered window at (\(location.x), \(location.y)), skipping.")
                return true
            }
        }

        return true
    }

    private func handleMouseMove(to location: CGPoint) {
        updateOverlay(at: location)
    }

    // MARK: - Key Event Handling

    private func handleKeyPress(flags: CGEventFlags, keyCode: CGKeyCode) -> Bool {
        guard isOverlayShown, let window = hoveredWindow else { return true }

        // Check for Command key
        guard flags.contains(.maskCommand) else { return true }

        switch keyCode {
        case 12: // Q
            if shortcutQuit {
                performWindowAction(window: window, action: .quit, instigator: .keyboard)
                return false
            }
        case 13: // W
            if shortcutClose {
                performWindowAction(window: window, action: .close, instigator: .keyboard)
                return false
            }
        case 46: // M
            if shortcutMinimize {
                performWindowAction(window: window, action: .minimize, instigator: .keyboard)
                return false
            }
        case 3: // F
            if shortcutMaximize {
                performWindowAction(window: window, action: .zoom, instigator: .keyboard)
                return false
            }
        default:
            break
        }

        return true
    }

    // MARK: - Window Fetching

    func fetchWindows() {
        let windowList =
            CGWindowListCopyWindowInfo(
                CGWindowListOption.optionOnScreenOnly,
                kCGNullWindowID
            ) as? [[String: Any]] ?? []

        let filteredWindows = windowList.filter { window in
            window[kCGWindowLayer as String] as? Int == 0
        }

        let regularWindows = filteredWindows.filter {
            ($0[kCGWindowOwnerName as String] as? String) != "Dock"
        }

        let tracked = regularWindows.compactMap { TrackedWindow(from: $0) }

        DispatchQueue.main.async {
            if self.trackedWindows != tracked {
                let previous = self.trackedWindows

                if self.isIconOverlaySuppressed {
                    if !previous.isEmpty, !self.hasLargeBoundsChange(from: previous, to: tracked) {
                        self.trackedWindows = tracked
                        self.finishIconOverlaySpaceTransition()
                        return
                    }
                } else if !previous.isEmpty, self.hasLargeBoundsChange(from: previous, to: tracked) {
                    self.beginIconOverlaySpaceTransition()
                }

                self.logger.debug("=== Windows (\(tracked.count)) ===")
                for (index, window) in tracked.enumerated() {
                    self.logger.debug(
                        "[\(index)] \(window.ownerName) - \(window.title) | bounds: \(String(describing: window.bounds))"
                    )
                }

                self.trackedWindows = tracked
            }

            guard !self.isIconOverlaySuppressed else { return }

            self.updateIconOverlayFrame()
        }
    }

    private func hasLargeBoundsChange(from old: [TrackedWindow], to new: [TrackedWindow]) -> Bool {
        let oldById = Dictionary(uniqueKeysWithValues: old.map { ($0.windowNumber, $0) })

        for window in new {
            guard let previous = oldById[window.windowNumber] else { continue }

            let deltaX = abs(previous.bounds.midX - window.bounds.midX)
            let deltaY = abs(previous.bounds.midY - window.bounds.midY)
            if deltaX > 20 || deltaY > 20 {
                return true
            }
        }

        return false
    }

    // MARK: - Overlay Management

    private var overlayWindow: NSWindow?
    private var iconOverlayWindow: NSWindow?
    private var iconOverlayResumeTimer: Timer?
    private var isIconOverlaySuppressed = false
    private static let spaceTransitionIconDelay: TimeInterval = 0.1
    private(set) var overlayRect: CGRect?
    @Published private(set) var hoveredWindow: TrackedWindow?

    @Published private(set) var isOverlayShown: Bool = false
    @Published private(set) var isOverlayHovered: Bool = false

    func updateOverlay(at mouseLocation: CGPoint) {
        guard isOverlayShown else {
            return
        }

        DispatchQueue.main.async { [self] in
            if let rect = overlayRect {
                let isHovering = rect.contains(mouseLocation)
                if isOverlayHovered != isHovering {
                    isOverlayHovered = isHovering
                }
            }

            // Find window under mouse
            for window in trackedWindows {
                let windowFrame = window.bounds

                // Check if mouse is within this window's bounds
                if windowFrame.contains(mouseLocation) {
                    let x = windowFrame.origin.x
                    let y = windowFrame.origin.y
                    let convertedY = ScreenCoordinates.cgTopLeftToAppKitBottomLeft(cgY: y, height: 40)

                    let showQuit = UserDefaults.standard.object(forKey: "showQuitButton") as? Bool ?? false
                    let showClose = UserDefaults.standard.object(forKey: "showCloseButton") as? Bool ?? true
                    let showMinimize = UserDefaults.standard.object(forKey: "showMinimizeButton") as? Bool ?? true
                    let showZoom = UserDefaults.standard.object(forKey: "showZoomButton") as? Bool ?? true
                    let buttonCount = [showQuit, showClose, showMinimize, showZoom].filter { $0 }.count
                    let overlayWidth = CGFloat(12 + buttonCount * 32)

                    let newFrame = NSRect(x: x + 8, y: convertedY - 8, width: overlayWidth, height: 40)
                    overlayWindow?.setFrame(newFrame, display: true)
                    overlayWindow?.orderFront(nil)

                    let cgOverlayRect = CGRect(x: x + 8, y: y + 8, width: overlayWidth, height: 40)
                    overlayRect = cgOverlayRect
                    hoveredWindow = window

                    overlayWindow?.orderFront(nil)
                    orderIconOverlayBelowActionOverlay()
                    return
                }
            }

            hoveredWindow = nil
            overlayWindow?.orderOut(nil)
        }
    }

    func handleOverlayClick(at location: CGPoint) {
        guard let rect = overlayRect, let window = hoveredWindow else { return }

        let localX = location.x - rect.minX
        var currentX: CGFloat = 8

        let showQuit = UserDefaults.standard.object(forKey: "showQuitButton") as? Bool ?? false
        let showClose = UserDefaults.standard.object(forKey: "showCloseButton") as? Bool ?? true
        let showMinimize =
            UserDefaults.standard.object(forKey: "showMinimizeButton") as? Bool ?? true
        let showZoom = UserDefaults.standard.object(forKey: "showZoomButton") as? Bool ?? true

        if showQuit {
            if localX >= currentX, localX <= currentX + 24 {
                performWindowAction(window: window, action: .quit, instigator: .overlay)
            }
            currentX += 32
        }

        if showClose {
            if localX >= currentX, localX <= currentX + 24 {
                performWindowAction(window: window, action: .close, instigator: .overlay)
            }
            currentX += 32
        }

        if showMinimize {
            if localX >= currentX, localX <= currentX + 24 {
                performWindowAction(window: window, action: .minimize, instigator: .overlay)
            }
            currentX += 32
        }

        if showZoom {
            if localX >= currentX, localX <= currentX + 24 {
                performWindowAction(window: window, action: .zoom, instigator: .overlay)
            }
            currentX += 32
        }
    }

    private func performWindowAction(window: TrackedWindow, action: WindowAction, instigator: Instigator) {
        let windowName = window.title

        switch(action) {
        case .quit:
            logger.info("\(instigator.displayName) Quit triggered on window: \(windowName)")
            quitApplication(window: window)
        case .minimize:
            logger.info("\(instigator.displayName) Minimize triggered on window: \(windowName)")
            performOSWindowAction(window: window, action: kAXMinimizeButtonAttribute)
        case .zoom:
            logger.info("\(instigator.displayName) Maximize triggered on window: \(windowName)")
            _ = CoreDockSendNotification("com.apple.expose.awake" as CFString, 0)
            hideOverlay()
            performOSWindowAction(window: window, action: kAXZoomButtonAttribute)
        case .close:
            logger.info("\(instigator.displayName) Close triggered on window: \(windowName)")
            performOSWindowAction(window: window, action: kAXCloseButtonAttribute)
        default:
            break
        }
    }

    private func performOSWindowAction(window: TrackedWindow, action: String) {
        let pid = window.pid
        let windowID = window.windowNumber

        let app = AXUIElementCreateApplication(pid)
        let windows = (try? app.windows()) ?? []
        logger.debug("AXUIElement windows for PID \(pid): \(windows.count)")

        for axWindow in windows {
            if let axWindowId = try? axWindow.cgWindowId(), axWindowId == windowID {
                do {
                    if let button = try? axWindow.attribute(action, AXUIElement.self) {
                        try button.performAction(kAXPressAction)
                        logger.info(
                            "Performed \(action) on window with PID \(pid) and WindowID \(windowID)"
                        )
                    } else {
                        logger.error(
                            "Failed to get \(action) for window with PID \(pid) and WindowID \(windowID)"
                        )
                    }
                } catch {
                    logger.error(
                        "Failed to perform action \(action) on window: \(error.localizedDescription)"
                    )
                }

                return
            }
        }

        logger.warning(
            "No matching AXUIElement found for window with PID \(pid) and WindowID \(windowID)"
        )
    }

    private func quitApplication(window: TrackedWindow) {
        let pid = window.pid

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
            logger.info("Terminated application with PID \(pid)")
        } else {
            logger.error("Failed to get NSRunningApplication for PID \(pid)")
        }
    }

    func showOverlay() {
        // TODO: Optimize by only fetching windows when necessary
        if windowFetchTimer == nil {
            fetchWindows()

            windowFetchTimer = Timer.scheduledTimer(withTimeInterval: updateDuration, repeats: true) { [weak self] _ in
                self?.fetchWindows()
            }
        }

        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OverlayView())
            overlayWindow = window
        }

        showIconOverlay()

        // Start mouse monitoring when overlay is visible
        MouseEventMonitor.shared.start()

        // Do an initial overlay update with current mouse position
        if let mouseLocation = CGEvent(source: nil)?.location {
            updateOverlay(at: mouseLocation)
        }
    }

    func hideOverlay() {
        windowFetchTimer?.invalidate()
        windowFetchTimer = nil
        iconOverlayResumeTimer?.invalidate()
        iconOverlayResumeTimer = nil
        isIconOverlaySuppressed = false
        overlayWindow?.orderOut(nil)
        hideIconOverlay()
        trackedWindows = []
        MouseEventMonitor.shared.stop()
    }

    func recreateOverlay() {
        overlayWindow?.close()
        overlayWindow = nil
        iconOverlayWindow?.close()
        iconOverlayWindow = nil

        showOverlay()
    }

    // MARK: - Icon Overlay Management

    private func showIconOverlay() {
        guard showAppIcons, !isIconOverlaySuppressed else { return }

        let unionFrame = ScreenCoordinates.unionFrame

        if iconOverlayWindow == nil {
            let window = NSWindow(
                contentRect: unionFrame,
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
            window.contentView = NSHostingView(rootView: WindowIconsOverlayView(core: self))
            iconOverlayWindow = window
        }

        iconOverlayWindow?.setFrame(unionFrame, display: true)
        iconOverlayWindow?.orderFront(nil)
        orderIconOverlayBelowActionOverlay()
    }

    private func hideIconOverlay() {
        iconOverlayResumeTimer?.invalidate()
        iconOverlayResumeTimer = nil
        iconOverlayWindow?.orderOut(nil)
        iconOverlayWindow?.close()
        iconOverlayWindow = nil
        iconCache.clear()
    }

    private func beginIconOverlaySpaceTransition() {
        guard showAppIcons, iconOverlayWindow != nil || isOverlayShown else { return }

        isIconOverlaySuppressed = true
        iconOverlayWindow?.orderOut(nil)
        scheduleIconOverlayResume()
    }

    private func scheduleIconOverlayResume() {
        iconOverlayResumeTimer?.invalidate()
        iconOverlayResumeTimer = Timer.scheduledTimer(
            withTimeInterval: Self.spaceTransitionIconDelay,
            repeats: false
        ) { [weak self] _ in
            self?.finishIconOverlaySpaceTransition()
        }
    }

    private func finishIconOverlaySpaceTransition() {
        iconOverlayResumeTimer?.invalidate()
        iconOverlayResumeTimer = nil

        guard isOverlayShown else {
            isIconOverlaySuppressed = false
            return
        }

        isIconOverlaySuppressed = false
        showIconOverlay()
        updateIconOverlayFrame()

        if let mouseLocation = CGEvent(source: nil)?.location {
            updateOverlay(at: mouseLocation)
        }
    }

    private func updateIconOverlayFrame() {
        guard iconOverlayWindow != nil, showAppIcons else { return }

        let unionFrame = ScreenCoordinates.unionFrame
        iconOverlayWindow?.setFrame(unionFrame, display: true)
        orderIconOverlayBelowActionOverlay()
    }

    private func orderIconOverlayBelowActionOverlay() {
        guard let iconOverlayWindow, let overlayWindow else { return }

        iconOverlayWindow.order(.below, relativeTo: overlayWindow.windowNumber)
    }

    func refreshIconOverlayVisibility() {
        guard isOverlayShown else { return }

        if showAppIcons {
            showIconOverlay()
        } else {
            hideIconOverlay()
        }
    }

    private func restartApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }
}
