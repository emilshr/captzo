import AppKit
import SwiftUI

struct AspectRatioMenu: View {
    @Binding var selection: AspectRatioOption
    var includeAllOption: Bool = false
    var allSelected: Bool = false
    var onSelectAll: (() -> Void)?
    var labelStyle: AspectRatioMenuLabelStyle = .compact
    var isDisabled: Bool = false

    var body: some View {
        Menu {
            if includeAllOption {
                Button {
                    onSelectAll?()
                } label: {
                    menuRow(title: "All", option: nil, isSelected: allSelected)
                }
                Divider()
            }

            ForEach(AspectRatioOption.allCases) { option in
                Button {
                    selection = option
                } label: {
                    menuRow(
                        title: option.displayName,
                        option: option,
                        isSelected: !allSelected && selection == option
                    )
                }
            }
        } label: {
            labelContent
        }
        .labelStyle(.titleAndIcon)
        .disabled(isDisabled)
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var labelContent: some View {
        switch labelStyle {
        case .compact:
            HStack(spacing: 8) {
                if allSelected {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Image(nsImage: AspectRatioGlyph.nsImage(
                        option: selection,
                        size: 14,
                        color: .white.withAlphaComponent(0.9)
                    ))
                    Text(selection.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 88)
            .frame(height: 36)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .settings:
            HStack(spacing: 8) {
                if allSelected {
                    Text("All")
                } else {
                    AspectRatioGlyph(option: selection, size: 16, color: selection.badgeColor)
                    Text(selection.displayName)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .toolbarFilter:
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                if allSelected {
                    Text("All Ratios")
                } else {
                    AspectRatioGlyph(option: selection, size: 12, color: selection.badgeColor)
                    Text(selection.displayName)
                }
            }
        }
    }

    @ViewBuilder
    private func menuRow(title: String, option: AspectRatioOption?, isSelected: Bool) -> some View {
        HStack {
            if let option {
                Image(nsImage: AspectRatioGlyph.nsImage(
                    option: option,
                    size: 16,
                    color: option.glyphNSColor
                ))
            } else {
                Image(systemName: "square.dashed")
                    .frame(width: 16, height: 16)
            }
            Text(title)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

enum AspectRatioMenuLabelStyle {
    case compact
    case settings
    case toolbarFilter
}

/// Binding-friendly wrapper when filter is optional (`nil` = All).
struct AspectRatioFilterMenu: View {
    @Binding var filter: AspectRatioOption?

    var body: some View {
        AspectRatioMenu(
            selection: Binding(
                get: { filter ?? .oneToOne },
                set: { filter = $0 }
            ),
            includeAllOption: true,
            allSelected: filter == nil,
            onSelectAll: { filter = nil },
            labelStyle: .toolbarFilter
        )
        .help("Filter by aspect ratio")
    }
}
