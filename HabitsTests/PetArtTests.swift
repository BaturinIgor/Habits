import SwiftUI
import XCTest
@testable import Habits

/// Нарисованные питомцы (design/pets/pets.js): соответствие состояний и отрисовка без сбоев.
@MainActor
final class PetArtTests: XCTestCase {

    // MARK: Состояния приложения -> дизайн

    func testStageMapping() {
        XCTAssertNil(PetArt.stageIndex(.egg))
        XCTAssertEqual(PetArt.stageIndex(.baby), 0)
        XCTAssertEqual(PetArt.stageIndex(.young), 1)
        XCTAssertEqual(PetArt.stageIndex(.adult), 2)
        XCTAssertEqual(PetArt.stageIndex(.legend), 3)
    }

    func testMoodMapping() {
        XCTAssertEqual(PetArt.emotion(for: .happy), .happy)
        XCTAssertEqual(PetArt.emotion(for: .calm), .happy)
        XCTAssertEqual(PetArt.emotion(for: .sad), .sad)
        XCTAssertEqual(PetArt.emotion(for: .lonely), .sad)
        XCTAssertEqual(PetArt.emotion(for: .sleeping), .sleep)
        for mood in [PetMood.happy, .calm, .sad, .lonely, .sleeping] {
            XCTAssertEqual(PetArt.emotion(for: mood, reacting: true), .cheer)
        }
    }

    func testEverySpeciesIsDrawn() {
        for species in Pets.all {
            XCTAssertNotNil(PetStyle.style(for: species.id), species.id)
        }
        XCTAssertEqual(PetStyle.all.count, 11)
        XCTAssertNil(PetStyle.style(for: "unknown"))
    }

    // MARK: Геометрия и поза

    func testSVGPathParser() {
        let triangle = SVGPath.parse("M96 10 h8 l-4 4 z").boundingRect
        XCTAssertEqual(triangle.minX, 96, accuracy: 0.01)
        XCTAssertEqual(triangle.width, 8, accuracy: 0.01)
        XCTAssertEqual(triangle.height, 4, accuracy: 0.01)
        // Полукруг радиуса 10: sweep 0 справа налево (ось y вниз) идёт через верх.
        let arc = SVGPath.parse("M110 50 A10 10 0 0 0 90 50").boundingRect
        XCTAssertEqual(arc.width, 20, accuracy: 0.1)
        XCTAssertEqual(arc.minY, 40, accuracy: 0.1)
        // Флаги дуги слитно («00») и относительная дуга с sweep 1 (через низ).
        XCTAssertEqual(SVGPath.parse("M110 50 A10 10 0 00 90 50").boundingRect.minY, 40, accuracy: 0.1)
        let relArc = SVGPath.parse("M110 50 a10 10 0 0 1 -20 0").boundingRect
        XCTAssertEqual(relArc.minX, 90, accuracy: 0.1)
        XCTAssertEqual(relArc.maxY, 60, accuracy: 0.1)

        // Неявный повтор команды: после l, после M (→ L) и после m (→ l).
        let zigzag = SVGPath.parse("M10 10 l5 5 5 -5").boundingRect
        XCTAssertEqual(zigzag, CGRect(x: 10, y: 10, width: 10, height: 5))
        let implicitL = SVGPath.parse("M0 0 10 0 10 4").boundingRect
        XCTAssertEqual(implicitL, CGRect(x: 0, y: 0, width: 10, height: 4))
        let implicitRel = SVGPath.parse("m10 10 5 5").boundingRect
        XCTAssertEqual(implicitRel, CGRect(x: 10, y: 10, width: 5, height: 5))
        // Отрицательные числа без пробела, «.5» и экспонента.
        XCTAssertEqual(SVGPath.parse("M0 0 L10 0 -5 .5").boundingRect, CGRect(x: -5, y: 0, width: 15, height: 0.5))
        let exponent = SVGPath.parse("M0 0 L1e1 0-2e-1 2.5E0").boundingRect
        XCTAssertEqual(exponent.minX, -0.2, accuracy: 0.001)
        XCTAssertEqual(exponent.maxX, 10, accuracy: 0.001)
        XCTAssertEqual(exponent.maxY, 2.5, accuracy: 0.001)
        // Относительные кривые: q и c от текущей точки.
        let quad = SVGPath.parse("M10 0 q5 5 10 0").boundingRect
        XCTAssertEqual(quad.minX, 10, accuracy: 0.01)
        XCTAssertEqual(quad.maxX, 20, accuracy: 0.01)
        XCTAssertEqual(quad.height, 2.5, accuracy: 0.01)
        let cubic = SVGPath.parse("M0 0 L5 0 c0 10 10 10 10 0").boundingRect
        XCTAssertEqual(cubic.maxX, 15, accuracy: 0.01)
        XCTAssertEqual(cubic.height, 7.5, accuracy: 0.01)
    }

    func testSceneLayersPerStageAndEmotion() {
        let cat = PetStyle.style(for: "cat")!
        let baby = PetScene(style: cat, stage: 0, emotion: .happy)
        XCTAssertFalse(baby.elements.contains { $0.group == .tail }, "у малыша нет хвоста")
        XCTAssertTrue(baby.elements.contains { $0.group == .eyes })
        let adult = PetScene(style: cat, stage: 2, emotion: .sleep)
        XCTAssertTrue(adult.elements.contains { $0.group == .tail })
        XCTAssertFalse(adult.elements.contains { $0.group == .eyes }, "во сне глаза закрыты")
        XCTAssertTrue(adult.elements.contains { $0.group == .z(0) })
        let cheer = PetScene(style: cat, stage: 3, emotion: .cheer)
        XCTAssertTrue(cheer.elements.contains { $0.group == .spark(4) })
    }

    func testPoseFollowsAnimationRules() {
        let rest = PetPose.at(0, emotion: .happy, full: true, reaction: nil)
        XCTAssertEqual(rest.breathe, 0, accuracy: 0.001)
        XCTAssertEqual(rest.blink, 1, accuracy: 0.001)
        XCTAssertEqual(rest.jumpY, 0, accuracy: 0.001)
        // Моргание на 95% цикла 3.6 с.
        XCTAssertEqual(PetPose.at(3.6 * 0.95, emotion: .happy, full: true, reaction: nil).blink, 0.08, accuracy: 0.001)
        // Пик прыжка на 20% от 1.6 с.
        XCTAssertEqual(PetPose.at(0, emotion: .cheer, full: true, reaction: 0.32).jumpY, -30, accuracy: 0.001)
        // Сон: хвост не двигается; минимальная анимация: хвост не двигается.
        XCTAssertEqual(PetPose.at(1.3, emotion: .sleep, full: true, reaction: nil).tailDegrees, 0)
        XCTAssertEqual(PetPose.at(1.3, emotion: .happy, full: false, reaction: nil).tailDegrees, 0)
        XCTAssertNotEqual(PetPose.at(1.3, emotion: .happy, full: true, reaction: nil).tailDegrees, 0)
    }

    // MARK: Отрисовка

    func testEverySpeciesRendersAtEveryStageAndEmotion() throws {
        for style in PetStyle.all {
            for stage in 0..<4 {
                for emotion in PetEmotion.allCases {
                    let scene = PetScene(style: style, stage: stage, emotion: emotion)
                    let renderer = ImageRenderer(content: PetArtView.canvas(scene, pose: .rest).frame(width: 60, height: 60))
                    let image = try XCTUnwrap(renderer.cgImage, "\(style.id) \(stage) \(emotion)")
                    let bounds = Self.opaqueBounds(image)
                    XCTAssertFalse(bounds.isEmpty, "\(style.id) \(stage) \(emotion)")
                    XCTAssertGreaterThan(bounds.height, CGFloat(image.height) * 0.3, "\(style.id) \(stage) \(emotion)")
                }
            }
        }
    }

    func testAvatarRendersForEveryMood() throws {
        let pet = PetState(species: "cat", name: "Test", adoptedAt: Date())
        for stage in PetStage.allCases {
            for mood in [PetMood.happy, .calm, .sad, .lonely, .sleeping] {
                let renderer = ImageRenderer(content: PetAvatar(pet: pet, stage: stage, mood: mood, size: 80, motion: .none))
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertFalse(Self.opaqueBounds(image).isEmpty)
            }
        }
    }

    /// Листы для сравнения с design/pets/preview. Пишет в PET_SHEET_DIR (TEST_RUNNER_PET_SHEET_DIR) или во временную папку.
    func testRenderSheets() throws {
        let dir = ProcessInfo.processInfo.environment["PET_SHEET_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let ids = PetStyle.all.map(\.id)
        try Self.write(Self.sheet(rows: ["cat"], columns: (0..<4).map { ($0, PetEmotion.happy) }, extraRows: [.sad, .sleep]),
                       to: dir.appendingPathComponent("kan86-cat-sheet.png"))
        try Self.write(Self.sheet(rows: ids, columns: (0..<4).map { ($0, PetEmotion.happy) }),
                       to: dir.appendingPathComponent("kan86-stages.png"))
        try Self.write(Self.sheet(rows: ids, columns: PetEmotion.allCases.map { (2, $0) }),
                       to: dir.appendingPathComponent("kan86-emotions.png"))
        // Кадры анимации кота: хвост в крайних точках, прыжок, искры, плывущие «z».
        let cat = PetStyle.style(for: "cat")!
        let frames: [(PetEmotion, PetPose)] = [
            (.happy, PetPose.at(0, emotion: .happy, full: true, reaction: nil)),
            (.happy, PetPose.at(1.3, emotion: .happy, full: true, reaction: nil)),
            (.cheer, PetPose.at(0, emotion: .cheer, full: true, reaction: 0.32)),
            (.cheer, PetPose.at(0, emotion: .cheer, full: true, reaction: 0.45)),
            (.sleep, PetPose.at(1.0, emotion: .sleep, full: true, reaction: nil)),
        ]
        let motion = HStack(spacing: 10) {
            ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                PetArtView.canvas(PetScene(style: cat, stage: 2, emotion: frame.0), pose: frame.1).frame(width: 200, height: 210)
            }
        }
        .padding(20)
        .background(Color(red: 0x4a / 255, green: 0x55 / 255, blue: 0x66 / 255))
        try Self.write(motion, to: dir.appendingPathComponent("kan86-cat-motion.png"))

        // Размеры питомца в виджетах (78 и 110 pt), статично, во сне - проверка текста «z» и тени в обеих темах.
        let pet = PetState(species: "cat", name: "Test", adoptedAt: Date())
        for scheme in [ColorScheme.light, .dark] {
            let widgets = HStack(spacing: 16) {
                PetAvatar(pet: pet, stage: .adult, mood: .sleeping, size: 78, motion: .none)
                    .frame(width: 170, height: 170)
                PetAvatar(pet: pet, stage: .legend, mood: .lonely, size: 110, motion: .none)
                    .frame(width: 364, height: 170)
            }
            .padding(16)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
            try Self.write(widgets, to: dir.appendingPathComponent("kan86-widget-\(scheme == .dark ? "dark" : "light").png"))
        }
    }

    // MARK: Помощники

    private static func sheet(rows: [String], columns: [(Int, PetEmotion)], extraRows: [PetEmotion] = []) -> some View {
        // Строки: виды (или для одного вида - эмоции, как cat-stages.png).
        let lines: [(String, [(Int, PetEmotion)])] = extraRows.isEmpty
            ? rows.map { id in (id, columns) }
            : ([PetEmotion.happy] + extraRows).map { emo in (rows[0], columns.map { ($0.0, emo) }) }
        return VStack(spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 10) {
                    Text(verbatim: line.0).font(.headline).foregroundStyle(.white).frame(width: 110, alignment: .leading)
                    ForEach(Array(line.1.enumerated()), id: \.offset) { _, cell in
                        PetArtView.canvas(PetScene(style: PetStyle.style(for: line.0)!, stage: cell.0, emotion: cell.1), pose: .rest)
                            .frame(width: 200, height: 210)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(red: 0x4a / 255, green: 0x55 / 255, blue: 0x66 / 255))
    }

    private static func write(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage?.pngData())
        try image.write(to: url)
    }

    /// Рамка непрозрачных пикселей.
    private static func opaqueBounds(_ image: CGImage) -> CGRect {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return .null }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 20 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
