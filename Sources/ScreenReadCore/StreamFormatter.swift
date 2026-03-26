// Sources/ScreenReadCore/StreamFormatter.swift
import Foundation

public enum StreamFormatter {
    public static func formatNodeAsJSONL(_ node: AXNode, depth: Int) -> String {
        var dict: [String: Any] = ["role": node.role, "depth": depth]
        if let t = node.title { dict["title"] = t }
        if let v = node.value { dict["value"] = v }
        if let s = node.subrole { dict["subrole"] = s }
        if let r = node.roleDescription { dict["roleDescription"] = r }
        if let pos = node.position, let x = pos["x"], let y = pos["y"] {
            dict["x"] = Int(x); dict["y"] = Int(y)
        }
        if let sz = node.size, let w = sz["width"], let h = sz["height"] {
            dict["width"] = Int(w); dict["height"] = Int(h)
        }
        if let e = node.isEnabled { dict["isEnabled"] = e }
        if let f = node.isFocused { dict["isFocused"] = f }
        if let s = node.isSelected { dict["isSelected"] = s }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
