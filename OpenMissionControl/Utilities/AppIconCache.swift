//
//  AppIconCache.swift
//  OpenMissionControl
//

import AppKit

final class AppIconCache {
    private var cache: [String: NSImage] = [:]
    private static let placeholder = NSImage(named: NSImage.applicationIconName)!

    func icon(for pid: pid_t) -> NSImage {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return Self.placeholder
        }

        let key = app.bundleIdentifier ?? "pid:\(pid)"
        if let cached = cache[key] {
            return cached
        }

        let resolved: NSImage
        if let appIcon = app.icon {
            resolved = appIcon
        } else if let bundleURL = app.bundleURL {
            resolved = NSWorkspace.shared.icon(forFile: bundleURL.path)
        } else {
            resolved = Self.placeholder
        }

        cache[key] = resolved
        return resolved
    }

    func clear() {
        cache.removeAll()
    }
}
