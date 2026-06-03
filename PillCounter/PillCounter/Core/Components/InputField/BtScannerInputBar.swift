//
//  BtScannerInputBar.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/06/26.
//
//
//  BtScannerInputBar.swift
//  PillCounter
//

import SwiftUI
import UIKit

struct BtScannerInputBar: UIViewRepresentable {

    @Binding var focusTrigger: Int
    /// Called with the trimmed barcode string when the scanner sends Return.
    /// Value is read directly from the UITextField — no SwiftUI binding timing involved.
    let onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.inputView = UIView()
        let zeroAccessory = UIView(frame: .zero)
        zeroAccessory.autoresizingMask = []
        tf.inputAccessoryView = zeroAccessory
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.keyboardType = .asciiCapable
        tf.textContentType = .none
        tf.returnKeyType = .done
        tf.delegate = context.coordinator
        context.coordinator.uiTextField = tf

        // iPad: suppress the shortcut bar that shows the mic/dictation button
        tf.inputAssistantItem.leadingBarButtonGroups = []
        tf.inputAssistantItem.trailingBarButtonGroups = []

        tf.alpha = 0
        tf.backgroundColor = .clear
        tf.tintColor = .clear       // hides the blinking caret
        tf.textColor = .clear       // hides any typed characters
        tf.borderStyle = .none
        tf.isOpaque = false

        DispatchQueue.main.async { tf.becomeFirstResponder() }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        let prev = context.coordinator.lastFocusTrigger
        if focusTrigger != prev {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextFieldDelegate {
        let onSubmit: (String) -> Void
        weak var uiTextField: UITextField?
        var lastFocusTrigger: Int = 0

        init(onSubmit: @escaping (String) -> Void) {
            self.onSubmit = onSubmit
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            // Read value directly from the UITextField — guaranteed to be the
            // final accumulated string without any SwiftUI binding delay.
            let barcode = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            textField.text = ""
            onSubmit(barcode)
            return false
        }
    }
}
