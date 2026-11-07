import SwiftUI

// Обёртки над API, которых нет в старых iOS. На iOS 26 — Liquid Glass,
// на iOS 17–25 — обычные системные стили, чтобы приложение работало с iOS 17.

extension View {
    /// `.glassButtonStyle()` / `.glassProminent` на iOS 26, иначе `.bordered` / `.borderedProminent`.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// `.glassEffect` на iOS 26, иначе материал с той же формой.
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// Таб-бар сворачивается при прокрутке вниз (только iOS 26).
    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Zoom-переход к экрану (iOS 18+), иначе обычный push.
    @ViewBuilder
    func zoomTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    /// Источник zoom-перехода (iOS 18+).
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
