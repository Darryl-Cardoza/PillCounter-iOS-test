import SwiftUI
import Combine

protocol CodeNameOption: Identifiable, Hashable {
    var code: String { get }
    var name: String { get }
}

/// Text-field-styled dropdown matching `FloatingLabelTextField`'s look. Tapping
/// it turns the field itself into a live search box and shows a scrollable
/// option list floating just above the field, entirely outside its bounds —
/// never rendered inside/overlapping the field itself. The field never moves;
/// the list's own height is capped to whatever space is actually available
/// between the field and the keyboard, so it's always fully visible and
/// scrollable rather than pushing the field around or getting clipped.
struct SearchableDropdownField<Option: CodeNameOption>: View {

    @EnvironmentObject var appColors: AppColors
    @EnvironmentObject private var overlayCoordinator: DropdownOverlayCoordinator

    /// Identifies this field's list in the shared overlay layer — must be
    /// unique among fields sharing one `.dropdownOverlayHost()`. `@State` so
    /// identity is stable across re-renders (a `let UUID()` would churn on
    /// every body evaluation since this is a value-type view struct).
    @State private var fieldID = UUID()

    let placeholder: String

    let options: [Option]
    @Binding var selection: Option?
    var disabled: Bool = false
    /// Set false for dropdowns that just pick from a short fixed list (terminal,
    /// pharmacy type) — tapping still opens the option list, but the field never
    /// turns into a live-filter text box.
    var showSearch: Bool = true
    /// Row/field label override; defaults to "code - name". Terminal and pharmacy
    /// type have no code worth surfacing, so they pass a name/label-only closure.
    var displayText: ((Option) -> String)? = nil
    /// Called instead of opening the list when tapped while `disabled` — e.g.
    /// surfacing a "feature not available" toast rather than doing nothing.
    var onDisabledTap: (() -> Void)? = nil

    @State private var searchText: String = ""
    @FocusState private var isFocused: Bool
    /// Drives expansion for `showSearch == false` fields, which never focus a
    /// text field (it stays disabled), so `isFocused` alone can't open the list.
    @State private var isListOpen: Bool = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var fieldFrame: CGRect = .zero

    private let listMaxHeight: CGFloat = 250
    private let fieldHeight: CGFloat = 64
    /// Gap between field and list when the list floats above (search fields).
    private let gapAbove: CGFloat = 8
    /// Gap between field and list when the list drops below (no-search fields).
    private let gapBelow: CGFloat = 6
    /// Row content (2 x 12pt vertical padding + ~20pt text line) plus its 1pt divider.
    private let rowHeight: CGFloat = 45

    private var isExpanded: Bool { showSearch ? isFocused : isListOpen }
    private var isActive: Bool { isExpanded || selection != nil }

    private func label(for option: Option) -> String {
        displayText?(option) ?? "\(option.code) - \(option.name)"
    }

    private var fieldText: String {
        selection.map(label(for:)) ?? ""
    }

    private var filteredOptions: [Option] {
        guard showSearch, !searchText.isEmpty else { return options }
        let query = searchText.lowercased()
        return options.filter {
            $0.code.lowercased().contains(query) || $0.name.lowercased().contains(query)
        }
    }

    /// Absolute Y (in screen/global coordinates) the list's bottom edge must
    /// sit at — above the field, AND above the keyboard, whichever is more
    /// restrictive. The field can be partially/fully behind the keyboard
    /// (it never moves), so this can't just be "field's top minus gap" —
    /// it must also never exceed the keyboard's own top edge.
    private var listBottomY: CGFloat {
        guard fieldFrame != .zero else { return 0 }
        let fieldTop = fieldFrame.minY - gapAbove
        guard keyboardHeight > 0 else { return fieldTop }
        let keyboardTop = UIScreen.main.bounds.height - keyboardHeight - gapAbove
        return min(fieldTop, keyboardTop)
    }

    /// Natural height of the list's own content — a handful of rows (e.g. 2
    /// countries) shouldn't reserve the full max height, only what they need.
    private var contentHeight: CGFloat {
        CGFloat(filteredOptions.count) * rowHeight
    }

    /// The list shrinks to fit its actual row count, but never exceeds
    /// `listMaxHeight`, and never exceeds whatever vertical space is actually
    /// free above `listBottomY` either (so it's never clipped by the
    /// field/keyboard on a short screen).
    private var availableListHeight: CGFloat {
        let cappedByContent = min(contentHeight, listMaxHeight)
        guard fieldFrame != .zero else { return cappedByContent }
        return min(cappedByContent, listBottomY)
    }

    /// Vertical offset to apply to the list, which is laid out (before this
    /// offset) with its own top pinned to the field's top via `.overlay(alignment: .top)`.
    /// Moves it so its BOTTOM lands exactly at `listBottomY`, regardless of
    /// where the field itself sits relative to the keyboard.
    private var listOffsetY: CGFloat {
        guard fieldFrame != .zero else { return 0 }
        return (listBottomY - availableListHeight) - fieldFrame.minY
    }

    /// Absolute Y the downward list's top edge sits at — just below the field.
    /// Used only when `showSearch == false`: those fields never bring up a
    /// keyboard, so there's no keyboard edge to avoid, just the field itself.
    private var listTopYBelow: CGFloat {
        guard fieldFrame != .zero else { return 0 }
        return fieldFrame.maxY + gapBelow
    }

    /// Downward list is capped by content/max height and by whatever space is
    /// free between the field's bottom and the screen's bottom edge.
    private var availableListHeightBelow: CGFloat {
        let cappedByContent = min(contentHeight, listMaxHeight)
        guard fieldFrame != .zero else { return cappedByContent }
        let spaceBelow = UIScreen.main.bounds.height - listTopYBelow - gapBelow
        return min(cappedByContent, max(0, spaceBelow))
    }

    var body: some View {
        field
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { fieldFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, newValue in
                            fieldFrame = newValue
                            if isExpanded { publishOverlay() }
                        }
                }
            )
            .onReceive(Publishers.keyboardHeight) { height in
                keyboardHeight = height
                if isExpanded { publishOverlay() }
            }
            .onChange(of: isExpanded) { _, expanded in
                if expanded {
                    publishOverlay()
                } else {
                    overlayCoordinator.hide(fieldID: fieldID)
                }
            }
            .onChange(of: searchText) { _, _ in
                if isExpanded { publishOverlay() }
            }
            .onChange(of: selection) { _, _ in
                if isExpanded { publishOverlay() }
            }
            .onDisappear {
                overlayCoordinator.hide(fieldID: fieldID)
            }
    }

    /// Renders the list into the shared root-level overlay layer (see
    /// `DropdownOverlayCoordinator`) instead of a local `.overlay`, so it
    /// always paints above every row regardless of declaration order — a list
    /// nested inside this field's own view could never outrank a sibling
    /// field's opaque background declared later in the same stack. Position
    /// is expressed in global coordinates (`fieldFrame` is already `.global`)
    /// via `.position`, since the host's overlay sits outside this field's
    /// local layout entirely.
    private func publishOverlay() {
        let width = fieldFrame.width > 0 ? fieldFrame.width : nil
        let height = showSearch ? availableListHeight : availableListHeightBelow
        let topY = showSearch ? (listBottomY - height) : listTopYBelow
        let centerX = fieldFrame.midX
        let centerY = topY + height / 2
        overlayCoordinator.show(fieldID: fieldID, dismiss: closeList) {
            optionList
                .frame(width: width)
                .frame(height: height)
                .position(x: centerX, y: centerY)
        }
    }

    /// Closes the list the same way selecting a row does, minus the selection —
    /// shared by row-tap-to-select and outside-tap-to-dismiss.
    private func closeList() {
        isFocused = false
        isListOpen = false
        UIApplication.hideKeyboard()
    }

    private var field: some View {
        ZStack(alignment: .leading) {
            Text(placeholder)
                .font(isActive ? .caption : .body)
                .foregroundColor(isFocused ? appColors.primary : appColors.text.opacity(0.75))
                .offset(y: isActive ? -16 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
                .padding(.leading, 8)

            TextField("", text: (isExpanded && showSearch) ? $searchText : .constant(fieldText))
                .padding(.leading, 8)
                .focused($isFocused)
                .font(.body)
                .foregroundColor(disabled ? appColors.text.opacity(0.75) : appColors.text)
                .padding(.top, isActive ? 10 : 0)
                .opacity(isActive ? 1 : 0)
                .disabled(disabled || !showSearch)

            HStack {
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(appColors.text.opacity(0.75))
                    .padding(.trailing, 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 20)
        .frame(height: fieldHeight)
        .background(appColors.secondaryBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !disabled else {
                onDisabledTap?()
                return
            }
            if showSearch {
                searchText = ""
                isFocused = true
            } else {
                isListOpen.toggle()
            }
        }
    }

    private var optionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredOptions) { option in
                    Button {
                        selection = option
                        closeList()
                    } label: {
                        HStack {
                            Text(label(for: option))
                                .foregroundColor(option == selection ? appColors.primary : appColors.text)
                                .fontWeight(option == selection ? .semibold : .regular)
                            Spacer()
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .foregroundColor(appColors.primary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    if option.id != filteredOptions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .background(appColors.secondaryBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(appColors.text.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
