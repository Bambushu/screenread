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
}
