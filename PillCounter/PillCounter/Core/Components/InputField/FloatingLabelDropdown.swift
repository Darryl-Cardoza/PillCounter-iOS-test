import SwiftUI
import Combine

struct FloatingLabelDropdown<Option: Hashable>: View {

    // MARK: - Public API (matches your call site)
    let placeholder: String
    @Binding var selection: Option?
    let options: [Option]
    let labelText: (Option) -> String
    var disabled: Bool = false
    var searchable: Bool = false
    var searchPlaceholder: String = "Search"
    var onSelect: ((Option) -> Void)? = nil

    @EnvironmentObject private var appColors: AppColors

    // MARK: - Private state
    @State private var isExpanded = false
    @State private var searchText = ""
    @State private var panelSize: CGSize = .zero
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool

    private let fieldHeight: CGFloat = 64
    private let listMaxHeight: CGFloat = 260

    private var hasSelection: Bool { selection != nil }
    private var isActive: Bool { searchFocused || hasSelection || isExpanded }

    private var filteredOptions: [Option] {
        guard searchable, isExpanded, !searchText.isEmpty else { return options }
        return options.filter {
            labelText($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    /// What the field's text shows: the live search text while searching, else the selected label.
    private var displayText: String {
        if searchable && isExpanded { return searchText }
        return selection.map(labelText) ?? ""
    }

    var body: some View {
        fieldButton
            // The menu lives in an overlay -> it never affects the layout
            // of siblings, it just draws on top of them.
            .overlay(alignment: .topLeading) {
                if isExpanded {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .global)
                        let screen = UIScreen.main.bounds.size
                        let availableBelow = screen.height - keyboardHeight - frame.maxY
                        // Flip upward if there isn't room below (keyboard included).
                        let opensUp = availableBelow < panelSize.height + 6
                            && frame.minY - panelSize.height - 6 > 0

                        ZStack(alignment: .topLeading) {
                            // Full-area tap catcher to dismiss on outside tap.
                            Color.black.opacity(0.001)
                                .frame(width: screen.width, height: screen.height)
                                .offset(x: -frame.minX, y: -frame.minY)
                                .onTapGesture { close() }

                            menuPanel
                                .frame(width: frame.width)
                                .background(
                                    GeometryReader { g in
                                        Color.clear
                                            .preference(key: SizeKey.self, value: g.size)
                                    }
                                )
                                .offset(y: opensUp ? -(panelSize.height + 6)
                                                   : fieldHeight + 6)
                        }
                    }
                    .onPreferenceChange(SizeKey.self) { panelSize = $0 }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .onReceive(Publishers.keyboardHeight) { height in
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = height }
            }
            // Lift the whole control above neighboring views while open.
            .zIndex(isExpanded ? 9999 : 0)
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Field
    private var fieldButton: some View {
        ZStack(alignment: .leading) {
            // Floating placeholder label
            Text(placeholder)
                .font(isActive ? .caption : .body)
                .foregroundColor(searchFocused ? appColors.primary : appColors.text.opacity(0.75))
                .offset(y: isActive ? -16 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
                .padding(.leading, 8)
                .allowsHitTesting(false)

            HStack(spacing: 8) {
                Group {
                    if searchable {
                        TextField("", text: $searchText)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onTapGesture { if !isExpanded { open() } }
                    } else {
                        Text(displayText)
                    }
                }
                .padding(.leading, 8)
                .font(.body)
                .foregroundColor(disabled ? appColors.text.opacity(0.75) : appColors.text)
                .padding(.top, isActive ? 10 : 0)
                .opacity(isActive ? 1 : 0)
                .animation(.easeIn(duration: 0.15).delay(0.1), value: isActive)

                Spacer(minLength: 0)

                if searchable && isExpanded && !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(appColors.text.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(appColors.text.opacity(0.75))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: fieldHeight)
        .background(appColors.secondaryBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !disabled else { return }
            isExpanded ? close() : open()
        }
    }

    // MARK: - Floating menu
    private var menuPanel: some View {
        VStack(spacing: 0) {
            if filteredOptions.isEmpty {
                Text("No results")
                    .font(.subheadline)
                    .foregroundColor(appColors.text.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredOptions, id: \.self) { option in
                            optionRow(option)
                        }
                    }
                }
                .frame(maxHeight: listMaxHeight)
            }
        }
        .background(appColors.secondaryBackground)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private func optionRow(_ option: Option) -> some View {
        Button {
            selection = option
            onSelect?(option)
            close()
        } label: {
            HStack {
                Text(labelText(option))
                    .font(.body)
                    .foregroundColor(appColors.text)
                Spacer()
                if option == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(appColors.primary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(option == selection ? appColors.primary.opacity(0.08) : .clear)
    }

    // MARK: - Actions
    private func open() {
        guard !disabled else { return }
        withAnimation(.easeInOut(duration: 0.18)) { isExpanded = true }
        if searchable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.18)) { isExpanded = false }
        searchFocused = false
        searchText = ""
    }
}

private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
