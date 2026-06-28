//
//  TrackedWindow.swift
//  OpenMissionControl
//

import ApplicationServices
import CoreGraphics
import Foundation

struct TrackedWindow: Identifiable, Equatable {
    let windowNumber: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect

    var id: CGWindowID { windowNumber }

    init?(from dict: [String: Any]) {
        guard let windowNumber = dict[kCGWindowNumber as String] as? CGWindowID,
              let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
              let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"],
              let y = boundsDict["Y"],
              let width = boundsDict["Width"],
              let height = boundsDict["Height"]
        else {
            return nil
        }

        self.windowNumber = windowNumber
        self.pid = pid
        self.ownerName = dict[kCGWindowOwnerName as String] as? String ?? "Unknown"
        self.title = dict[kCGWindowName as String] as? String ?? ""
        self.bounds = CGRect(x: x, y: y, width: width, height: height)
    }
}
