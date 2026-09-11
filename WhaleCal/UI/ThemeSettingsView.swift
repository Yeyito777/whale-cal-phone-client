import SwiftUI

struct ThemeSettingsView: View {
    @AppStorage(CalendarThemeName.storageKey) private var selection = CalendarThemeName.dark.rawValue
    @Environment(\.dismiss) private var dismiss
    private var selected: CalendarThemeName { CalendarThemeName(savedValue: selection) }
    private var theme: WhalePalette { selected.palette }

    var body: some View {
        VStack(spacing: 0) {
            WhalePageHeader(title: "Theme", onClose: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(CalendarThemeName.allCases) { option in
                        Button {
                            // No cross-fade or identity reset: preserve navigation,
                            // scroll position, unsaved edits, and the SSH session.
                            selection = option.rawValue
                        } label: {
                            HStack(spacing: 16) {
                                HStack(spacing: 3) {
                                    ForEach(Array(option.palette.preview.enumerated()), id: \.offset) { _, color in
                                        Rectangle().fill(color).frame(width: 10, height: 30)
                                    }
                                }.padding(7).background(option.palette.background)
                                    .overlay { Rectangle().strokeBorder(theme.line, lineWidth: 1) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(option.title).font(.system(size: 16, weight: .medium)).foregroundStyle(theme.text)
                                    Text(option.summary).font(.system(size: 12)).foregroundStyle(theme.muted)
                                }
                                Spacer(minLength: 0)
                                if selected == option {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
                                }
                            }.frame(minHeight: 80).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("Theme \(option.rawValue)")
                            .accessibilityLabel(option.title)
                            .accessibilityValue(selected == option ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selected == option ? [.isSelected] : [])
                            .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
                    }
                    Text("Appearance is saved on this phone. Calendar colors stay unchanged.")
                        .font(.system(size: 12)).foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
                }.padding(.horizontal, 20)
            }
        }.background(theme.background).foregroundStyle(theme.text).tint(theme.accent)
            .environment(\.whaleTheme, theme).preferredColorScheme(.dark)
    }
}
