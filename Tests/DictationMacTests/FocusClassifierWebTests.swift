import DictationCore
import DictationMac
import XCTest

/// R218: Electron/Chrome inputs (contenteditable, generic groups exposing editable text) count as text fields.
final class FocusClassifierWebTests: XCTestCase {
    func test_R218_unknownRoleWithSettableSelectedTextIsAnEditableArea() {
        for role in ["AXGroup", "AXGenericElement", "AXStaticText", nil] as [String?] {
            XCTAssertEqual(FocusClassifier.role(axRole: role, subrole: nil, bundleID: "com.anysphere.sand",
                                                selectedTextSettable: true), .textArea, "\(role ?? "nil")")
        }
    }

    func test_R218_unknownRoleWithoutSettableTextIsNotAField() {
        XCTAssertEqual(FocusClassifier.role(axRole: "AXGroup", subrole: nil, bundleID: "com.google.Chrome",
                                            selectedTextSettable: false), FieldRole.none)
        XCTAssertEqual(FocusClassifier.role(axRole: "AXButton", subrole: nil, bundleID: nil,
                                            selectedTextSettable: false), FieldRole.none)
    }

    func test_R218_webAreaAndSearchFieldsStillClassified() {
        XCTAssertEqual(FocusClassifier.role(axRole: "AXWebArea", subrole: nil, bundleID: "com.google.Chrome",
                                            selectedTextSettable: true), .editableWebArea)
        XCTAssertEqual(FocusClassifier.role(axRole: "AXSearchField", subrole: nil, bundleID: nil,
                                            selectedTextSettable: true), .textField)
        XCTAssertEqual(FocusClassifier.role(axRole: "AXTextField", subrole: "AXSecureTextField", bundleID: nil,
                                            selectedTextSettable: true), .secureTextField)
    }

    func test_R218_editableInTerminalIsTerminal() {
        XCTAssertEqual(FocusClassifier.role(axRole: "AXGroup", subrole: nil, bundleID: "com.apple.Terminal",
                                            selectedTextSettable: true), .terminal)
    }
}
