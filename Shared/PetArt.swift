import SwiftUI

// Нарисованные питомцы в стиле «мягкий объём». Порт design/pets/pets.js:
// та же геометрия в пространстве 200×210 (viewBox 0 -22 200 210), масштабируется до размера вида.

// MARK: - Вид питомца

/// Внешность вида, как SP в pets.js.
struct PetStyle {
    enum Ears { case none, cat, flop, tuft, bunny, fox, round, owl, horns, horse, flame }
    enum Tail { case none, cat, stub, pom, fox, dragon, phoenix }
    enum Face { case plain, cat, dog, beak, bunny, fox, panda, owl }

    let id: String
    let fur: Color
    let light: Color
    let belly: Color
    let line: Color
    var dark: Color = .black
    var stripe: Color = .clear
    var inner: Color = .clear
    var beak: Color = .orange
    var wingsBack: Color?
    let ears: Ears
    let tail: Tail
    let face: Face
    var wings = false
    var shell = false
    var spikes = false
    var horn = false
    var mane = false

    static let all: [PetStyle] = [
        PetStyle(id: "cat", fur: Color(petHex: 0xf5a04a), light: Color(petHex: 0xffd9a0), belly: Color(petHex: 0xfff3e0),
                 line: Color(petHex: 0xd9853a), stripe: Color(petHex: 0xe8913f), inner: Color(petHex: 0xffb3b3),
                 ears: .cat, tail: .cat, face: .cat),
        PetStyle(id: "dog", fur: Color(petHex: 0xd39a62), light: Color(petHex: 0xf1d3a8), belly: Color(petHex: 0xfff4e4),
                 line: Color(petHex: 0xa8703f), dark: Color(petHex: 0x8a5a35), ears: .flop, tail: .stub, face: .dog),
        PetStyle(id: "chick", fur: Color(petHex: 0xffd23f), light: Color(petHex: 0xfff3a6), belly: Color(petHex: 0xfff8d0),
                 line: Color(petHex: 0xe0a800), beak: Color(petHex: 0xff9a3c), ears: .tuft, tail: .none, face: .beak, wings: true),
        PetStyle(id: "bunny", fur: Color(petHex: 0xece6e0), light: Color(petHex: 0xffffff), belly: Color(petHex: 0xffffff),
                 line: Color(petHex: 0xb9aea3), inner: Color(petHex: 0xffc2cc), ears: .bunny, tail: .pom, face: .bunny),
        PetStyle(id: "turtle", fur: Color(petHex: 0x9ad36f), light: Color(petHex: 0xd4f5b4), belly: Color(petHex: 0xf3f7c9),
                 line: Color(petHex: 0x5e9c3e), ears: .none, tail: .none, face: .plain, shell: true),
        PetStyle(id: "fox", fur: Color(petHex: 0xf27b2f), light: Color(petHex: 0xffb47a), belly: Color(petHex: 0xfffaf3),
                 line: Color(petHex: 0xc2551a), inner: Color(petHex: 0x5a3220), ears: .fox, tail: .fox, face: .fox),
        PetStyle(id: "panda", fur: Color(petHex: 0xf6f6f4), light: Color(petHex: 0xffffff), belly: Color(petHex: 0xffffff),
                 line: Color(petHex: 0xa9a9a9), dark: Color(petHex: 0x2f3138), ears: .round, tail: .none, face: .panda),
        PetStyle(id: "owl", fur: Color(petHex: 0xa8794e), light: Color(petHex: 0xd8b48a), belly: Color(petHex: 0xf1e0c6),
                 line: Color(petHex: 0x7a5230), beak: Color(petHex: 0xf2b33d), ears: .owl, tail: .none, face: .owl, wings: true),
        PetStyle(id: "dragon", fur: Color(petHex: 0x4fbf8f), light: Color(petHex: 0xa8ecc8), belly: Color(petHex: 0xfbe9a6),
                 line: Color(petHex: 0x2f8a63), wingsBack: Color(petHex: 0x3aa67a), ears: .horns, tail: .dragon, face: .plain,
                 spikes: true),
        PetStyle(id: "unicorn", fur: Color(petHex: 0xfbf7ff), light: Color(petHex: 0xffffff), belly: Color(petHex: 0xffffff),
                 line: Color(petHex: 0xcdbbe0), inner: Color(petHex: 0xffd0e4), ears: .horse, tail: .none, face: .plain,
                 horn: true, mane: true),
        PetStyle(id: "phoenix", fur: Color(petHex: 0xff6b3d), light: Color(petHex: 0xffc06a), belly: Color(petHex: 0xffe0a3),
                 line: Color(petHex: 0xd94a1e), beak: Color(petHex: 0xffd34d), ears: .flame, tail: .phoenix, face: .beak, wings: true),
    ]

    /// Нарисованный вид для id из Pets.all; nil - рисуем эмодзи.
    static func style(for species: String) -> PetStyle? { byID[species] }

    private static let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
}

// MARK: - Состояния приложения -> дизайн

enum PetEmotion: Int, CaseIterable {
    case happy, sad, sleep, cheer
}

enum PetArt {
    /// Стадия дизайна: 0 малыш, 1 подросток, 2 взрослый (ошейник), 3 легенда (корона). Яйцо не рисуется.
    static func stageIndex(_ stage: PetStage) -> Int? {
        switch stage {
        case .egg: nil
        case .baby: 0
        case .young: 1
        case .adult: 2
        case .legend: 3
        }
    }

    /// Эмоция дизайна для настроения; reacting - питомец только что получил отметку или корм.
    static func emotion(for mood: PetMood, reacting: Bool = false) -> PetEmotion {
        if reacting { return .cheer }
        switch mood {
        case .happy, .calm: return .happy
        case .sad, .lonely: return .sad
        case .sleeping: return .sleep
        }
    }
}

// MARK: - Сцена

/// Готовые фигуры питомца в координатах дизайна. Позы (дыхание, моргание, хвост) накладываются при отрисовке.
struct PetScene {
    enum Group: Equatable { case still, tail, eyes, z(Int), spark(Int) }
    /// fur - градиент меха; shadow - тень на земле, цвет зависит от темы.
    enum Paint { case color(Color), fur, shadow }

    struct Stroke {
        var color: Color
        var width: CGFloat
        var cap: CGLineCap = .butt
        var join: CGLineJoin = .miter
    }

    enum Content {
        case shape(Path, fill: Paint?, stroke: Stroke?)
        case text(String, size: CGFloat, baseline: CGPoint, color: Color)
    }

    struct Element {
        var content: Content
        /// Внутри группы тела (прыжок, дыхание, масштаб стадии).
        var inBody: Bool
        var group: Group = .still
        var opacity: Double = 1
    }

    let stage: Int
    let emotion: PetEmotion
    let scale: CGFloat
    let headY: CGFloat
    let furGradient: Gradient
    let gradientCenter: CGPoint
    let gradientRadius: CGFloat
    var elements: [Element] = []

    /// Центр моргания (глаза сжимаются по вертикали вокруг него).
    var eyeCenter: CGPoint { CGPoint(x: 100, y: headY - 8) }
    static let tailPivot = CGPoint(x: 132, y: 162)
    static let ground = CGPoint(x: 100, y: 184)

    private static let cache = NSCache<NSString, Box>()
    private final class Box { let scene: PetScene; init(_ scene: PetScene) { self.scene = scene } }

    static func cached(_ style: PetStyle, stage: Int, emotion: PetEmotion) -> PetScene {
        let key = "\(style.id)-\(stage)-\(emotion.rawValue)" as NSString
        if let box = cache.object(forKey: key) { return box.scene }
        let scene = PetScene(style: style, stage: stage, emotion: emotion)
        cache.setObject(Box(scene), forKey: key)
        return scene
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    init(style S: PetStyle, stage: Int, emotion: PetEmotion) {
        let stage = min(max(stage, 0), 3)
        self.stage = stage
        self.emotion = emotion
        let emo = emotion.rawValue
        let s: CGFloat = [0.72, 0.84, 0.94, 1][stage]
        let headY: CGFloat = stage >= 2 ? 92 : 112
        let hr: CGFloat = stage >= 2 ? 58 : 66
        scale = s
        self.headY = headY
        furGradient = Gradient(stops: [.init(color: S.light, location: 0), .init(color: S.fur, location: 0.75)])
        gradientCenter = CGPoint(x: 86, y: headY - hr * 0.45)
        gradientRadius = hr * 1.5

        let ink = Color(petHex: 0x2b2b3a)
        let blush = Color(petHex: 0xff8a8a)
        let white = Color.white
        func R(_ x: CGFloat, _ y: CGFloat) -> String { "\(100 + x * hr) \(headY + y * hr)" }
        let ln = Stroke(color: S.line, width: 2.5, join: .round)

        var out: [Element] = []
        func add(_ d: String, fill: Paint? = nil, stroke: Stroke? = nil, body: Bool = true,
                 group: Group = .still, opacity: Double = 1, transform: CGAffineTransform = .identity) {
            out.append(Element(content: .shape(SVGPath.parse(d).applying(transform), fill: fill, stroke: stroke),
                               inBody: body, group: group, opacity: opacity))
        }
        func addPath(_ p: Path, fill: Paint? = nil, stroke: Stroke? = nil, body: Bool = true,
                     group: Group = .still, opacity: Double = 1) {
            out.append(Element(content: .shape(p, fill: fill, stroke: stroke), inBody: body, group: group, opacity: opacity))
        }
        func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        }
        func rotation(_ deg: CGFloat, _ cx: CGFloat, _ cy: CGFloat) -> CGAffineTransform {
            CGAffineTransform(translationX: cx, y: cy).rotated(by: deg * .pi / 180).translatedBy(x: -cx, y: -cy)
        }
        let color = { (c: Color) in Paint.color(c) }

        // Искры легенды и тень (вне тела).
        if stage == 3 {
            let gold = color(Color(petHex: 0xffe27a))
            add("M30 60 l4 10 l10 4 l-10 4 l-4 10 l-4 -10 l-10 -4 l10 -4z", fill: gold, body: false)
            add("M170 66 l3 7 l7 3 l-7 3 l-3 7 l-3 -7 l-7 -3 l7 -3z", fill: gold, body: false)
        }
        addPath(ellipse(100, 184, 56 * s, 7), fill: .shadow, body: false, opacity: 0.18)

        // Задний слой: хвосты, панцирь, крылья за спиной.
        if stage >= 1 {
            switch S.tail {
            case .cat:
                addPath(Self.tailPoly([(130, 166), (176, 178), (194, 140), (170, 128)], 9.5, 5), fill: color(S.fur), stroke: ln, group: .tail)
            case .fox:
                addPath(Self.tailPoly([(128, 166), (186, 176), (196, 120), (168, 104)], 13, 9), fill: color(S.fur), stroke: ln, group: .tail)
                addPath(ellipse(168, 106, 10, 10), fill: color(Color(petHex: 0xfffaf3)), stroke: Stroke(color: S.line, width: 2.5), group: .tail)
            case .dragon:
                addPath(Self.tailPoly([(128, 168), (178, 180), (192, 150), (186, 128)], 11, 4), fill: color(S.fur), stroke: ln, group: .tail)
                add("M180 128 l10 -8 l2 12z", fill: color(S.belly), stroke: Stroke(color: S.line, width: 2, join: .round), group: .tail)
            case .stub:
                addPath(Self.tailPoly([(136, 160), (156, 156), (162, 140), (160, 128)], 8, 6), fill: color(S.fur), stroke: ln, group: .tail)
            case .pom:
                addPath(ellipse(152, 160, 13, 13), fill: color(white), stroke: Stroke(color: S.line, width: 2.5))
            case .phoenix:
                let st = Stroke(color: S.line, width: 2, join: .round)
                add("M130 160 C160 170 186 160 194 132 C180 146 166 150 150 148Z", fill: color(Color(petHex: 0xffb03a)), stroke: st)
                add("M128 166 C162 184 190 176 198 156 C182 166 164 166 148 158Z", fill: color(Color(petHex: 0xff6b3d)), stroke: st)
            case .none:
                break
            }
        }
        if S.shell {
            let sy: CGFloat = stage >= 2 ? 138 : 140, rx: CGFloat = stage >= 2 ? 72 : 78, ry: CGFloat = 50
            let dark = Color(petHex: 0x8a5a2b), light = Color(petHex: 0xe3ad6e)
            addPath(ellipse(100, sy, rx, ry), fill: color(Color(petHex: 0xc98b4a)), stroke: Stroke(color: dark, width: 2.5))
            addPath(ellipse(100, sy, rx - 9, ry - 9), stroke: Stroke(color: light, width: 5))
            let st = Stroke(color: dark, width: 1.5, join: .round)
            add("M\(100 - rx + 12) \(sy - 4) l10 -16 l14 4 l2 18 l-12 10 l-12 -6z", fill: color(light), stroke: st)
            add("M\(100 + rx - 12) \(sy - 4) l-10 -16 l-14 4 l-2 18 l12 10 l12 -6z", fill: color(light), stroke: st)
        }
        if let wb = S.wingsBack, stage >= 1 {
            let h = headY
            add("M52 \(h + 40) C20 \(h + 20) 18 \(h - 10) 30 \(h - 24) C34 \(h) 44 \(h + 12) 60 \(h + 18)Z", fill: color(wb), stroke: ln)
            add("M148 \(h + 40) C180 \(h + 20) 182 \(h - 10) 170 \(h - 24) C166 \(h) 156 \(h + 12) 140 \(h + 18)Z", fill: color(wb), stroke: ln)
        }
        if stage >= 2 {
            addPath(ellipse(100, 150, 54, 36), fill: S.shell ? color(S.belly) : .fur, stroke: ln)
            addPath(ellipse(100, 156, 30, 22), fill: color(S.belly), opacity: 0.95)
        }

        // Уши за головой.
        for sx: CGFloat in [-1, 1] {
            switch S.ears {
            case .round:
                addPath(ellipse(100 + sx * hr * 0.72, headY - hr * 0.74, hr * 0.3, hr * 0.3), fill: color(S.dark))
            case .bunny:
                let t = rotation(sx * 10, 100 + sx * hr * 0.38, headY - hr * 0.8)
                addPath(ellipse(100 + sx * hr * 0.38, headY - hr * 1.35, hr * 0.2, hr * 0.62).applying(t), fill: color(S.fur), stroke: ln)
                addPath(ellipse(100 + sx * hr * 0.38, headY - hr * 1.3, hr * 0.1, hr * 0.46).applying(t), fill: color(S.inner))
            case .fox, .horse:
                let tip = R(sx * 0.72, S.ears == .fox ? -1.45 : -1.25)
                add("M\(R(sx * 0.82, -0.42)) Q\(R(sx * 0.9, -1.1)) \(tip) Q\(R(sx * 0.5, -1.15)) \(R(sx * 0.22, -0.92))Z", fill: color(S.fur), stroke: ln)
                add("M\(R(sx * 0.72, -0.72)) Q\(R(sx * 0.76, -1.1)) \(R(sx * 0.71, -1.3)) Q\(R(sx * 0.52, -1.05)) \(R(sx * 0.42, -0.9))Z", fill: color(S.inner))
            case .owl:
                add("M\(R(sx * 0.75, -0.6)) L\(R(sx * 0.82, -1.18)) L\(R(sx * 0.35, -0.92))Z", fill: color(S.fur), stroke: ln)
            case .horns:
                add("M\(R(sx * 0.5, -0.82)) Q\(R(sx * 0.62, -1.3)) \(R(sx * 0.78, -1.36)) Q\(R(sx * 0.6, -1.0)) \(R(sx * 0.28, -0.92))Z",
                    fill: color(Color(petHex: 0xfff4d6)), stroke: ln)
            default:
                break
            }
        }
        if S.ears == .flame && stage < 3 {
            let st = Stroke(color: S.line, width: 2, join: .round)
            add("M\(R(-0.25, -0.9)) C\(R(-0.5, -1.3)) \(R(-0.2, -1.4)) \(R(-0.3, -1.6)) C\(R(0, -1.4)) \(R(0.05, -1.2)) \(R(0, -0.95))Z",
                fill: color(Color(petHex: 0xffb03a)), stroke: st)
            add("M\(R(-0.08, -0.95)) C\(R(-0.15, -1.4)) \(R(0.2, -1.5)) \(R(0.12, -1.75)) C\(R(0.42, -1.45)) \(R(0.35, -1.2)) \(R(0.22, -0.92))Z",
                fill: color(Color(petHex: 0xffd34d)), stroke: st)
            add("M\(R(0.15, -0.94)) C\(R(0.3, -1.3)) \(R(0.55, -1.3)) \(R(0.5, -1.5)) C\(R(0.7, -1.2)) \(R(0.55, -1.0)) \(R(0.4, -0.85))Z",
                fill: color(Color(petHex: 0xff8a3d)), stroke: st)
        }
        if S.ears == .tuft {
            add("M\(R(-0.05, -0.96)) C\(R(-0.2, -1.3)) \(R(0.05, -1.32)) \(R(0, -1.18)) C\(R(0.12, -1.36)) \(R(0.3, -1.2)) \(R(0.1, -0.96))Z",
                fill: color(S.fur), stroke: ln)
        }

        // Голова.
        if S.ears == .cat {
            func P(_ deg: CGFloat) -> String {
                let t = deg * .pi / 180
                return "\(100 + hr * cos(t)) \(headY - hr * sin(t))"
            }
            add("M\(P(150)) C\(R(-0.93, -0.78)) \(R(-0.85, -1.22)) \(R(-0.77, -1.35)) C\(R(-0.72, -1.38)) \(R(-0.66, -1.32)) \(R(-0.56, -1.17)) "
                + "C\(R(-0.46, -1.06)) \(R(-0.4, -0.97)) \(P(108)) A\(hr) \(hr) 0 0 1 \(P(72)) "
                + "C\(R(0.4, -0.97)) \(R(0.46, -1.06)) \(R(0.56, -1.17)) C\(R(0.66, -1.32)) \(R(0.72, -1.38)) \(R(0.77, -1.35)) "
                + "C\(R(0.85, -1.22)) \(R(0.93, -0.78)) \(P(30)) A\(hr) \(hr) 0 1 1 \(P(150)) Z", fill: .fur, stroke: ln)
            for sx: CGFloat in [-1, 1] {
                add("M\(R(sx * 0.72, -0.86)) C\(R(sx * 0.72, -1.04)) \(R(sx * 0.72, -1.18)) \(R(sx * 0.7, -1.2)) "
                    + "C\(R(sx * 0.64, -1.2)) \(R(sx * 0.56, -1.08)) \(R(sx * 0.46, -0.98)) Z", fill: color(S.inner))
            }
            add("M\(R(-0.13, -0.94)) L\(R(-0.1, -0.78)) M\(R(0, -0.98)) L\(R(0, -0.8)) M\(R(0.13, -0.94)) L\(R(0.1, -0.78))",
                stroke: Stroke(color: S.stripe, width: 4.5, cap: .round))
        } else {
            addPath(ellipse(100, headY, hr + 2, hr), fill: .fur, stroke: ln)
        }

        // Украшения головы.
        if S.face == .fox {
            add("M\(R(-1.0, 0.05)) Q\(R(-0.5, -0.1)) \(R(0, 0.2)) Q\(R(0.5, -0.1)) \(R(1.0, 0.05)) Q\(R(0.8, 0.75)) \(R(0, 0.98)) "
                + "Q\(R(-0.8, 0.75)) \(R(-1.0, 0.05))Z", fill: color(Color(petHex: 0xfffaf3)))
        }
        if S.face == .panda {
            for sx: CGFloat in [-1, 1] {
                let cx = 100 + sx * 24, cy = headY - 6
                addPath(ellipse(cx, cy, 13, 17).applying(rotation(sx * -25, cx, cy)), fill: color(S.dark))
            }
        }
        if S.face == .owl {
            for sx: CGFloat in [-1, 1] {
                addPath(ellipse(100 + sx * 24, headY - 8, 20, 20), fill: color(S.belly), stroke: Stroke(color: S.line, width: 1.5))
            }
        }
        if S.mane {
            add("M\(R(-0.1, -1.0)) C\(R(-0.7, -1.05)) \(R(-1.1, -0.5)) \(R(-0.95, 0.15)) C\(R(-0.8, -0.3)) \(R(-0.6, -0.6)) \(R(-0.2, -0.72))Z",
                fill: color(Color(petHex: 0xf7a8d8)))
            add("M\(R(-0.15, -0.98)) C\(R(-0.6, -0.9)) \(R(-0.85, -0.5)) \(R(-0.82, -0.05)) C\(R(-0.65, -0.4)) \(R(-0.45, -0.6)) \(R(-0.1, -0.76))Z",
                fill: color(Color(petHex: 0xb7a4f7)))
            add("M\(R(0.05, -1.0)) C\(R(0.4, -1.02)) \(R(0.55, -0.9)) \(R(0.62, -0.78)) C\(R(0.4, -0.82)) \(R(0.2, -0.8)) \(R(0.0, -0.74))Z",
                fill: color(Color(petHex: 0x9fd8f7)))
        }
        let addHorn = {
            add("M\(R(-0.13, -0.92)) L\(R(0, -1.5)) L\(R(0.13, -0.92))Z", fill: color(Color(petHex: 0xffd34d)),
                stroke: Stroke(color: Color(petHex: 0xd9a400), width: 2, join: .round))
            add("M\(R(-0.1, -1.08)) L\(R(0.08, -1.02)) M\(R(-0.07, -1.22)) L\(R(0.06, -1.17)) M\(R(-0.04, -1.36)) L\(R(0.04, -1.32))",
                stroke: Stroke(color: Color(petHex: 0xd9a400), width: 1.5))
        }
        if S.horn && stage < 3 { addHorn() }
        if S.ears == .flop {
            for sx: CGFloat in [-1, 1] {
                add("M\(R(sx * 0.55, -0.88)) C\(R(sx * 1.05, -0.95)) \(R(sx * 1.15, -0.2)) \(R(sx * 0.95, 0.15)) "
                    + "C\(R(sx * 0.8, 0.3)) \(R(sx * 0.68, 0.0)) \(R(sx * 0.72, -0.35)) C\(R(sx * 0.74, -0.6)) \(R(sx * 0.62, -0.75)) \(R(sx * 0.4, -0.82))Z",
                    fill: color(S.dark), stroke: Stroke(color: S.line, width: 2, join: .round))
            }
        }

        // Мордочка.
        let y = headY - 8
        let beak = S.face == .beak || S.face == .owl
        if !beak && S.face != .fox && S.face != .panda {
            addPath(ellipse(100, headY + (stage < 2 ? 24 : 20), stage < 2 ? 34 : 30, stage < 2 ? 24 : 20), fill: color(S.belly), opacity: 0.95)
        }
        if S.face == .panda { addPath(ellipse(100, headY + 22, 26, 18), fill: color(white)) }

        // Глаза.
        let eyeInk = S.face == .panda ? white : ink
        if emo == 2 {
            add("M66 \(y) q10 8 20 0 M114 \(y) q10 8 20 0", stroke: Stroke(color: eyeInk, width: 3.5, cap: .round))
        } else if emo == 3 {
            add("M66 \(y + 3) q10 -12 20 0 M114 \(y + 3) q10 -12 20 0", stroke: Stroke(color: eyeInk, width: 4, cap: .round))
        } else {
            let ry: CGFloat = stage == 0 ? 13 : 11.5
            addPath(ellipse(76, y, ry - 2, ry), fill: color(ink), group: .eyes)
            addPath(ellipse(124, y, ry - 2, ry), fill: color(ink), group: .eyes)
            addPath(ellipse(79, y - 4, 3.8, 3.8), fill: color(white), group: .eyes)
            addPath(ellipse(127, y - 4, 3.8, 3.8), fill: color(white), group: .eyes)
            addPath(ellipse(73.5, y + 4, 1.8, 1.8), fill: color(white), group: .eyes, opacity: 0.8)
            addPath(ellipse(121.5, y + 4, 1.8, 1.8), fill: color(white), group: .eyes, opacity: 0.8)
            if emo == 1 {
                add("M64 \(y - 15) L86 \(y - 22) M136 \(y - 15) L114 \(y - 22)", stroke: Stroke(color: eyeInk, width: 3, cap: .round))
                add("M70 \(y + 12) q-4 8 0 12 q4 -4 0 -12z", fill: color(Color(petHex: 0x7cc4ff)))
            }
        }
        addPath(ellipse(60, y + 20, 10, 6), fill: color(blush), opacity: emo == 1 ? 0.25 : 0.5)
        addPath(ellipse(140, y + 20, 10, 6), fill: color(blush), opacity: emo == 1 ? 0.25 : 0.5)

        // Нос и рот.
        if beak {
            add("M92 \(y + 12) Q100 \(y + 8) 108 \(y + 12) L100 \(y + 24)Z", fill: color(S.beak),
                stroke: Stroke(color: Color(petHex: 0xd98a1e), width: 1.5, join: .round))
            if emo == 3 { add("M94 \(y + 17) L106 \(y + 17) L100 \(y + 28)Z", fill: color(Color(petHex: 0xe0602a))) }
        } else {
            switch S.face {
            case .dog, .panda: addPath(ellipse(100, y + 14, 7, 5), fill: color(ink))
            case .fox: addPath(ellipse(100, y + 14, 5, 4), fill: color(ink))
            default: add("M96 \(y + 14) h8 l-4 4 z", fill: color(Color(petHex: 0xd9605a)))
            }
            let mouth = Stroke(color: ink, width: 2.5, cap: .round)
            switch emo {
            case 0: add("M92 \(y + 23) q4 5 8 0 q4 5 8 0", stroke: mouth)
            case 1: add("M93 \(y + 28) q7 -6 14 0", stroke: mouth)
            case 2: addPath(ellipse(100, y + 26, 3, 2.5), fill: color(ink))
            default: add("M90 \(y + 21) q10 14 20 0 z", fill: color(Color(petHex: 0xc9504a)))
            }
            if S.face == .dog && (emo == 0 || emo == 3) { add("M96 \(y + 27) q4 9 8 0z", fill: color(Color(petHex: 0xff7d8a))) }
            if S.face == .bunny {
                addPath(Path(roundedRect: CGRect(x: 96, y: y + 25, width: 8, height: 7), cornerRadius: 1.5),
                        fill: color(white), stroke: Stroke(color: S.line, width: 1))
            }
            if S.face == .cat {
                add("M\(R(-0.62, 0.22)) L\(R(-0.98, 0.14)) M\(R(-0.62, 0.3)) L\(R(-0.96, 0.34)) "
                    + "M\(R(0.62, 0.22)) L\(R(0.98, 0.14)) M\(R(0.62, 0.3)) L\(R(0.96, 0.34))",
                    stroke: Stroke(color: S.line, width: 1.6, cap: .round), opacity: 0.7)
            }
        }

        // Крылья по бокам.
        if S.wings {
            let big = stage >= 2
            for sx: CGFloat in [-1, 1] {
                let x0 = 100 + sx * (big ? 50 : 58), y0: CGFloat = big ? 140 : 118
                add("M\(x0) \(y0) C\(100 + sx * 74) \(big ? 146 : 126) \(100 + sx * 76) \(big ? 166 : 150) \(100 + sx * 60) \(big ? 172 : 160) "
                    + "C\(100 + sx * 56) \(big ? 160 : 146) \(100 + sx * 50) \(big ? 150 : 132) \(x0) \(y0)Z", fill: color(S.fur), stroke: ln)
            }
        }
        if S.face == .owl && stage >= 2 {
            add("M90 150 l5 5 l5 -5 l5 5 l5 -5 M90 162 l5 5 l5 -5 l5 5 l5 -5", stroke: Stroke(color: S.line, width: 2, cap: .round))
        }
        if S.spikes && stage >= 1 {
            add("M\(R(-0.08, -0.98)) l8 -14 l8 14z", fill: color(S.belly), stroke: Stroke(color: S.line, width: 2, join: .round))
        }

        // Лапы.
        if beak {
            add("M70 176 l-6 6 h24 l-6 -6z", fill: color(S.beak))
            add("M118 176 l-6 6 h24 l-6 -6z", fill: color(S.beak))
        } else if S.horn {
            for x: CGFloat in [78, 122] {
                add("M\(x - 12) 166 L\(x - 13) 178 Q\(x) 183 \(x + 13) 178 L\(x + 12) 166Z", fill: color(Color(petHex: 0xfbf7ff)), stroke: ln)
                add("M\(x - 13) 174 Q\(x) 179 \(x + 13) 174 L\(x + 13) 178 Q\(x) 183 \(x - 13) 178Z", fill: color(Color(petHex: 0xc9a8ef)),
                    stroke: Stroke(color: Color(petHex: 0xa989d6), width: 2, join: .round))
            }
        } else {
            let paw = S.face == .panda ? S.dark : S.light
            addPath(ellipse(78, 176, 14, 8), fill: color(paw))
            addPath(ellipse(122, 176, 14, 8), fill: color(paw))
        }
        if S.face == .panda && stage >= 2 {
            addPath(ellipse(54, 148, 12, 20), fill: color(S.dark))
            addPath(ellipse(146, 148, 12, 20), fill: color(S.dark))
        }

        // Ошейник взрослого и корона легенды.
        if stage == 2 && !S.wings && !S.shell {
            let ny = headY + hr * 0.86, w = hr * 0.66
            add("M\(100 - w) \(ny - 8) Q100 \(ny + 14) \(100 + w) \(ny - 8)", stroke: Stroke(color: Color(petHex: 0xe8505b), width: 8, cap: .round))
            addPath(ellipse(100, ny + 9, 7, 7), fill: color(Color(petHex: 0xffd34d)), stroke: Stroke(color: Color(petHex: 0xd9a400), width: 1.5))
            add("M95 \(ny + 10) h10", stroke: Stroke(color: Color(petHex: 0xb07f00), width: 1.5, cap: .round))
            addPath(ellipse(100, ny + 13, 1.6, 1.6), fill: color(Color(petHex: 0x8a6200)))
        }
        if stage == 3 {
            let by = headY - hr + 10
            let gold = Color(petHex: 0xffd34d), rim = Color(petHex: 0xe0a400)
            add("M78 \(by) L74 \(by - 24) L88 \(by - 12) L100 \(by - 30) L112 \(by - 12) L126 \(by - 24) L122 \(by) Q100 \(by + 8) 78 \(by) Z",
                fill: color(gold), stroke: Stroke(color: rim, width: 2.5, join: .round))
            add("M80 \(by - 3) Q100 \(by + 4) 120 \(by - 3)", stroke: Stroke(color: rim, width: 2))
            addPath(ellipse(100, by - 11, 3.5, 3.5), fill: color(Color(petHex: 0xff6b8a)))
            addPath(ellipse(74, by - 25, 2.5, 2.5), fill: color(gold))
            addPath(ellipse(100, by - 31, 2.8, 2.8), fill: color(gold))
            addPath(ellipse(126, by - 25, 2.5, 2.5), fill: color(gold))
            if S.horn { addHorn() }
        }

        // Сон: «z». Отметка: искры и +1 (видны только в анимации, как в cat-animation.html).
        let zColor = Color(petHex: 0xcfd8ff)
        if emo == 2 {
            out.append(Element(content: .text("z", size: 22, baseline: CGPoint(x: 150, y: 44), color: zColor), inBody: false, group: .z(0)))
            out.append(Element(content: .text("z", size: 16, baseline: CGPoint(x: 166, y: 28), color: zColor), inBody: false, group: .z(1)))
        }
        if emo == 3 {
            let sparks: [(CGFloat, CGFloat, CGFloat)] = [(34, 64, 1.2), (168, 48, 1), (176, 116, 0.8), (26, 128, 0.8)]
            for (i, sp) in sparks.enumerated() {
                let t = CGAffineTransform(translationX: sp.0, y: sp.1).scaledBy(x: sp.2, y: sp.2)
                add("M0 -10 L3 -3 L10 0 L3 3 L0 10 L-3 3 L-10 0 L-3 -3Z", fill: color(Color(petHex: 0xffe27a)), body: false,
                    group: .spark(i), transform: t)
            }
            out.append(Element(content: .text("+1", size: 15, baseline: CGPoint(x: 128, y: 30), color: Color(petHex: 0xffe27a)),
                               inBody: false, group: .spark(4)))
        }
        elements = out
    }

    /// Хвост: полоса переменной ширины вдоль кубической кривой с закруглённым концом (tailPoly из pets.js).
    static func tailPoly(_ pts: [(CGFloat, CGFloat)], _ w0: CGFloat, _ w1: CGFloat) -> Path {
        let (p0, p1, p2, p3) = (pts[0], pts[1], pts[2], pts[3])
        let n = 24
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n), m = 1 - t
            let x = m * m * m * p0.0 + 3 * m * m * t * p1.0 + 3 * m * t * t * p2.0 + t * t * t * p3.0
            let y = m * m * m * p0.1 + 3 * m * m * t * p1.1 + 3 * m * t * t * p2.1 + t * t * t * p3.1
            let dx = 3 * m * m * (p1.0 - p0.0) + 6 * m * t * (p2.0 - p1.0) + 3 * t * t * (p3.0 - p2.0)
            let dy = 3 * m * m * (p1.1 - p0.1) + 6 * m * t * (p2.1 - p1.1) + 3 * t * t * (p3.1 - p2.1)
            let len = max(hypot(dx, dy), 0.0001), w = w0 + (w1 - w0) * t
            left.append(CGPoint(x: x - dy / len * w, y: y + dx / len * w))
            right.append(CGPoint(x: x + dy / len * w, y: y - dx / len * w))
        }
        var path = Path()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        SVGPath.addArc(&path, from: left[n], rx: w1, ry: w1, rotation: 0, large: false, sweep: false, to: right[n])
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Поза (анимация)

/// Как сильно двигается питомец.
enum PetMotion {
    /// Полная анимация на больших размерах, минимальная на маленьких.
    case automatic
    /// Только дыхание, моргание и прыжок на отметку.
    case minimal
    /// Статичная картинка (виджет).
    case none
}

struct PetPose {
    var breathe: CGFloat = 0
    var blink: CGFloat = 1
    var tailDegrees: CGFloat = 0
    var jumpY: CGFloat = 0
    var jumpScale = CGSize(width: 1, height: 1)
    /// Сдвиг и прозрачность «z».
    var z: [(offset: CGSize, opacity: Double)] = [(.zero, 1), (.zero, 1)]
    /// Масштаб, сдвиг и прозрачность искр и «+1».
    var sparks: [(scale: CGFloat, dy: CGFloat, opacity: Double)] = Array(repeating: (1, 0, 0), count: 5)

    static let rest = PetPose()

    /// Поза в момент времени по правилам cat-animation.html.
    /// - Parameters:
    ///   - full: false - только дыхание, моргание и прыжок.
    ///   - reaction: секунды с отметки привычки, nil - реакции нет.
    static func at(_ time: TimeInterval, emotion: PetEmotion, full: Bool, reaction: TimeInterval?) -> PetPose {
        var pose = PetPose()
        let breathePeriod: Double = switch emotion {
        case .sleep: 5
        case .sad: 4
        default: 3
        }
        pose.breathe = CGFloat((1 - cos(2 * .pi * time / breathePeriod)) / 2)

        let b = time.truncatingRemainder(dividingBy: 3.6) / 3.6
        pose.blink = CGFloat(keyframes(b, [(0, 1), (0.92, 1), (0.95, 0.08), (1, 1)], ease: false))

        if full {
            let tailPeriod: Double? = switch emotion {
            case .sleep: nil
            case .sad: 5
            case .cheer: 0.55
            case .happy: 2.6
            }
            if let tailPeriod {
                let w = (1 - cos(2 * .pi * time / tailPeriod)) / 2
                pose.tailDegrees = CGFloat(3 - 10 * w)
            }
            if emotion == .sleep {
                for i in 0..<2 {
                    let p = (time + Double(i) * 1.5).truncatingRemainder(dividingBy: 3) / 3
                    let e = smooth(p)
                    let opacity = p < 0.3 ? smooth(p / 0.3) : 1 - smooth((p - 0.3) / 0.7)
                    pose.z[i] = (CGSize(width: 14 * e, height: 10 - 36 * e), opacity)
                }
            }
        }

        if let reaction, reaction >= 0, reaction < 1.6 {
            let p = reaction / 1.6
            pose.jumpY = CGFloat(keyframes(p, [(0, 0), (0.08, 0), (0.2, -30), (0.32, 0), (0.4, 0), (1, 0)]))
            pose.jumpScale = CGSize(width: keyframes(p, [(0, 1), (0.08, 1.08), (0.2, 0.95), (0.32, 1.06), (0.4, 1), (1, 1)]),
                                    height: keyframes(p, [(0, 1), (0.08, 0.9), (0.2, 1.06), (0.32, 0.94), (0.4, 1), (1, 1)]))
            if full {
                let delays = [0, 0.08, 0.15, 0.12, 0.1]
                for i in 0..<5 {
                    let q = (reaction - delays[i]) / 1.6
                    guard q >= 0 else { continue }
                    let scale = keyframes(q, [(0, 0.3), (0.1, 0.3), (0.25, 1), (0.6, 1.3), (1, 1.3)])
                    let dy = keyframes(q, [(0, 0), (0.25, 0), (0.6, -10), (1, -10)])
                    let opacity = keyframes(q, [(0, 0), (0.1, 0), (0.25, 1), (0.6, 0), (1, 0)])
                    pose.sparks[i] = (CGFloat(scale), CGFloat(dy), opacity)
                }
            }
        }
        return pose
    }

    private static func smooth(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Линейная или сглаженная интерполяция по ключевым кадрам (доля, значение).
    private static func keyframes(_ p: Double, _ frames: [(Double, Double)], ease: Bool = true) -> Double {
        guard let first = frames.first else { return 0 }
        if p <= first.0 { return first.1 }
        for (a, b) in zip(frames, frames.dropFirst()) where p <= b.0 {
            let t = b.0 > a.0 ? (p - a.0) / (b.0 - a.0) : 1
            return a.1 + (b.1 - a.1) * (ease ? smooth(t) : t)
        }
        return frames.last?.1 ?? 0
    }
}

// MARK: - Отрисовка

enum PetRenderer {
    static let designSize = CGSize(width: 200, height: 210)
    static let designOriginY: CGFloat = -22

    /// - Parameter shadow: цвет тени; на тёмном фоне чёрная тень не видна, поэтому там она светлая.
    static func draw(_ scene: PetScene, pose: PetPose, in context: inout GraphicsContext, size: CGSize, shadow: Color = .black) {
        let k = min(size.width / designSize.width, size.height / designSize.height)
        var root = context
        root.translateBy(x: (size.width - designSize.width * k) / 2, y: (size.height - designSize.height * k) / 2 - designOriginY * k)
        root.scaleBy(x: k, y: k)

        let g = PetScene.ground
        // Прыжок и дыхание вокруг точки на земле, затем масштаб стадии.
        let bodyTransform = CGAffineTransform(translationX: g.x, y: g.y)
            .translatedBy(x: 0, y: pose.jumpY)
            .scaledBy(x: pose.jumpScale.width, y: pose.jumpScale.height)
            .scaledBy(x: 1 + 0.025 * pose.breathe, y: 1 - 0.025 * pose.breathe)
            .scaledBy(x: scene.scale, y: scene.scale)
            .translatedBy(x: -g.x, y: -g.y)
        var body = root
        body.concatenate(bodyTransform)

        let pivot = PetScene.tailPivot
        let tailTransform = CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: pose.tailDegrees * .pi / 180).translatedBy(x: -pivot.x, y: -pivot.y)
        let e = scene.eyeCenter
        let eyesTransform = CGAffineTransform(translationX: e.x, y: e.y).scaledBy(x: 1, y: pose.blink).translatedBy(x: -e.x, y: -e.y)
        let shading = GraphicsContext.Shading.radialGradient(scene.furGradient, center: scene.gradientCenter,
                                                              startRadius: 0, endRadius: scene.gradientRadius)

        for element in scene.elements {
            var c = element.inBody ? body : root
            var opacity = element.opacity
            switch element.group {
            case .still: break
            case .tail: c.concatenate(tailTransform)
            case .eyes: c.concatenate(eyesTransform)
            case .z(let i):
                let z = pose.z[min(i, pose.z.count - 1)]
                c.translateBy(x: z.offset.width, y: z.offset.height)
                opacity *= z.opacity
            case .spark(let i):
                let sp = pose.sparks[min(i, pose.sparks.count - 1)]
                guard sp.opacity > 0.001 else { continue }
                let center = sparkCenter(element)
                c.translateBy(x: center.x, y: center.y + sp.dy)
                c.scaleBy(x: sp.scale, y: sp.scale)
                c.translateBy(x: -center.x, y: -center.y)
                opacity *= sp.opacity
            }
            c.opacity *= opacity
            switch element.content {
            case let .shape(path, fill, stroke):
                if let fill {
                    switch fill {
                    case .fur: c.fill(path, with: shading)
                    case .shadow: c.fill(path, with: .color(shadow))
                    case .color(let color): c.fill(path, with: .color(color))
                    }
                }
                if let stroke {
                    c.stroke(path, with: .color(stroke.color),
                             style: StrokeStyle(lineWidth: stroke.width, lineCap: stroke.cap, lineJoin: stroke.join))
                }
            case let .text(string, size, baseline, color):
                let text = c.resolve(Text(verbatim: string).font(.system(size: size, weight: .bold)).foregroundColor(color))
                let measured = text.measure(in: CGSize(width: 200, height: 200))
                let ascent = text.firstBaseline(in: measured)
                c.draw(text, at: CGPoint(x: baseline.x, y: baseline.y - ascent), anchor: .topLeading)
            }
        }
    }

    private static func sparkCenter(_ element: PetScene.Element) -> CGPoint {
        switch element.content {
        case .shape(let path, _, _): CGPoint(x: path.boundingRect.midX, y: path.boundingRect.midY)
        case .text(_, let size, let baseline, _): CGPoint(x: baseline.x + size * 0.4, y: baseline.y - size * 0.35)
        }
    }
}

// MARK: - Вид

/// Нарисованный питомец с анимацией по design/pets/README.md.
struct PetArtView: View {
    let style: PetStyle
    let stage: Int
    let mood: PetMood
    var size: CGFloat = 120
    /// Растёт при отметке привычки или кормлении: питомец подпрыгивает.
    var reaction: Int = 0
    var motion: PetMotion = .automatic

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var reactedAt: Date?

    private enum Level { case still, minimal, full }

    private var level: Level {
        if motion == .none || reduceMotion || lowPower { return .still }
        if motion == .minimal || size < 100 { return .minimal }
        return .full
    }

    var body: some View {
        let emotion = PetArt.emotion(for: mood, reacting: reactedAt != nil)
        let scene = PetScene.cached(style, stage: stage, emotion: emotion)
        let level = level
        Group {
            let shadow = colorScheme == .dark ? Color.white.opacity(0.55) : Color.black
            if level == .still {
                Self.canvas(scene, pose: .rest, shadow: shadow)
            } else {
                TimelineView(.animation(minimumInterval: level == .full ? 1.0 / 30 : 1.0 / 20,
                                        paused: !visible || scenePhase == .background)) { timeline in
                    let date = timeline.date
                    let pose = PetPose.at(date.timeIntervalSinceReferenceDate, emotion: emotion, full: level == .full,
                                          reaction: reactedAt.map { date.timeIntervalSince($0) })
                    Self.canvas(scene, pose: pose, shadow: shadow)
                }
                .drawingGroup()
            }
        }
        .saturation(mood == .lonely ? 0.45 : 1)
        .frame(width: size, height: size)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: reaction) { old, new in
            // Без анимации (виджет, «Уменьшение движения», энергосбережение) мордочку не меняем.
            guard new > old, level != .still else { return }
            reactedAt = Date()
        }
        .task(id: reactedAt) {
            guard let start = reactedAt else { return }
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            if reactedAt == start { reactedAt = nil }
        }
    }

    static func canvas(_ scene: PetScene, pose: PetPose, shadow: Color = .black) -> some View {
        Canvas { context, size in
            PetRenderer.draw(scene, pose: pose, in: &context, size: size, shadow: shadow)
        }
    }
}

// MARK: - Разбор SVG-путей

/// Мини-разбор атрибута d из SVG: M L H V C Q A Z (и строчные варианты).
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        let chars = Array(d.utf8)
        var i = 0
        var command: UInt8 = 0
        var current = CGPoint.zero
        var start = CGPoint.zero

        func skipSeparators() {
            while i < chars.count, chars[i] == 32 || chars[i] == 44 || chars[i] == 10 || chars[i] == 9 { i += 1 }
        }
        func isNumberStart(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 }
        func number() -> CGFloat {
            skipSeparators()
            let begin = i
            if i < chars.count, chars[i] == 45 || chars[i] == 43 { i += 1 }
            var seenDot = false
            while i < chars.count {
                let c = chars[i]
                if c >= 48 && c <= 57 { i += 1 } else if c == 46 && !seenDot { seenDot = true; i += 1 } else if c == 101 || c == 69 {
                    i += 1
                    if i < chars.count, chars[i] == 45 || chars[i] == 43 { i += 1 }
                } else { break }
            }
            return CGFloat(Double(String(decoding: chars[begin..<i], as: UTF8.self)) ?? 0)
        }
        /// Флаг дуги - один символ 0 или 1, поэтому «00» и «0 0» читаются одинаково.
        func flag() -> Bool {
            skipSeparators()
            guard i < chars.count else { return false }
            defer { i += 1 }
            return chars[i] == 49
        }
        func point(relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            skipSeparators()
            guard i < chars.count else { break }
            if !isNumberStart(chars[i]) {
                command = chars[i]
                i += 1
            } else if command == 77 {
                command = 76 // после M идут неявные L
            } else if command == 109 {
                command = 108
            }
            let relative = command >= 97
            switch command | 0x20 {
            case 109: // m
                current = point(relative: relative)
                start = current
                path.move(to: current)
            case 108: // l
                current = point(relative: relative)
                path.addLine(to: current)
            case 104: // h
                let x = number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case 118: // v
                let y = number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case 99: // c
                let c1 = point(relative: relative), c2 = point(relative: relative), end = point(relative: relative)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
            case 113: // q
                let c1 = point(relative: relative), end = point(relative: relative)
                path.addQuadCurve(to: end, control: c1)
                current = end
            case 97: // a
                let rx = number(), ry = number(), rotation = number(), large = flag(), sweep = flag()
                let end = point(relative: relative)
                addArc(&path, from: current, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep, to: end)
                current = end
            case 122: // z
                path.closeSubpath()
                current = start
                while i < chars.count, isNumberStart(chars[i]) { i += 1 }
            default:
                return path
            }
        }
        return path
    }

    /// Дуга SVG (эллипс по концам) кривыми Безье, по SVG 1.1 F.6.5.
    static func addArc(_ path: inout Path, from p0: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat,
                       large: Bool, sweep: Bool, to p1: CGPoint) {
        guard p0 != p1 else { return }
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = (large != sweep ? 1 : -1) * sqrt(max(0, num / den))
        let cxp = coef * rx * y1 / ry, cyp = -coef * ry * x1 / rx
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
        let ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry, vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry
        let theta = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2) - 0.001)))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * x * cosP - ry * y * sinP, y: cy + rx * x * sinP + ry * y * cosP)
        }
        var a = theta
        for s in 0..<segments {
            let b = a + step
            let c1 = map(cos(a) - k * sin(a), sin(a) + k * cos(a))
            let c2 = map(cos(b) + k * sin(b), sin(b) - k * cos(b))
            let end = s == segments - 1 ? p1 : map(cos(b), sin(b))
            path.addCurve(to: end, control1: c1, control2: c2)
            a = b
        }
    }
}

private extension Color {
    init(petHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}
