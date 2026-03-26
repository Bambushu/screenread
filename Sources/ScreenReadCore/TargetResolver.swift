// Sources/ScreenReadCore/TargetResolver.swift
import Foundation
import ApplicationServices
import AppKit

public final class TargetResolver: Sendable {

    public init() {}

    // MARK: - List Windows

    public func listWindows() -> [WindowInfo] {
        var results: [WindowInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let appName = app.localizedName else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows = getWindowTitles(appElement)
            if windows.isEmpty {
                results.append(WindowInfo(
                    app: appName,
                    pid: app.processIdentifier,
                    title: "(no windows)",
                    bundleId: app.bundleIdentifier
                ))
            } else {
                for title in windows {
                    results.append(WindowInfo(
                        app: appName,
                        pid: app.processIdentifier,
                        title: title,
                        bundleId: app.bundleIdentifier
                    ))
                }
            }
        }
        return results
    }

    // MARK: - Resolve Targets

    public func resolveFrontmost() throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw ScreenReadError.noAccessibilityPermission
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ScreenReadError.appNotFound("frontmost", suggestions: [])
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    public func resolveApp(_ name: String) throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw ScreenReadError.noAccessibilityPermission
        }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let lowered = name.lowercased()

        // Exact match first
        if let match = apps.first(where: { $0.localizedName?.lowercased() == lowered }) {
            return AXUIElementCreateApplication(match.processIdentifier)
        }

        // Substring match
        if let match = apps.first(where: { $0.localizedName?.lowercased().contains(lowered) == true }) {
            return AXUIElementCreateApplication(match.processIdentifier)
        }

        // No match — find suggestions
        let suggestions = apps.compactMap { $0.localizedName }
            .filter { levenshtein($0.lowercased(), lowered) <= 3 }
            .prefix(3)
        throw ScreenReadError.appNotFound(name, suggestions: Array(suggestions))
    }

    public func resolveWindow(_ title: String) throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw ScreenReadError.noAccessibilityPermission
        }
        let lowered = title.lowercased()
        var allTitles: [String] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows = getAXWindows(appElement) else { continue }

            for window in windows {
                if let windowTitle = getStringAttribute(window, kAXTitleAttribute as CFString) {
                    allTitles.append(windowTitle)
                    if windowTitle.lowercased().contains(lowered) {
                        return window
                    }
                }
            }
        }

        let suggestions = allTitles
            .filter { $0.lowercased().contains(lowered.prefix(3)) }
            .prefix(3)
        throw ScreenReadError.windowNotFound(title, suggestions: Array(suggestions))
    }

    public func resolvePID(_ pid: pid_t) throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw ScreenReadError.noAccessibilityPermission
        }
        let apps = NSWorkspace.shared.runningApplications
        guard apps.contains(where: { $0.processIdentifier == pid }) else {
            throw ScreenReadError.pidNotFound(pid)
        }
        return AXUIElementCreateApplication(pid)
    }

    // MARK: - Get First Window of App Element

    public func firstWindow(_ appElement: AXUIElement) throws -> AXUIElement {
        guard let windows = getAXWindows(appElement), let first = windows.first else {
            throw ScreenReadError.noWindows("app")
        }
        return first
    }

    // MARK: - Private Helpers

    private func getAXWindows(_ appElement: AXUIElement) -> [AXUIElement]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func getWindowTitles(_ appElement: AXUIElement) -> [String] {
        guard let windows = getAXWindows(appElement) else { return [] }
        return windows.compactMap { getStringAttribute($0, kAXTitleAttribute as CFString) }
    }

    func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dist = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                dist[i][j] = min(dist[i-1][j] + 1, dist[i][j-1] + 1, dist[i-1][j-1] + cost)
            }
        }
        return dist[a.count][b.count]
    }
}
