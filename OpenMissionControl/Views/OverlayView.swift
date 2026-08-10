//
//  OverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 14/3/2026.
//

import SwiftUI

enum OverlayTheme: String, CaseIterable, DisplayNameable {
    case `default`
    case minimal
    case coloredMinimal

    var displayName: String {
        switch self {
        case .default:
            return "Default"
        case .minimal:
            return "Minimal"
        case .coloredMinimal:
            return "Colored Minimal"
        }
    }
}

struct OverlayView: View {
    @AppStorage(SettingsDefaults.Key.overlayTheme) private var currentTheme: OverlayTheme =
        SettingsDefaults.overlayTheme
    @AppStorage(SettingsDefaults.Key.overlayButtonScale) private var overlayButtonScale: Double =
        SettingsDefaults.overlayButtonScale
    var isPreview: Bool = false

    var body: some View {
        let sizing = OverlaySizing(scale: overlayButtonScale)

        Group {
            switch currentTheme {
            case .default:
                DefaultOverlayView(sizing: sizing)
            case .minimal:
                MinimalOverlayView(sizing: sizing)
            case .coloredMinimal:
                ColoredMinimalOverlayView(sizing: sizing)
            }
        }
        .environment(\.isPreview, isPreview)
    }
}

private struct IsPreviewKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isPreview: Bool {
        get { self[IsPreviewKey.self] }
        set { self[IsPreviewKey.self] = newValue }
    }
}
