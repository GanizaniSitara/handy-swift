import XCTest
@testable import HandySwift

/// Cases ported from Handy.NET tests/Handy.Tests/Program.cs so the two stay behaviourally aligned.
final class DomainCorrectionTests: XCTestCase {
    private func rule(_ from: String, _ to: String, enabled: Bool = true, variants: [String] = [],
                      required: [String] = [], blocked: [String] = [], caseSensitive: Bool = false) -> DomainCorrection {
        var r = DomainCorrection()
        r.enabled = enabled; r.from = from; r.to = to; r.variants = variants
        r.requiredContext = required; r.blockedContext = blocked; r.caseSensitive = caseSensitive
        return r
    }

    private func check(_ input: String, _ rules: [DomainCorrection], _ expected: String, _ count: Int,
                       file: StaticString = #filePath, line: UInt = #line) {
        let (text, applied) = DomainCorrector.apply(input, rules)
        XCTAssertEqual(text, expected, file: file, line: line)
        XCTAssertEqual(applied.reduce(0) { $0 + $1.count }, count, file: file, line: line)
    }

    func testMultiWordProducts() {
        check("Please open azure dev ops and service now.",
              [rule("azure dev ops", "Azure DevOps"), rule("service now", "ServiceNow")],
              "Please open Azure DevOps and ServiceNow.", 2)
    }
    func testPhraseBoundaries() {
        check("The microservice now runs service now checks.", [rule("service now", "ServiceNow")],
              "The microservice now runs ServiceNow checks.", 1)
    }
    func testCanonicalCasing() {
        check("Schedule the contoso atlas review.", [rule("contoso atlas", "Contoso Atlas")],
              "Schedule the Contoso Atlas review.", 1)
    }
    func testPunctuationOutsideMatch() {
        check("Route this through service now, then update azure dev ops.",
              [rule("service now", "ServiceNow"), rule("azure dev ops", "Azure DevOps")],
              "Route this through ServiceNow, then update Azure DevOps.", 2)
    }
    func testFlexibleWhitespace() {
        check("The quarterly business     review is ready.", [rule("quarterly business review", "QBR")],
              "The QBR is ready.", 1)
    }
    func testDisabledRule() {
        check("Leave service now alone.", [rule("service now", "ServiceNow", enabled: false)],
              "Leave service now alone.", 0)
    }
    func testHyphenBounded() {
        check("The service-now migration mentions service now.", [rule("service now", "ServiceNow")],
              "The service-now migration mentions ServiceNow.", 1)
    }
    func testPossessiveBounded() {
        check("The contoso's plan references contoso.", [rule("contoso", "Contoso")],
              "The contoso's plan references Contoso.", 1)
    }
    func testRequiredContext() {
        check("Please create a service now ticket.", [rule("service now", "ServiceNow", required: ["ticket"])],
              "Please create a ServiceNow ticket.", 1)
    }
    func testMissingRequiredContext() {
        check("We can service now and review later.", [rule("service now", "ServiceNow", required: ["ticket"])],
              "We can service now and review later.", 0)
    }
    func testBlockedContext() {
        check("We can service now please.", [rule("service now", "ServiceNow", blocked: ["please"])],
              "We can service now please.", 0)
    }
    func testVariants() {
        check("Open a snow incident ticket.",
              [rule("service now", "ServiceNow", variants: ["service now", "snow"], required: ["ticket"])],
              "Open a ServiceNow incident ticket.", 1)
    }
    func testCaseSensitive() {
        check("abc ABC abc.", [rule("abc", "ABC", caseSensitive: true)], "ABC ABC ABC.", 2)
    }

    func testDecodesHandyNetSettingsShape() throws {
        let json = """
        {"charDelayMs": 5, "hotkey": "Ctrl+Space", "domainCorrections": [
          {"enabled": false, "from": "service now", "to": "ServiceNow", "variants": ["service now", "snow"],
           "requiredContext": ["ticket"], "blockedContext": ["weather"], "caseSensitive": true, "notes": "ITSM"}]}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.charDelayMs, 5)
        XCTAssertEqual(s.appLanguage, "en")
        let r = try XCTUnwrap(s.domainCorrections.first)
        XCTAssertFalse(r.enabled)
        XCTAssertEqual(r.effectiveVariants, ["service now", "snow"])
        XCTAssertEqual(r.blockedContext, ["weather"])
        XCTAssertTrue(r.caseSensitive)
    }
}

final class TranscriptFilterTests: XCTestCase {
    func testRemovesEnglishFillers() {
        XCTAssertEqual(TranscriptFilter.filter("Um, I think, uh, we should hmm go.", lang: "en", customFillerWords: nil),
                       "I think, we should go.")
    }
    func testCollapsesStuttersOfThreeOrMore() {
        XCTAssertEqual(TranscriptFilter.filter("wh wh wh what now now", lang: "en", customFillerWords: nil),
                       "wh what now now")
    }
    func testPortugueseKeepsUm() {
        XCTAssertEqual(TranscriptFilter.filter("um carro", lang: "pt-BR", customFillerWords: nil), "um carro")
    }
    func testEmptyCustomListDisablesFillerRemoval() {
        XCTAssertEqual(TranscriptFilter.filter("uh okay", lang: "en", customFillerWords: []), "uh okay")
    }
}

final class FocusPolicyTests: XCTestCase {
    func testParseMatchesHandyNet() {
        XCTAssertEqual(Injector.FocusPolicy.parse(nil), .restoreAndPaste)
        XCTAssertEqual(Injector.FocusPolicy.parse(""), .restoreAndPaste)
        XCTAssertEqual(Injector.FocusPolicy.parse("RefuseAndCopy"), .refuseAndCopy)
        XCTAssertEqual(Injector.FocusPolicy.parse("refuse"), .refuseAndCopy)
        XCTAssertEqual(Injector.FocusPolicy.parse("restore"), .restoreAndPaste)
        XCTAssertEqual(Injector.FocusPolicy.parse("PasteAnyway"), .pasteAnyway)
        XCTAssertEqual(Injector.FocusPolicy.parse("unknown"), .restoreAndPaste)
        XCTAssertEqual(Settings().pasteFocusPolicy, "RestoreAndPaste")
    }
}
