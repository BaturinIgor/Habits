import SwiftUI
import UIKit

/// Альтернативные иконки приложения (Pro). Файлы: Assets.xcassets/AppIcon-<имя>,
/// превью для выбора: IconPreview-<имя>.
enum AppIcons {
    struct Item: Identifiable {
        /// nil у стандартной иконки.
        let name: String?
        let title: LocalizedStringKey
        var id: String { name ?? "Original" }
        var preview: String { "IconPreview-" + id }
        var assetName: String? { name.map { "AppIcon-" + $0 } }
    }

    static let all: [Item] = [
        Item(name: nil, title: "Classic"),
        Item(name: "Sunset", title: "Sunset"),
        Item(name: "Forest", title: "Forest"),
        Item(name: "Rose", title: "Rose"),
        Item(name: "Gold", title: "Gold"),
        Item(name: "Midnight", title: "Midnight"),
        Item(name: "Light", title: "Light"),
    ]

    @MainActor
    static var current: Item {
        let asset = UIApplication.shared.alternateIconName
        return all.first { $0.assetName == asset } ?? all[0]
    }
}

struct AppIconView: View {
    @Environment(HabitStore.self) private var store
    @State private var selected: String = AppIcons.current.id
    @State private var showingPaywall = false
    @State private var errorText: String?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 16)]

    var body: some View {
        analyticsBody.analyticsScreen(.appIcon)
    }

    @ViewBuilder private var analyticsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !store.data.isPro {
                    HStack(spacing: 8) {
                        ProBadge()
                        Text("New icons are part of Pro.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(AppIcons.all) { item in
                        Button {
                            choose(item)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(item.preview)
                                        .resizable()
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                        }
                                        .padding(4)
                                        .overlay {
                                            if selected == item.id {
                                                RoundedRectangle(cornerRadius: 21, style: .continuous)
                                                    .strokeBorder(Color.accentColor, lineWidth: 3)
                                            }
                                        }
                                    if item.name != nil && !store.data.isPro {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(5)
                                            .background(Circle().fill(.black.opacity(0.55)))
                                            .offset(x: -2, y: -2)
                                    }
                                }
                                Text(item.title)
                                    .font(.caption.weight(selected == item.id ? .semibold : .regular))
                                    .foregroundStyle(Color.primary)
                            }
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(selected == item.id ? .isSelected : [])
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("App icon")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(highlight: .appIcons, source: .feature)
        }
    }

    private func choose(_ item: AppIcons.Item) {
        guard item.name == nil || store.data.isPro else {
            showingPaywall = true
            return
        }
        guard UIApplication.shared.supportsAlternateIcons, item.id != selected else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(item.assetName)
                Analytics.shared.action(.appIconChange)
                errorText = nil
                selected = item.id
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
