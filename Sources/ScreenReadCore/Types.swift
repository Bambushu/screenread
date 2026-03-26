// Sources/ScreenReadCore/Types.swift
import Foundation
import ApplicationServices
import AppKit

// MARK: - Targeting

public enum TargetMode: Sendable {
    case frontmost
    case app(String)
    case window(String)
    case pid(pid_t)
    case list
}

// MARK: - Output

public enum OutputFormat: Sendable {
    case textTree
    case textOnly
    case json
}

// MARK: - AX Node

public struct AXNode: Sendable, Codable {
    public let role: String
    public let subrole: String?
    public let title: String?
    public let value: String?
    public let roleDescription: String?
    public let position: [String: Double]?
    public let size: [String: Double]?
    public var children: [AXNode]

    public init(
        role: String,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        roleDescription: String? = nil,
        position: [String: Double]? = nil,
        size: [String: Double]? = nil,
        children: [AXNode] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.roleDescription = roleDescription
        self.position = position
        self.size = size
        self.children = children
    }
}

// MARK: - Window Info (for --list)

public struct WindowInfo: Sendable, Codable {
    public let app: String
    public let pid: Int32
    public let title: String
    public let bundleId: String?

    public init(app: String, pid: Int32, title: String, bundleId: String?) {
        self.app = app
        self.pid = pid
        self.title = title
        self.bundleId = bundleId
    }
}

// MARK: - Errors

public enum ScreenReadError: Error, CustomStringConvertible {
    case noAccessibilityPermission
    case appNotFound(String, suggestions: [String])
    case windowNotFound(String, suggestions: [String])
    case pidNotFound(pid_t)
    case noWindows(String)
    case timeout(String)
    case emptyTree

    public var description: String {
        switch self {
        case .noAccessibilityPermission:
            return "ScreenRead needs Accessibility access. Grant it in System Preferences → Privacy & Security → Accessibility."
        case .appNotFound(let name, let suggestions):
            let hint = suggestions.isEmpty ? "" : " Did you mean: \(suggestions.joined(separator: ", "))?"
            return "No app matching '\(name)'.\(hint)"
        case .windowNotFound(let title, let suggestions):
            let hint = suggestions.isEmpty ? "" : " Did you mean: \(suggestions.joined(separator: ", "))?"
            return "No window matching '\(title)'.\(hint)"
        case .pidNotFound(let pid):
            return "No process found with PID \(pid)."
        case .noWindows(let app):
            return "App '\(app)' has no open windows."
        case .timeout(let app):
            return "App '\(app)' is not responding (timed out after 2s)."
        case .emptyTree:
            return "Window found but accessibility tree is empty (app may not support accessibility)."
        }
    }
}
