// Sources/ScreenReadCore/AXHelpers.swift
import Foundation
import ApplicationServices

/// Shared accessor for string attributes on AXUIElement.
/// Used by both TargetResolver and AXTreeWalker to avoid duplication.
func axStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard result == .success else { return nil }
    if let str = value as? String { return str }
    if let num = value as? NSNumber { return num.stringValue }
    return nil
}
