import AppKit
import SwiftUI

/// Always-visible address bar text field.
/// Intercepts Tab, Arrows, Esc, Enter for autocomplete and navigation.
struct AddressTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var wantsFocus: Bool
    @Binding var isFocused: Bool
    var onCommit: () -> Void
    var onCancel: () -> Void
    var onTab: () -> Void
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onTextChange: (String) -> Void

    func makeNSView(context: Context) -> KeyInterceptingTextField {
        let field = KeyInterceptingTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingHead
        field.stringValue = text
        field.placeholderString = "Enter path…"
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.onFocusChange = { focused in
            self.isFocused = focused
        }
        // Enable focus after initial window setup to prevent auto-focus on launch
        DispatchQueue.main.async {
            field.allowFocus = true
        }
        return field
    }

    func updateNSView(_ nsView: KeyInterceptingTextField, context: Context) {
        nsView.onFocusChange = { focused in
            self.isFocused = focused
        }

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if wantsFocus {
            nsView.allowFocus = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.selectText(nil)
                self.wantsFocus = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressTextField

        init(_ parent: AddressTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onTextChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onArrowUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onArrowDown()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab()
                return true
            default:
                return false
            }
        }
    }
}

/// NSTextField subclass that tracks focus state.
final class KeyInterceptingTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    /// When true, allows focus. Set to false initially to prevent window auto-focus.
    var allowFocus = false

    override var acceptsFirstResponder: Bool { allowFocus }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocusChange?(true)
        }
        return result
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}
