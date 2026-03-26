// Tests/ScreenReadCoreTests/TargetResolverTests.swift
import Testing
@testable import ScreenReadCore

@Suite("TargetResolver Tests")
struct TargetResolverTests {

    @Test("listWindows returns at least one window")
    func listWindowsReturnsResults() throws {
        let resolver = TargetResolver()
        let windows = resolver.listWindows()
        #expect(!windows.isEmpty, "Should find at least one window on a running macOS system")
    }

    @Test("resolveApp finds Finder")
    func resolveAppFinder() throws {
        let resolver = TargetResolver()
        // Finder is always running on macOS
        let element = try resolver.resolveApp("Finder")
        #expect(element != nil)
    }

    @Test("resolveApp suggests similar names on miss")
    func resolveAppSuggestions() throws {
        let resolver = TargetResolver()
        do {
            _ = try resolver.resolveApp("Finderr")
            Issue.record("Should have thrown appNotFound")
        } catch let error as ScreenReadError {
            if case .appNotFound(_, let suggestions) = error {
                #expect(suggestions.contains("Finder"))
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    @Test("resolveFrontmost returns an element")
    func resolveFrontmost() throws {
        let resolver = TargetResolver()
        let element = try resolver.resolveFrontmost()
        #expect(element != nil)
    }

    @Test("resolvePID fails for invalid PID")
    func resolvePIDInvalid() throws {
        let resolver = TargetResolver()
        do {
            _ = try resolver.resolvePID(99999)
            Issue.record("Should have thrown pidNotFound")
        } catch let error as ScreenReadError {
            if case .pidNotFound = error {
                // expected
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }
}
