import DictationMac
import XCTest

/// R219: Chromium/Electron contenteditable ignores AXSelectedText while reporting success, so
/// insertion pastes there, and elsewhere verifies the AX write and pastes when nothing changed.
final class InsertionStrategyTests: XCTestCase {
    func test_R219_chromiumElementsPasteDirectly() {
        XCTAssertEqual(InsertionStrategy.method(isChromiumElement: true), .paste)
        XCTAssertEqual(InsertionStrategy.method(isChromiumElement: false), .accessibility)
    }

    func test_R219_unchangedValueMeansTheAXWriteDidNothing() {
        XCTAssertFalse(InsertionStrategy.didInsert(before: "hi", after: "hi", text: "there"))
        XCTAssertFalse(InsertionStrategy.didInsert(before: nil, after: nil, text: "there"))
    }

    func test_R219_valueContainingTheTextMeansInserted() {
        XCTAssertTrue(InsertionStrategy.didInsert(before: "hi ", after: "hi there", text: "there"))
        XCTAssertTrue(InsertionStrategy.didInsert(before: "", after: "Send the deck, thanks.", text: "Send the deck, thanks."))
    }

    func test_R219_valueChangedButWithoutTheTextIsNotTrusted() {
        XCTAssertFalse(InsertionStrategy.didInsert(before: "hi", after: "h", text: "there"))
    }

    func test_R219_pasteKeystrokeIsCommandVAndNeverReturn() {
        XCTAssertEqual(InsertionStrategy.pasteKeyCode, 9) // kVK_ANSI_V
        XCTAssertNotEqual(InsertionStrategy.pasteKeyCode, 36) // kVK_Return
        XCTAssertNotEqual(InsertionStrategy.pasteKeyCode, 76) // kVK_ANSI_KeypadEnter
    }
}
