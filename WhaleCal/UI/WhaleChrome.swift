import SwiftUI

/// Quiet, shared navigation chrome. Native controls remain for editing inputs
/// and confirmations, not as containers around every piece of calendar content.
struct WhalePageHeader: View {
    @Environment(\.whaleTheme) private var theme
    let title: String
    var closeLabel = "Done"
    let onClose: () -> Void
    var closeEnabled = true
    var actionTitle: String?
    var actionSymbol: String?
    var actionEnabled = true
    var onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: closeLabel == "Back" ? "chevron.left" : "chevron.down")
                    .font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel(closeLabel).foregroundStyle(theme.muted).disabled(!closeEnabled)
            Text(title).font(.system(size: 16, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
            if let onAction {
                Button(action: onAction) {
                    Group {
                        if let actionSymbol { Image(systemName: actionSymbol).font(.system(size: 18, weight: .regular)) }
                        else { Text(actionTitle ?? "Edit").font(.system(size: 14, weight: .medium)) }
                    }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.disabled(!actionEnabled).accessibilityLabel(actionTitle ?? "New event")
            }
        }.buttonStyle(.plain).foregroundStyle(theme.text)
            .padding(.leading, 4).padding(.trailing, 16).padding(.vertical, 4)
            .background(theme.background)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("\(title) header")
    }
}

struct WhaleViewTabs: View {
    @Environment(\.whaleTheme) private var theme
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["Month", "Week", "Agenda", "Deadlines"], id: \.self) { option in
                Button { selection = option } label: {
                    Text(option).font(.system(size: 14, weight: selection == option ? .semibold : .regular))
                        .foregroundStyle(selection == option ? theme.text : theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if selection == option { Rectangle().fill(theme.accent).frame(height: 2).padding(.horizontal, 12) }
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("View \(option)")
                    .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }.overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }
}

struct WhaleSectionLabel: View {
    @Environment(\.whaleTheme) private var theme
    let text: String
    var body: some View { Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.muted) }
}
