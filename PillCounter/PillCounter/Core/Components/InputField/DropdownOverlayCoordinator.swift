import SwiftUI

/// Lets any number of `SearchableDropdownField`s share one paint layer for
/// their floating option lists. zIndex only ranks siblings within the same
/// parent, so a list nested inside its own field's `.overlay` can never
/// out-rank a *different* row's field declared later in the same stack —
/// only a real, single top-level overlay can guarantee "whichever field is
/// actually open paints above every other row" regardless of declaration
/// order. Install one instance via `.dropdownOverlayHost()` near the root of
/// a screen that has 2+ `SearchableDropdownField`s stacked vertically.
final class DropdownOverlayCoordinator: ObservableObject {
    @Published fileprivate var content: AnyView? = nil
    /// Identifies which field currently owns the shared layer, so opening one
    /// field closes any other that was already open.
    @Published private(set) var openFieldID: AnyHashable? = nil
    /// Closes the currently-open field the same way its own row would (clears
    /// focus/list-open state there too) — called when the user taps outside it.
    private var dismiss: (() -> Void)? = nil

    func show<Content: View>(fieldID: AnyHashable, dismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        openFieldID = fieldID
        self.dismiss = dismiss
        self.content = AnyView(content())
    }

    func hide(fieldID: AnyHashable) {
        guard openFieldID == fieldID else { return }
        openFieldID = nil
        dismiss = nil
        content = nil
    }

    fileprivate func dismissOpenField() {
        dismiss?()
    }
}

private struct DropdownOverlayHostModifier: ViewModifier {
    @StateObject private var coordinator = DropdownOverlayCoordinator()

    func body(content: Content) -> some View {
        content
            .environmentObject(coordinator)
            .overlay {
                // `SearchableDropdownField` positions its list using `.global`
                // frames (`fieldFrame`), so this overlay's own local origin
                // must line up with `.global` (0, 0) too — otherwise whatever
                // sits above this host in the view tree (status bar, a
                // BaseView header) shows up as a constant, unexplained gap
                // between the field and its list. `GeometryReader` reports
                // this overlay's own top-left in `.global`; offsetting by its
                // negative re-anchors local (0, 0) to match.
                GeometryReader { proxy in
                    let globalOrigin = proxy.frame(in: .global).origin
                    ZStack {
                        if coordinator.content != nil {
                            // Full-screen tap catcher behind the list dismisses
                            // on any tap outside it — the list's own rows sit
                            // above this in the same overlay and get first
                            // crack at the tap.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { coordinator.dismissOpenField() }
                        }
                        coordinator.content
                    }
                    .offset(x: -globalOrigin.x, y: -globalOrigin.y)
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func dropdownOverlayHost() -> some View {
        modifier(DropdownOverlayHostModifier())
    }
}
