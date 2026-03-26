// Tests/ScreenReadCoreTests/FormatterTests.swift
import Testing
@testable import ScreenReadCore

@Suite("Formatter Tests")
struct FormatterTests {

    let sampleTree = AXNode(
        role: "AXWindow",
        title: "Test Window",
        children: [
            AXNode(role: "AXGroup", title: "Navigation", children: [
                AXNode(role: "AXLink", title: "Home", value: nil),
                AXNode(role: "AXLink", title: "About", value: nil),
            ]),
            AXNode(role: "AXStaticText", title: nil, value: "Hello World"),
            AXNode(role: "AXHeading", title: "Main Title", value: nil,
                   roleDescription: "heading"),
        ]
    )

    @Test("Text tree format has correct indentation")
    func textTreeFormat() {
        let output = Formatter.formatTextTree(sampleTree)
        #expect(output.contains("[window] Test Window"))
        #expect(output.contains("  [group] Navigation"))
        #expect(output.contains("    [link] Home"))
        #expect(output.contains("  [statictext] Hello World"))
    }

    @Test("Text-only format strips structure")
    func textOnlyFormat() {
        let output = Formatter.formatTextOnly(sampleTree)
        #expect(output.contains("Test Window"))
        #expect(output.contains("Home"))
        #expect(output.contains("Hello World"))
        #expect(!output.contains("["))
        #expect(!output.contains("]"))
    }

    @Test("JSON format is valid JSON")
    func jsonFormat() {
        let output = Formatter.formatJSON(sampleTree)
        // Valid JSON starts with { and ends with }
        #expect(output.hasPrefix("{"))
        #expect(output.hasSuffix("}"))
    }

    @Test("JSON format contains all fields")
    func jsonContainsFields() {
        let output = Formatter.formatJSON(sampleTree)
        #expect(output.contains("\"role\""))
        #expect(output.contains("\"AXWindow\""))
        #expect(output.contains("\"title\""))
        #expect(output.contains("\"children\""))
    }

    @Test("Empty node formats cleanly")
    func emptyNode() {
        let node = AXNode(role: "AXGroup")
        let output = Formatter.formatTextTree(node)
        #expect(output.contains("[group]"))
    }

    // MARK: - State Flags + Clickable Tests

    let disabledButton = AXNode(role: "AXButton", title: "Delete", position: ["x": 400, "y": 300], size: ["width": 80, "height": 40], isEnabled: false)
    let focusedField = AXNode(role: "AXTextField", title: "Search", value: "hello", position: ["x": 200, "y": 50], size: ["width": 200, "height": 30], isEnabled: true, isFocused: true)
    let enabledButton = AXNode(role: "AXButton", title: "Submit", position: ["x": 440, "y": 310], size: ["width": 80, "height": 40], isEnabled: true)

    var interactiveTree: AXNode {
        AXNode(role: "AXWindow", title: "Test", children: [
            disabledButton,
            focusedField,
            enabledButton,
            AXNode(role: "AXStaticText", value: "Just text")
        ])
    }

    @Test("Text tree shows state flags")
    func textTreeStateFlags() {
        let output = Formatter.formatTextTree(interactiveTree)
        #expect(output.contains("(disabled)"))
        #expect(output.contains("(focused)"))
        #expect(!output.contains("Submit (enabled)"))
    }

    @Test("Clickable format outputs interactive elements")
    func clickableFormat() {
        let output = Formatter.formatClickable(interactiveTree)
        // Submit: x=440+80/2=480, y=310+40/2=330
        #expect(output.contains("480,330"))
        // Search: x=200+200/2=300, y=50+30/2=65
        #expect(output.contains("300,65"))
        #expect(output.contains("disabled"))
        #expect(!output.contains("Just text"))
    }

    @Test("Clickable JSON is valid array")
    func clickableJSONFormat() {
        let output = Formatter.formatClickableJSON(interactiveTree)
        #expect(output.hasPrefix("["))
        #expect(output.hasSuffix("]"))
        #expect(output.contains("\"x\":480"))
        #expect(output.contains("\"x\":300"))
    }
}
