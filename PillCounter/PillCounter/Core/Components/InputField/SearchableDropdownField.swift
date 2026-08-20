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

    let placeholder: String
    
    let options: [Option]
    @Binding var selection: Option?
    var disabled: Bool = false

    @State private var searchText: String = ""
    @FocusState private var isFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var fieldFrame: CGRect = .zero

    private let listMaxHeight: CGFloat = 250
    private let fieldHeight: CGFloat = 64
    private let gap: CGFloat = 8
    /// Row content (2 x 12pt vertical padding + ~20pt text line) plus its 1pt divider.
    private let rowHeight: CGFloat = 45

    private var isExpanded: Bool { isFocused }
    private var isActive: Bool { isFocused || selection != nil }

    private var displayText: String {
        selection.map { "\($0.code) - \($0.name)" } ?? ""
    }

    private var filteredOptions: [Option] {
        guard !searchText.isEmpty else { return options }
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
        let fieldTop = fieldFrame.minY - gap
        guard keyboardHeight > 0 else { return fieldTop }
        let keyboardTop = UIScreen.main.bounds.height - keyboardHeight - gap
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

    var body: some View {
        field
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { fieldFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, newValue in
                            fieldFrame = newValue
                        }
                }
            )
            // `.overlay` (not a ZStack sibling) so the list never affects this
            // field's own layout footprint in the surrounding form — it floats
            // entirely above the field's bounds, never inside/overlapping them.
            .overlay(alignment: .top) {
                if isExpanded {
                    optionList
                        .frame(width: fieldFrame.width > 0 ? fieldFrame.width : nil)
                        .frame(height: availableListHeight)
                        .offset(y: listOffsetY)
                }
            }
            .onReceive(Publishers.keyboardHeight) { height in
                keyboardHeight = height
            }
            // High, not just 1 — this sits among sibling fields in the same
            // VStack, and the floating list must paint above ALL of them
            // (fields declared later in the form included), not merely above
            // its own immediate neighbor.
            .zIndex(isExpanded ? 1000 : 0)
    }

    private var field: some View {
        ZStack(alignment: .leading) {
            Text(placeholder)
                .font(isActive ? .caption : .body)
                .foregroundColor(isFocused ? appColors.primary : appColors.text.opacity(0.75))
                .offset(y: isActive ? -16 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
                .padding(.leading, 8)

            TextField("", text: isExpanded ? $searchText : .constant(displayText))
                .padding(.leading, 8)
                .focused($isFocused)
                .font(.body)
                .foregroundColor(disabled ? appColors.text.opacity(0.75) : appColors.text)
                .padding(.top, isActive ? 10 : 0)
                .opacity(isActive ? 1 : 0)
                .disabled(disabled)

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
            guard !disabled else { return }
            searchText = ""
            isFocused = true
        }
    }

    private var optionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredOptions) { option in
                    Button {
                        selection = option
                        isFocused = false
                        UIApplication.hideKeyboard()
                    } label: {
                        HStack {
                            Text("\(option.code) - \(option.name)")
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
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
