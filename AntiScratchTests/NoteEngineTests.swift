import XCTest
@testable import AntiScratchCore

final class NoteEngineTests: XCTestCase {
    func testInlineMathSupportsVariablesAndPercentages() {
        let input = """
        math:
        preço: 120
        preço + 15% =
        """

        XCTAssertEqual(
            NoteEngine.renderInlineResults(in: input),
            "math:\npreço: 120\npreço + 15% = 138"
        )
    }

    func testAggregateModesIgnoreComments() {
        XCTAssertEqual(
            NoteEngine.analyze("sum:\n10\n// 100\n20").results,
            [NoteResult(label: "Soma · 2 valores", value: "30")]
        )
    }

    func testTimerParsesUnits() {
        XCTAssertEqual(NoteEngine.analyze("timer: 5m").timerDuration, 300)
        XCTAssertEqual(NoteEngine.analyze("timer: 30s").timerDuration, 30)
    }
}
