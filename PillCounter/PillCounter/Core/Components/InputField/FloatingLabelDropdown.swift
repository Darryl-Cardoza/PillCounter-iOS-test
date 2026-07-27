import SwiftUI
import Combine

/// Carries a request to render a dropdown's floating panel outside any
/// clipping ScrollView. Read at a root-level `.overlayPreferenceValue` (see
/// `DropdownOverlayHost`) so the panel is never clipped or overlapped by
/// sibling fields inside the same scroll content.
struct DropdownOverlayKey: PreferenceKey {
    struct Request: Identifiable {
        let id: AnyHashable
        let anchor: Anchor<CGRect>
        /// Builds the panel given the field's resolved frame and the available
        /// height below it (both already in the host's own coordinate space,
        /// with the keyboard's height already subtracted) so it can size/flip
        /// itself relative to the field without touching `UIScreen` at all.
        let panel: (_ fieldFrame: CGRect, _ availableBelow: CGFloat) -> AnyView
        let onDismiss: () -> Void
    }

    static var defaultValue: [Request] = []
    static func reduce(value: inout [Request], nextValue: () -> [Request]) {
        value.append(contentsOf: nextValue())
    }
}

/// Drop this once at the root of a screen (outside any ScrollView) so every
/// `FloatingLabelDropdown` inside it can float its panel above sibling
/// content instead of being clipped/pushed by the surrounding scroll view.
struct DropdownOverlayHost: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(DropdownOverlayKey.self) { requests in
                GeometryReader { proxy in
                    // The keyboard sits above everything in its own window, so the
                    // panel must fit within the space that's actually still visible
                    // above it — measured in this same host coordinate space, not
                    // UIScreen's, which would drift from `proxy` once the keyboard
                    // resizes/scrolls surrounding content.
                    let visibleBottom = proxy.size.height - max(0, keyboardHeight - proxy.safeAreaInsets.bottom)

                    ZStack(alignment: .topLeading) {
                        ForEach(requests) { request in
                            let frame = proxy[request.anchor]
                            Color.black.opacity(0.001)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .contentShape(Rectangle())
                                .onTapGesture { request.onDismiss() }
                            request.panel(frame, visibleBottom - frame.maxY)
                        }
                    }
                }
                .allowsHitTesting(!requests.isEmpty)
            }
            .onReceive(Publishers.keyboardHeight) { height in
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = height }
            }
    }
}

extension View {
    func dropdownOverlayHost() -> some View { modifier(DropdownOverlayHost()) }
}

private struct DropdownScrollProxyKey: EnvironmentKey {
    static let defaultValue: ScrollViewProxy? = nil
}

extension EnvironmentValues {
    /// The enclosing ScrollView's proxy, if any — lets a `FloatingLabelDropdown`
    /// scroll itself into view above the keyboard when it opens.
    var dropdownScrollProxy: ScrollViewProxy? {
        get { self[DropdownScrollProxyKey.self] }
        set { self[DropdownScrollProxyKey.self] = newValue }
    }
}

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
    @Environment(\.dropdownScrollProxy) private var scrollProxy

    // MARK: - Private state
    @State private var isExpanded = false
    /// Backs the field's text. Always shows the selected label when nothing
    /// is being typed; becomes the live search query as soon as the user edits it.
    @State private var text = ""
    @State private var panelSize: CGSize = .zero
    @FocusState private var searchFocused: Bool
    private let instanceId = UUID()

    private let fieldHeight: CGFloat = 64
    private let listMaxHeight: CGFloat = 260

    private var hasSelection: Bool { selection != nil }
    private var isActive: Bool { searchFocused || hasSelection || isExpanded }

    private var filteredOptions: [Option] {
        guard searchable, !text.isEmpty else { return options }
        return options.filter {
            labelText($0).localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        fieldButton
            .anchorPreference(key: DropdownOverlayKey.self, value: .bounds) { anchor in
                guard isExpanded else { return [] }
                return [DropdownOverlayKey.Request(
                    id: instanceId,
                    anchor: anchor,
                    panel: { frame, availableBelow in
                        AnyView(floatingPanel(fieldFrame: frame, availableBelow: availableBelow))
                    },
                    onDismiss: close
                )]
            }
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
    }

    /// The panel positioned relative to the field's own frame. Both `frame`
    /// and `availableBelow` are supplied by `DropdownOverlayHost` in its own
    /// coordinate space, with the keyboard's height already subtracted from
    /// `availableBelow` — so the panel always fits above the keyboard instead
    /// of being covered by it.
    private func floatingPanel(fieldFrame frame: CGRect, availableBelow: CGFloat) -> some View {
        // Default to opening below (standard combo-box behavior). Only flip
        // upward once we've actually measured the panel's real height and
        // confirmed there's genuinely no room below but there is above —
        // using a stale/zero size here would place the panel right on top
        // of the field instead of cleanly above or below it.
        let opensUp = panelSize.height > 0
            && availableBelow < panelSize.height + 6
            && frame.minY - panelSize.height - 6 > 0

        return menuPanel
            .frame(width: frame.width)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: SizeKey.self, value: g.size)
                }
            )
            .offset(x: frame.minX,
                    y: opensUp ? frame.minY - (panelSize.height + 6)
                               : frame.minY + fieldHeight + 6)
            .onPreferenceChange(SizeKey.self) { panelSize = $0 }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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
                        TextField("", text: $text)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text(text)
                    }
                }
                .padding(.leading, 8)
                .font(.body)
                .foregroundColor(disabled ? appColors.text.opacity(0.75) : appColors.text)
                .padding(.top, isActive ? 10 : 0)
                .opacity(isActive ? 1 : 0)
                .animation(.easeIn(duration: 0.15).delay(0.1), value: isActive)

                Spacer(minLength: 0)

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
        .id(instanceId)
        .onTapGesture {
            guard !disabled, !isExpanded else { return }
            open()
        }
        .onAppear { text = selection.map(labelText) ?? "" }
        .onChange(of: selection) { _, newValue in
            guard !isExpanded else { return }
            text = newValue.map(labelText) ?? ""
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
            text = labelText(option)
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
        if searchable { searchFocused = true }
        // Give the keyboard-show animation a moment to start before scrolling,
        // so the field lands just above the keyboard's final resting position
        // instead of wherever it was before the keyboard appeared.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy?.scrollTo(instanceId, anchor: .top)
            }
        }
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.18)) { isExpanded = false }
        searchFocused = false
        text = selection.map(labelText) ?? ""
    }
}

private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
