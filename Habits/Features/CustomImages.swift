import Observation
import PhotosUI
import SwiftUI
import UIKit

/// Свои фото для фона и аватарки (Pro). Хранятся рядом с данными приложения.
@MainActor
@Observable
final class CustomImages {
    static let shared = CustomImages()
    static let photoID = "photo"

    enum Slot: String {
        case background, avatar
        var fileName: String { "custom-\(rawValue).jpg" }
        var maxSide: CGFloat { self == .avatar ? 480 : 1800 }
    }

    private(set) var background: UIImage?
    private(set) var avatar: UIImage?

    private init() {
        background = Self.load(.background)
        avatar = Self.load(.avatar)
    }

    func image(_ slot: Slot) -> UIImage? { slot == .avatar ? avatar : background }

    private static func url(_ slot: Slot) -> URL {
        AppGroup.containerURL.appendingPathComponent(slot.fileName)
    }

    private static func load(_ slot: Slot) -> UIImage? {
        guard let data = try? Data(contentsOf: url(slot)) else { return nil }
        return UIImage(data: data)
    }

    /// Уменьшает фото, для аватарки обрезает по центру в квадрат, и сохраняет.
    @discardableResult
    func save(_ data: Data, to slot: Slot) -> Bool {
        guard let source = UIImage(data: data) else { return false }
        let image = Self.prepare(source, for: slot)
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: Self.url(slot), options: .atomic)
        } catch {
            return false
        }
        if slot == .avatar { avatar = image } else { background = image }
        return true
    }

    private static func prepare(_ image: UIImage, for slot: Slot) -> UIImage {
        var size = image.size
        var origin = CGPoint.zero
        var canvas = size
        if slot == .avatar {
            let side = min(size.width, size.height)
            origin = CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)
            canvas = CGSize(width: side, height: side)
        }
        let scale = min(1, slot.maxSide / max(canvas.width, canvas.height))
        size = CGSize(width: size.width * scale, height: size.height * scale)
        origin = CGPoint(x: origin.x * scale, y: origin.y * scale)
        canvas = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }
}

/// Плитка "Своё фото" в профиле: выбор из галереи, только с Pro.
struct PhotoRewardTile: View {
    @Environment(HabitStore.self) private var store
    let slot: CustomImages.Slot
    let onLocked: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var images = CustomImages.shared

    private var selected: Bool {
        let settings = store.data.settings
        return (slot == .avatar ? settings.avatarID : settings.backgroundID) == CustomImages.photoID
    }

    var body: some View {
        Group {
            if store.data.isPro {
                PhotosPicker(selection: $item, matching: .images) { tile }
            } else {
                Button(action: onLocked) { tile }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   images.save(data, to: slot) {
                    withAnimation(.snappy) {
                        store.updateSettings {
                            if slot == .avatar { $0.avatarID = CustomImages.photoID } else { $0.backgroundID = CustomImages.photoID }
                        }
                    }
                }
                item = nil
            }
        }
    }

    private var tile: some View {
        let image = images.image(slot)
        let shape = RoundedRectangle(cornerRadius: slot == .avatar ? 30 : 16, style: .continuous)
        return ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "photo.badge.plus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(.black.opacity(0.45)))
                            .padding(4)
                    }
            } else {
                shape.fill(Color.accentColor.opacity(0.12))
                Image(systemName: "photo.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: slot == .avatar ? 60 : nil, height: slot == .avatar ? 60 : 84)
        .frame(maxWidth: slot == .avatar ? nil : .infinity)
        .clipShape(slot == .avatar ? AnyShape(Circle()) : AnyShape(shape))
        .overlay(alignment: .topTrailing) {
            ProBadge().scaleEffect(0.7)
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: slot == .avatar ? 34 : 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(-4)
            }
        }
        .accessibilityLabel(Text("Your photo"))
    }
}
