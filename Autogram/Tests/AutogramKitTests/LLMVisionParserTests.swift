import XCTest
@testable import AutogramKit

final class LLMVisionParserTests: XCTestCase {
    func testExtractJSONArrayFromNoisyResponse() throws {
        let noisy = """
        Tu je analýza strany:
        Našiel som 2 prvky:
        [{"kind":"officialStamp","page":1,"box":[0.7,0.8,0.2,0.15],"confidence":0.92,
          "description_sk":"Úradná pečiatka v pravej dolnej časti"}]
        Dúfam, že to pomáha!
        """
        let json = try XCTUnwrap(LLMVisionParser.extractJSONArray(from: noisy))
        let elements = LLMVisionParser.decode(elements: json)
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements.first?.kind, .officialStamp)
        XCTAssertEqual(elements.first?.pageIndex, 0)
        XCTAssertEqual(elements.first?.boundingBox.x ?? -1, 0.7, accuracy: 0.001)
    }

    func testDecodeAllKindsAndClamping() {
        let payload = """
        [
         {"kind":"handwrittenSignature","page":2,"box":[0.1,0.85,0.4,0.08],"confidence":0.7,"description_sk":"Podpis"},
         {"kind":"embossedSeal","page":1,"box":[-0.2,0.5,0.3,0.3],"confidence":0.55},
         {"kind":"initial","page":3,"box":[0.5,0.9,0.05,0.03]},
         {"kind":"neznámy typ","page":1,"box":[0,0,0.1,0.1],"confidence":0.9}
        ]
        """
        let elements = LLMVisionParser.decode(elements: Data(payload.utf8))
        XCTAssertEqual(elements.count, 4)

        XCTAssertEqual(elements[0].kind, .handwrittenSignature)
        XCTAssertEqual(elements[0].pageIndex, 1)

        XCTAssertEqual(elements[1].kind, .embossedSeal)
        XCTAssertEqual(elements[1].boundingBox.x, 0, accuracy: 0.001)

        XCTAssertEqual(elements[2].kind, .initial)
        XCTAssertEqual(elements[2].confidence, 0.7, accuracy: 0.001)

        XCTAssertEqual(elements[3].kind, .other)
    }

    func testEmptyResponseYieldsNothing() {
        XCTAssertNil(LLMVisionParser.extractJSONArray(from: "Žiadne prvky som nenašiel."))
        XCTAssertTrue(LLMVisionParser.decode(elements: Data("[]".utf8)).isEmpty)
    }

    func testEffectivePromptFallsBackToDefault() {
        XCTAssertEqual(LLMVisionParser.effectivePrompt(nil), LLMVisionParser.systemPrompt)
        XCTAssertEqual(LLMVisionParser.effectivePrompt("   "), LLMVisionParser.systemPrompt)

        let custom = LLMVisionParser.effectivePrompt("Moje vlastné inštrukcie pre klasifikáciu.")
        XCTAssertTrue(custom.hasPrefix("Moje vlastné inštrukcie"))
        XCTAssertTrue(custom.contains("officialStamp"))
        XCTAssertTrue(custom.contains("JSON"))
    }

    func testDefaultPromptCoversSlovakSecurityElements() {
        for keyword in ["úradn", "slepotlač", "parafa", "vlastnoručný podpis", "notársk"] {
            XCTAssertTrue(LLMVisionParser.systemPrompt.lowercased().contains(keyword.lowercased()),
                          "Default prompt musí pokrývať: \(keyword)")
        }
    }
}
