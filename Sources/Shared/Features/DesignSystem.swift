import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import PlateCore

enum PlateAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}


// MARK: - Palette: cream, ink and bright food colours

extension Color {
    /// A colour that follows light and dark appearance.
    static func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }
    /// The page: warm cream by day, deep ube-black by night.
    static let cream = adaptive((1.0, 0.957, 0.894), (0.086, 0.071, 0.122))
    /// Sticker paper: white by day, plum by night.
    static let surface = adaptive((1.0, 1.0, 1.0), (0.141, 0.114, 0.192))
    /// Outlines and text: ink by day, cream by night.
    static let ink = adaptive((0.118, 0.102, 0.180), (1.0, 0.957, 0.894))
    /// Text that sits on bright fills, in both appearances.
    static let inkFixed = Color(red: 0.118, green: 0.102, blue: 0.180)
    static let chili = Color(red: 1.0, green: 0.39, blue: 0.18)
    static let butter = Color(red: 1.0, green: 0.765, blue: 0.2)
    static let matcha = Color(red: 0.42, green: 0.776, blue: 0.333)
    static let ube = Color(red: 0.557, green: 0.427, blue: 0.949)
    static let bubble = Color(red: 1.0, green: 0.478, blue: 0.698)
    static let sky = Color(red: 0.345, green: 0.776, blue: 1.0)
    static let overRed = Color(red: 1.0, green: 0.25, blue: 0.4)
    /// Roles. Protein is chili (also the accent), carbs butter, fat matcha.
    static let plateAccent = chili
    static let plateCarb = butter
    static let plateFat = matcha
    // Older names, kept so every screen picks up the new palette.
    static let saffron = chili
    static let terracotta = butter
    static let celadon = matcha
    static let glazeRed = overRed
    static let porcelain = cream
    static let glazeCharcoal = ink
    static let glazeSlate = surface
    static let glazeRim = surface
}
extension DayStatus {
    var color: Color { switch self { case .calm: Color.ube; case .almost: .butter; case .hit: .matcha; case .over: .overRed } }
}

// MARK: - Surfaces

/// A sticker card: white paper, a bold ink outline. Flat, no shadows.
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ink, lineWidth: 2))
        }
    }
}
extension View { func plateCard() -> some View { modifier(GlassCard()) } }

/// The page: cream paper with food stickers and doodles drifting and swaying.
struct PlateBackground: View {
    let status: DayStatus
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.plateMotionActive) private var motionActive
    private struct Doodle { let symbol: String; let emoji: Bool; let x: Double; let y: Double; let size: CGFloat; let color: Int; let speed: Double; let phase: Double }
    private static let doodles: [Doodle] = [
        Doodle(symbol: "🍓", emoji: true, x: 0.10, y: 0.12, size: 30, color: 0, speed: 0.6, phase: 0.0),
        Doodle(symbol: "sparkle", emoji: false, x: 0.86, y: 0.07, size: 22, color: 3, speed: 0.9, phase: 1.2),
        Doodle(symbol: "🥑", emoji: true, x: 0.90, y: 0.33, size: 32, color: 0, speed: 0.5, phase: 2.1),
        Doodle(symbol: "star.fill", emoji: false, x: 0.06, y: 0.40, size: 16, color: 1, speed: 1.1, phase: 0.7),
        Doodle(symbol: "🍜", emoji: true, x: 0.14, y: 0.68, size: 30, color: 0, speed: 0.45, phase: 3.3),
        Doodle(symbol: "heart.fill", emoji: false, x: 0.92, y: 0.60, size: 18, color: 4, speed: 0.8, phase: 2.8),
        Doodle(symbol: "🍙", emoji: true, x: 0.80, y: 0.88, size: 30, color: 0, speed: 0.55, phase: 1.7),
        Doodle(symbol: "scribble.variable", emoji: false, x: 0.32, y: 0.94, size: 26, color: 2, speed: 0.7, phase: 0.4),
        Doodle(symbol: "🌶️", emoji: true, x: 0.52, y: 0.03, size: 24, color: 0, speed: 0.65, phase: 4.0),
        Doodle(symbol: "circle.dotted", emoji: false, x: 0.60, y: 0.52, size: 40, color: 3, speed: 0.35, phase: 5.1)
    ]
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let palette: [Color] = [.chili, .butter, .matcha, status.color, .bubble]
            ZStack {
                Color.cream
                TimelineView(.animation(minimumInterval: 1 / 24, paused: reduced || !motionActive)) { timeline in
                    let t = reduced ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(Self.doodles.indices, id: \.self) { index in
                            let d = Self.doodles[index]
                            doodle(d, color: palette[d.color])
                                .rotationEffect(.degrees(sin(t * d.speed + d.phase) * 14))
                                .position(x: size.width * d.x + cos(t * d.speed * 0.6 + d.phase) * 12, y: size.height * d.y + sin(t * d.speed * 0.8 + d.phase) * 16)
                        }
                    }
                }.opacity(0.5)
            }.frame(width: size.width, height: size.height).clipped()
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
    @ViewBuilder private func doodle(_ d: Doodle, color: Color) -> some View {
        if d.emoji { Text(d.symbol).font(.system(size: d.size)) }
        else { Image(systemName: d.symbol).font(.system(size: d.size, weight: .black)).foregroundStyle(color) }
    }
}

// MARK: - Plato, the plate buddy

/// Plato's face. It bobs, blinks, looks where you drag, chomps when you log food and changes mood with your day.
struct PlateBuddy: View {
    let mood: DayStatus
    var size: CGFloat = 110
    var look: CGSize = .zero
    var chomp: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.plateMotionActive) private var motionActive
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced || !motionActive)) { timeline in
            let t = reduced ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let blink = !reduced && t.truncatingRemainder(dividingBy: 3.7) < 0.13
            face(blink: blink).offset(y: reduced ? 0 : sin(t * 2.2) * size * 0.025)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    private func face(blink: Bool) -> some View {
        let px = max(-1, min(1, look.width / 60)) * size * 0.035
        let py = max(-1, min(1, look.height / 60)) * size * 0.035
        return ZStack {
            HStack(spacing: size * 0.2) { eye(blink: blink); eye(blink: blink) }
                .offset(x: px, y: -size * 0.09 + py)
            HStack(spacing: size * 0.42) {
                Ellipse().fill(Color.bubble.opacity(0.75)).frame(width: size * 0.15, height: size * 0.085)
                Ellipse().fill(Color.bubble.opacity(0.75)).frame(width: size * 0.15, height: size * 0.085)
            }.offset(y: size * 0.06)
            mouth.offset(x: px * 0.5, y: size * 0.17)
                .keyframeAnimator(initialValue: 1.0, trigger: chomp) { view, scale in
                    view.scaleEffect(x: 1, y: scale)
                } keyframes: { _ in
                    SpringKeyframe(2.0, duration: 0.12)
                    SpringKeyframe(0.4, duration: 0.12)
                    SpringKeyframe(1.7, duration: 0.12)
                    SpringKeyframe(1.0, duration: 0.3)
                }
        }
    }
    @ViewBuilder private func eye(blink: Bool) -> some View {
        switch mood {
        case .hit:
            Image(systemName: "star.fill").font(.system(size: size * 0.15, weight: .black)).foregroundStyle(Color.butter)
                .overlay(Image(systemName: "star").font(.system(size: size * 0.15, weight: .black)).foregroundStyle(Color.inkFixed))
        case .over:
            Image(systemName: "xmark").font(.system(size: size * 0.11, weight: .black)).foregroundStyle(Color.inkFixed)
        default:
            Capsule().fill(Color.inkFixed).frame(width: size * 0.105, height: blink ? size * 0.02 : size * 0.15)
                .overlay(alignment: .topTrailing) { if !blink { Circle().fill(.white).frame(width: size * 0.035).offset(x: -size * 0.012, y: size * 0.02) } }
        }
    }
    @ViewBuilder private var mouth: some View {
        let line = StrokeStyle(lineWidth: size * 0.04, lineCap: .round)
        switch mood {
        case .calm:
            Circle().trim(from: 0.05, to: 0.45).stroke(Color.inkFixed, style: line).frame(width: size * 0.26, height: size * 0.26).offset(y: -size * 0.1)
        case .almost:
            Circle().stroke(Color.inkFixed, style: line).frame(width: size * 0.1, height: size * 0.1)
        case .hit:
            BottomHalf().fill(Color.inkFixed).frame(width: size * 0.3, height: size * 0.15)
                .overlay(alignment: .bottom) { Ellipse().fill(Color.bubble).frame(width: size * 0.13, height: size * 0.06).offset(y: -size * 0.015) }
        case .over:
            Squiggle().stroke(Color.inkFixed, style: line).frame(width: size * 0.28, height: size * 0.07)
        }
    }
}
private struct BottomHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY), radius: rect.width / 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}
private struct Squiggle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 24
        for step in 0...steps {
            let x = rect.minX + rect.width * Double(step) / Double(steps)
            let y = rect.midY + sin(Double(step) / Double(steps) * .pi * 4) * rect.height / 2
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

// MARK: - Stickers

/// An emoji sticker that sways on its own, pops when tapped, and can be dragged and flung back with a bounce.
struct WobbleSticker: View {
    let emoji: String
    var size: CGFloat = 28
    var draggable = false
    @State private var sway = false
    @State private var pops = 0
    @State private var drag = CGSize.zero
    @GestureState private var held = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let sticker = Text(emoji).font(.system(size: size))
            .padding(size * 0.2)
            .background(Circle().fill(Color.surface))
            .overlay(Circle().strokeBorder(Color.ink, lineWidth: 2))
            .rotationEffect(.degrees(reduced ? 0 : sway ? 10 : -10))
            .keyframeAnimator(initialValue: 1.0, trigger: pops) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
                SpringKeyframe(1.4, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
            .scaleEffect(held ? 1.25 : 1)
            .offset(drag)
            .animation(reduced ? nil : .spring(response: 0.3, dampingFraction: 0.5), value: held)
            .onTapGesture { pops += 1 }
            .sensoryFeedback(.impact(weight: .light), trigger: pops)
            .onAppear {
                guard !reduced else { return }
                withAnimation(.easeInOut(duration: Double(emoji.unicodeScalars.first?.value ?? 7).truncatingRemainder(dividingBy: 0.7) + 1.1).repeatForever(autoreverses: true)) { sway = true }
            }
            .accessibilityHidden(true)
        if draggable {
            sticker.gesture(DragGesture()
                .updating($held) { _, state, _ in state = true }
                .onChanged { drag = $0.translation }
                .onEnded { _ in withAnimation(reduced ? nil : .spring(response: 0.55, dampingFraction: 0.32)) { drag = .zero }; pops += 1 })
        } else {
            sticker
        }
    }
}
/// A row of draggable food stickers.
struct StickerShelf: View {
    var emojis = ["🍳", "🥑", "🍗", "🍚", "🧋"]
    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                WobbleSticker(emoji: emoji, size: 24, draggable: true).zIndex(Double(emojis.count - index))
            }
        }
    }
}

// MARK: - Small pieces

/// Plate's mark: a little plate face.
struct PlateMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(Color.chili)
            Circle().strokeBorder(Color.ink, lineWidth: max(1.5, size * 0.05))
            Circle().strokeBorder(Color.inkFixed.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 3])).padding(size * 0.12)
            HStack(spacing: size * 0.16) {
                Capsule().fill(Color.inkFixed).frame(width: size * 0.09, height: size * 0.14)
                Capsule().fill(Color.inkFixed).frame(width: size * 0.09, height: size * 0.14)
            }.offset(y: -size * 0.06)
            Circle().trim(from: 0.05, to: 0.45).stroke(Color.inkFixed, style: StrokeStyle(lineWidth: max(1.2, size * 0.045), lineCap: .round))
                .frame(width: size * 0.3, height: size * 0.3).offset(y: size * 0.02)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct MacroRing: View {
    let name: String
    let value, target: Double
    let color: Color
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.ink.opacity(0.08), style: StrokeStyle(lineWidth: compact ? 7 : 10))
                Circle().trim(from: 0, to: min(1, max(0, value/max(1,target)))).stroke(color, style: StrokeStyle(lineWidth: compact ? 7 : 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.6), value: value)
                Circle().strokeBorder(Color.ink, lineWidth: 1.5)
                VStack(spacing: 1) {
                    Text(value, format: .number.precision(.fractionLength(0))).font(.system(compact ? .headline : .title2, design: .rounded, weight: .black)).contentTransition(.numericText())
                    if !compact { Text("of \(Int(target)) g").font(.caption2).foregroundStyle(.secondary) }
                }
            }.frame(width: compact ? 58 : 88, height: compact ? 58 : 88)
            Text(name).font(.caption.weight(.heavy)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(name), \(Int(value)) of \(Int(target)) grams")
    }
}
struct CaptureButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "camera.fill").symbolEffect(.breathe, isActive: !reduced)
                Text("Log a meal").fontWeight(.black)
            }
            .font(.system(.subheadline, design: .rounded)).foregroundStyle(Color.inkFixed)
            .padding(.horizontal, 24).padding(.vertical, 15)
            .background(Capsule().fill(Color.chili))
            .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2.5))
        }.buttonStyle(PlatePress())
            .accessibilityHint("Take a photo, read a label, or enter food manually")
    }
}
struct FoodPhoto: View {
    let path: String?
    @Environment(PlateModel.self) private var model
    @State private var data: Data?
    var body: some View {
        ZStack {
            Rectangle().fill(Color.butter.opacity(0.25))
            if let data, let image = platformImage(data) { image.resizable().scaledToFill() }
            else { Text("🍽️").font(.system(size: 30)) }
        }.task(id: path) { data = nil; if let path { data = await PhotoStore.shared.load(path: path, sync: model.sync) } }
    }
}
func platformImage(_ data: Data) -> Image? {
    #if os(iOS)
    guard let image = UIImage(data: data) else { return nil }; return Image(uiImage: image)
    #else
    guard let image = NSImage(data: data) else { return nil }; return Image(nsImage: image)
    #endif
}
/// A tilted sticker label above each section.
struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .black, design: .rounded)).tracking(1.2)
            .foregroundStyle(Color.inkFixed).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.butter, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 1.5))
            .rotationEffect(.degrees(-2))
    }
}
/// Buttons squish when pressed and spring back with a little bounce.
struct PlatePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlatePressContent(content: configuration.label, pressed: configuration.isPressed)
    }
}
private struct PlatePressContent<Content: View>: View {
    let content: Content
    let pressed: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        content
            .scaleEffect(x: reduced ? 1 : pressed ? 1.04 : hovering ? 1.02 : 1, y: reduced ? 1 : pressed ? 0.9 : hovering ? 1.02 : 1)
            .rotationEffect(.degrees(hovering && !pressed && !reduced ? -1.5 : 0))
            .animation(reduced ? nil : .spring(response: 0.28, dampingFraction: 0.45), value: pressed)
            .animation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.55), value: hovering)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, isPressed in isPressed }
            .onHover { hovering = $0 }
    }
}
/// A round sticker holding a glyph.
struct PlateIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 42
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.4, weight: .black)).foregroundStyle(Color.inkFixed)
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(Color.ink, lineWidth: 2))
            .rotationEffect(.degrees(reduced ? 0 : hovering ? 14 : -6))
            .scaleEffect(hovering && !reduced ? 1.08 : 1)
            .animation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.45), value: hovering)
            .onHover { hovering = $0 }.accessibilityHidden(true)
    }
}
/// The capture-screen illustration: Plato waiting on a plate, with cutlery that sways. Tap to spin.
struct PlateSculpture: View {
    @State private var spins = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { withAnimation(reduced ? nil : .spring(response: 1, dampingFraction: 0.5)) { spins += 1 } } label: {
            HStack(spacing: 14) {
                WobbleSticker(emoji: "🍴", size: 26)
                ZStack {
                    Circle().fill(Color.surface)
                    Circle().strokeBorder(Color.ink, lineWidth: 2.5)
                    Circle().strokeBorder(Color.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6])).padding(14)
                    Circle().fill(Color.chili).padding(28).overlay(Circle().strokeBorder(Color.ink, lineWidth: 2).padding(28))
                    PlateBuddy(mood: .calm, size: 72)
                }.frame(width: 140, height: 140).rotationEffect(.degrees(spins * 360))
                WobbleSticker(emoji: "🥄", size: 26)
            }
        }.buttonStyle(PlatePress())
            .accessibilityLabel("Spin the plate").accessibilityHint("Decoration only; it doesn't change your food log")
    }
}
/// Sticker pills with a bouncy highlight that slides to your choice.
struct PlateSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, title in
                Button { withAnimation(reduced ? nil : .spring(response: 0.38, dampingFraction: 0.6)) { selection = index } } label: {
                    Text(title).font(.system(.subheadline, design: .rounded, weight: selection == index ? .black : .semibold))
                        .foregroundStyle(selection == index ? Color.inkFixed : Color.ink.opacity(0.6))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background {
                            if selection == index {
                                Capsule().fill(Color.butter).overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
                                    .matchedGeometryEffect(id: "segment", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }.buttonStyle(PlatePress()).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(4).background(Capsule().fill(Color.surface)).overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
            .sensoryFeedback(.selection, trigger: selection)
    }
}
struct PlatePageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    private var emoji: String {
        let list = ["🍳", "🥑", "🍜", "🍓", "🌶️", "🍙", "🧋", "🥗", "🍩"]
        return list[title.unicodeScalars.reduce(0) { $0 + Int($1.value) } % list.count]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) { SectionEyebrow(text: eyebrow); WobbleSticker(emoji: emoji, size: 18, draggable: true) }
            Text(title).font(.system(size: 38, weight: .black, design: .rounded)).tracking(-1).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(.subheadline, design: .rounded, weight: .medium)).foregroundStyle(Color.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The plate

/// Today as a plate seen from above, with Plato in the middle. Each meal is laid down clockwise as wedges of protein, carbs and fat;
/// a full plate is the target, and anything past it spills onto the rim. Dots on the rim mark when you ate; the chili pin is now.
struct PlateDial: View {
    let meals: [Meal]
    let target: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.plateMotionActive) private var motionActive
    @State private var reach: Double = 0
    @State private var showRemaining = false
    @State private var tilt = CGSize.zero
    @State private var wobble = false
    @State private var orbit = false
    @State private var chomp = 0
    @State private var boing = 0
    private let side: CGFloat = 236
    private let bandWidth: CGFloat = 34
    private struct Slice: Identifiable { let id: String; let start: Double; let end: Double; let color: Color }
    private var eaten: Double { meals.reduce(0) { $0 + $1.total.calories } }
    private var mood: DayStatus { DailyGuidance(eaten: .init(calories: eaten), target: Targets(nutrients: .init(calories: target))).state }
    private var slices: [Slice] {
        var cursor = 0.0
        var result: [Slice] = []
        let scale = 1 / max(1, target)
        for meal in meals.sorted(by: { $0.timestamp < $1.timestamp }) {
            let total = meal.total
            let span = total.calories * scale
            guard span > 0 else { continue }
            let parts: [(key: String, kcal: Double, color: Color)] = [("p", total.protein * 4, .chili), ("c", total.carbs * 4, .butter), ("f", total.fat * 9, .matcha)]
            let sum = parts.reduce(0) { $0 + $1.kcal }
            let gap = min(0.008, span * 0.2)
            var start = cursor
            if sum <= 0 {
                result.append(Slice(id: meal.id, start: start, end: start + span - gap, color: .sky))
            } else {
                for part in parts where part.kcal > 0 {
                    let width = (span - gap) * part.kcal / sum
                    result.append(Slice(id: meal.id + part.key, start: start, end: start + width, color: part.color))
                    start += width
                }
            }
            cursor += span
        }
        return result
    }
    private func dayFraction(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60) / 24
    }
    private func dominant(_ meal: Meal) -> Color {
        let t = meal.total
        let p = t.protein * 4, c = t.carbs * 4, f = t.fat * 9
        return p >= c && p >= f ? .chili : c >= f ? .butter : .matcha
    }
    var body: some View {
        Button {
            withAnimation(reduced ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { showRemaining.toggle() }
            boing += 1
        } label: {
            ZStack {
                orbiters
                ZStack { plate; rim; band; well }
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(reduced ? 0 : wobble ? 2.5 : -2.5))
                    .keyframeAnimator(initialValue: 1.0, trigger: boing) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
                        SpringKeyframe(0.93, duration: 0.1)
                        SpringKeyframe(1.06, duration: 0.18)
                        SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                    }
                bubble.offset(x: side * 0.34, y: -side * 0.5)
            }
            .frame(width: side + 60, height: side + 70)
            .rotation3DEffect(.degrees(reduced ? 0 : Double(tilt.width / 8)), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(reduced ? 0 : Double(-tilt.height / 8)), axis: (x: 1, y: 0, z: 0))
        }.buttonStyle(.plain)
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { tilt = CGSize(width: max(-70, min(70, $0.translation.width)), height: max(-70, min(70, $0.translation.height))) }.onEnded { _ in withAnimation(reduced ? nil : .spring(response: 0.6, dampingFraction: 0.4)) { tilt = .zero } })
            .sensoryFeedback(.impact(weight: .medium), trigger: boing)
            .sensoryFeedback(.success, trigger: chomp)
            .onAppear {
                guard !reduced else { reach = eaten / max(1, target); return }
                withAnimation(.spring(response: 1.6, dampingFraction: 0.75).delay(0.25)) { reach = eaten / max(1, target) }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { wobble = true }
                withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) { orbit = true }
            }
            .onChange(of: eaten) { old, new in
                if new > old { chomp += 1 }
                withAnimation(reduced ? nil : .spring(response: 1.1, dampingFraction: 0.65)) { reach = new / max(1, target) }
            }
            .onChange(of: target) { _, newValue in withAnimation(reduced ? nil : .spring(response: 1, dampingFraction: 0.7)) { reach = eaten / max(1, newValue) } }
            .accessibilityLabel("\(Int(eaten)) of \(Int(target)) calories across \(meals.count) \(meals.count == 1 ? "meal" : "meals"). Tap to switch between eaten and remaining.")
    }
    /// Food stickers circling the plate.
    private var orbiters: some View {
        ZStack {
            ForEach(Array(["🍳", "🥑", "🍗", "🍚"].enumerated()), id: \.offset) { index, emoji in
                Text(emoji).font(.system(size: 22))
                    .rotationEffect(.degrees(orbit ? -360 : 0))
                    .offset(y: -side * 0.6)
                    .rotationEffect(.degrees(Double(index) * 90 + 20))
            }
        }.rotationEffect(.degrees(orbit ? 360 : 0)).accessibilityHidden(true)
    }
    private var plate: some View {
        ZStack {
            Circle().fill(Color.surface)
            Circle().strokeBorder(Color.ink, lineWidth: 3)
            Circle().strokeBorder(Color.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 7])).padding(side * 0.1)
        }
    }
    private var rim: some View {
        let radius = side * 0.445
        let now = dayFraction(.now)
        return ZStack {
            ForEach(0..<24, id: \.self) { hour in
                Capsule().fill(Color.ink.opacity(hour % 6 == 0 ? 0.8 : 0.25))
                    .frame(width: hour % 6 == 0 ? 2.5 : 1.5, height: hour % 6 == 0 ? 9 : 5)
                    .offset(y: -radius).rotationEffect(.degrees(Double(hour) / 24 * 360))
            }
            ForEach(meals) { meal in
                Circle().fill(dominant(meal)).frame(width: 11, height: 11).overlay(Circle().strokeBorder(Color.ink, lineWidth: 1.5))
                    .offset(y: -radius).rotationEffect(.degrees(dayFraction(meal.timestamp) * 360))
                    .transition(.scale(scale: 0.1).combined(with: .opacity))
            }
            Image(systemName: "mappin").font(.system(size: 15, weight: .black)).foregroundStyle(Color.chili)
                .offset(y: -radius - 4).rotationEffect(.degrees(now * 360))
        }
    }
    private var band: some View {
        let diameter = side * 0.6
        return ZStack {
            Circle().stroke(Color.ink.opacity(0.06), lineWidth: bandWidth).frame(width: diameter, height: diameter)
            ForEach(slices) { slice in
                let from = min(slice.start, 1)
                Circle().trim(from: from, to: max(from, min(slice.end, reach, 1)))
                    .stroke(slice.color, style: StrokeStyle(lineWidth: bandWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90)).frame(width: diameter, height: diameter)
            }
            Circle().stroke(Color.ink, lineWidth: 2).frame(width: diameter + bandWidth, height: diameter + bandWidth)
            Circle().stroke(Color.ink, lineWidth: 2).frame(width: diameter - bandWidth, height: diameter - bandWidth)
            // Past the target, food spills onto the rim.
            Circle().trim(from: 0, to: min(1, max(0, reach - 1)))
                .stroke(Color.overRed, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: side * 0.8, height: side * 0.8)
        }
    }
    private var well: some View {
        ZStack {
            Circle().fill(tint.opacity(0.9)).frame(width: side * 0.44, height: side * 0.44)
                .overlay(Circle().strokeBorder(Color.ink, lineWidth: 2.5))
            PlateBuddy(mood: mood, size: side * 0.4, look: tilt, chomp: chomp)
        }
    }
    /// Plato's speech bubble with today's number.
    private var bubble: some View {
        let value = reach * max(1, target)
        let remaining = target - value
        return VStack(alignment: .leading, spacing: 0) {
            Text(Int((showRemaining ? abs(remaining) : value).rounded()), format: .number)
                .font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Color.ink)
                .contentTransition(.numericText(value: value)).lineLimit(1).minimumScaleFactor(0.6)
            Text(showRemaining ? (remaining < 0 ? "kcal over!" : "kcal left") : "kcal eaten").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Color.ink.opacity(0.65))
            Text("of \(Int(target))").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Color.ink.opacity(0.45))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.ink, lineWidth: 2))
        .overlay(alignment: .bottomLeading) {
            Rectangle().fill(Color.surface).frame(width: 12, height: 12)
                .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                .rotationEffect(.degrees(45)).offset(x: 16, y: 6).mask(Rectangle().offset(y: 8))
        }
        .rotationEffect(.degrees(reduced ? 0 : wobble ? 4 : -2))
        .frame(width: 112)
    }
}

// MARK: - Macro tiles

/// A bar with candy stripes that keep sliding while the app is open.
struct WiggleBar: View {
    let progress: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.plateMotionActive) private var motionActive
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ink.opacity(0.07))
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced || !motionActive)) { timeline in
                    let shift = reduced ? 0 : (timeline.date.timeIntervalSinceReferenceDate * 16).truncatingRemainder(dividingBy: 12)
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(tint))
                        var x = CGFloat(shift) - size.height - 12
                        while x < size.width {
                            var stripe = Path()
                            stripe.move(to: CGPoint(x: x, y: size.height))
                            stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                            stripe.addLine(to: CGPoint(x: x + size.height + 5, y: 0))
                            stripe.addLine(to: CGPoint(x: x + 5, y: size.height))
                            stripe.closeSubpath()
                            context.fill(stripe, with: .color(.white.opacity(0.3)))
                            x += 12
                        }
                    }
                }.frame(width: width).clipShape(Capsule())
                Capsule().strokeBorder(Color.ink, lineWidth: 1.5)
            }
        }
    }
}
struct NutrientTile: View {
    let name: String
    let symbol: String
    let value: Double
    let target: Double
    let tint: Color
    @State private var expanded = false
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { withAnimation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.6)) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 13, weight: .black)).foregroundStyle(Color.inkFixed)
                        .frame(width: 30, height: 30).background(Circle().fill(tint)).overlay(Circle().strokeBorder(Color.ink, lineWidth: 2))
                        .rotationEffect(.degrees(expanded ? 14 : -8))
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "minus" : "plus").font(.caption2.weight(.black)).foregroundStyle(Color.ink.opacity(0.5))
                }
                Text(name.uppercased()).font(.system(size: 10, weight: .black, design: .rounded)).tracking(0.8).foregroundStyle(Color.ink.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Int(value), format: .number).font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Color.ink).contentTransition(.numericText())
                    Text("g").font(.caption.weight(.bold)).foregroundStyle(Color.ink.opacity(0.5))
                }
                WiggleBar(progress: grown || reduced ? value / max(1, target) : 0, tint: tint).frame(height: 11)
                    .onAppear { withAnimation(reduced ? nil : .spring(response: 1.1, dampingFraction: 0.6).delay(0.35)) { grown = true } }
                    .animation(reduced ? nil : .spring(response: 0.8, dampingFraction: 0.6), value: value)
                if expanded { Text("\(Int(max(0, target - value))) g left\nTarget \(Int(target)) g").font(.caption2.weight(.semibold)).foregroundStyle(Color.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true).transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity)) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.surface))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.ink, lineWidth: 2))
        }.buttonStyle(PlatePress()).accessibilityLabel("\(name), \(Int(value)) of \(Int(target)) grams").accessibilityHint("Show remaining grams")
    }
}

struct PlateCalendar: View {
    @Binding var selection: Date
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var calendar: Calendar { .current }
    private var leading: Int { (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7 }
    private var count: Int { calendar.range(of: .day, in: .month, for: month)?.count ?? 30 }
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36).background(Color.plateAccent.opacity(0.08), in: .circle) }.accessibilityLabel("Previous month")
                Spacer(minLength: 2)
                Text(month, format: .dateTime.month(.wide).year()).font(.system(.headline, design: .rounded)).contentTransition(.numericText())
                Spacer(minLength: 2)
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36).background(Color.plateAccent.opacity(0.08), in: .circle) }.accessibilityLabel("Next month").disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption2.bold()).foregroundStyle(.secondary).frame(height: 25)
                }
                ForEach(0..<(leading+count), id: \.self) { cell in
                    if cell < leading { Color.clear.frame(height: 36) }
                    else {
                        let day = calendar.date(byAdding: .day, value: cell-leading, to: month) ?? month
                        let active = calendar.isDate(day, inSameDayAs: selection)
                        Button { withAnimation(reduced ? nil : .smooth) { selection = day } } label: {
                            Text("\(cell-leading+1)").font(.system(.subheadline, design: .rounded, weight: active ? .bold : .medium)).frame(maxWidth: .infinity).frame(height: 36).background(active ? Color.plateAccent.opacity(0.25) : .clear, in: .circle).overlay(Circle().stroke(calendar.isDateInToday(day) ? Color.plateAccent : .clear))
                        }.disabled(day > Date.now).accessibilityLabel(day.formatted(date: .complete, time: .omitted)).accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
            }
        }.buttonStyle(PlatePress()).foregroundStyle(.primary).padding(22).plateCard()
            .onAppear { month = calendar.dateInterval(of: .month, for: selection)?.start ?? month }
            .onChange(of: selection) { _, value in month = calendar.dateInterval(of: .month, for: value)?.start ?? month }
    }
    private func move(_ amount: Int) {
        withAnimation(reduced ? nil : .smooth) { month = calendar.date(byAdding: .month, value: amount, to: month) ?? month }
    }
}

private struct PlateMotionActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var plateMotionActive: Bool {
        get { self[PlateMotionActiveKey.self] }
        set { self[PlateMotionActiveKey.self] = newValue }
    }
}
/// Cards pop in one after another with a little tilt and bounce.
private struct PlateEntrance: ViewModifier {
    let order: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        content.opacity(appeared || reduced ? 1 : 0)
            .scaleEffect(appeared || reduced ? 1 : 0.88)
            .rotationEffect(.degrees(appeared || reduced ? 0 : (order.isMultiple(of: 2) ? -3 : 3)))
            .offset(y: appeared || reduced ? 0 : 28)
            .onAppear { withAnimation(reduced ? nil : .spring(response: 0.6, dampingFraction: 0.62).delay(Double(min(order, 6)) * 0.07)) { appeared = true } }
    }
}
extension View { func plateEntrance(_ order: Int = 0) -> some View { modifier(PlateEntrance(order: order)) } }

/// Emoji confetti that bursts out when you log food or hit your target.
struct SparkBurst: View {
    let trigger: Int
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        ZStack { if trigger > 0 && !reduced { ConfettiPop().id(trigger) } }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct ConfettiPop: View {
    @State private var fired = false
    @State private var faded = false
    private static let pieces = ["✨", "🎉", "⭐️", "💥", "🍓", "🥑", "💚", "🔥"]
    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { index in
                let angle = Double(index) / 18 * 2 * .pi
                let distance: Double = index.isMultiple(of: 2) ? 160 : 115
                Text(Self.pieces[index % Self.pieces.count]).font(.system(size: index % 3 == 0 ? 28 : 18))
                    .scaleEffect(fired ? 1 : 0.2)
                    .rotationEffect(.degrees(fired ? Double(index * 47 % 360) : 0))
                    .offset(x: fired ? cos(angle) * distance : 0, y: fired ? sin(angle) * distance + 50 : 0)
                    .opacity(faded ? 0 : 1)
            }
        }.onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.6)) { fired = true }
            withAnimation(.easeIn(duration: 0.6).delay(0.75)) { faded = true }
        }
    }
}

// MARK: - The breakfast crew

/// Three little characters for the top of Today: an avocado, a fried egg and a slice of toast.
/// They bob, sway and blink out of step; tap one to squish it, or drag it and let it spring back.
struct FruitTrio: View {
    var size: CGFloat = 80
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.plateMotionActive) private var motionActive
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced || !motionActive)) { timeline in
            let t = reduced ? 0 : timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: size * 0.06) {
                FoodBuddy(kind: .avocado, size: size, t: t, phase: 0).rotationEffect(.degrees(-10))
                FoodBuddy(kind: .egg, size: size, t: t, phase: 1.3).rotationEffect(.degrees(4)).offset(y: -size * 0.06)
                FoodBuddy(kind: .toast, size: size, t: t, phase: 2.6).rotationEffect(.degrees(12))
            }
        }.accessibilityHidden(true)
    }
}
private struct FoodBuddy: View {
    enum Kind { case avocado, egg, toast }
    let kind: Kind
    let size: CGFloat
    let t: Double
    let phase: Double
    @State private var pops = 0
    @State private var drag = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let blink = t > 0 && (t + phase).truncatingRemainder(dividingBy: 4.1) < 0.14
        character(blink: blink)
            .rotationEffect(.degrees(sin(t * 1.3 + phase) * 5))
            .offset(y: sin(t * 2 + phase) * size * 0.045)
            .keyframeAnimator(initialValue: 1.0, trigger: pops) { view, stretch in
                view.scaleEffect(x: 2 - stretch, y: stretch, anchor: .bottom)
            } keyframes: { _ in
                SpringKeyframe(0.72, duration: 0.1)
                SpringKeyframe(1.18, duration: 0.16)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
            .offset(drag)
            .gesture(DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { _ in
                    withAnimation(reduced ? nil : .spring(response: 0.55, dampingFraction: 0.32)) { drag = .zero }
                    pops += 1
                })
            .onTapGesture { pops += 1 }
            .sensoryFeedback(.impact(weight: .light), trigger: pops)
    }
    @ViewBuilder private func character(blink: Bool) -> some View {
        let line = max(2, size * 0.035)
        switch kind {
        case .avocado:
            ZStack {
                Ellipse().fill(Color(red: 0.26, green: 0.48, blue: 0.2)).frame(width: size * 0.8, height: size)
                Ellipse().fill(Color(red: 0.73, green: 0.87, blue: 0.42)).frame(width: size * 0.62, height: size * 0.82)
                Circle().fill(Color(red: 0.55, green: 0.32, blue: 0.2)).frame(width: size * 0.32, height: size * 0.32)
                    .overlay(Circle().strokeBorder(Color.inkFixed.opacity(0.35), lineWidth: line * 0.6)).offset(y: size * 0.19)
                face(size * 0.5, blink: blink).offset(y: -size * 0.1)
            }
            .overlay(Ellipse().strokeBorder(Color.ink, lineWidth: line).frame(width: size * 0.8, height: size))
            .frame(width: size, height: size)
        case .egg:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.34, style: .continuous).fill(Color.white).frame(width: size, height: size * 0.9)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.34, style: .continuous).strokeBorder(Color.ink, lineWidth: line).frame(width: size, height: size * 0.9))
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.2)).frame(width: size * 0.58, height: size * 0.58)
                    .overlay(Circle().strokeBorder(Color.inkFixed, lineWidth: line * 0.8))
                face(size * 0.46, blink: blink).offset(y: size * 0.01)
            }.frame(width: size, height: size)
        case .toast:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Color(red: 0.82, green: 0.47, blue: 0.22)).frame(width: size * 0.88, height: size * 0.94)
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(Color(red: 0.98, green: 0.72, blue: 0.44)).frame(width: size * 0.7, height: size * 0.76).offset(y: size * 0.03)
                RoundedRectangle(cornerRadius: size * 0.05, style: .continuous).fill(Color.butter).frame(width: size * 0.24, height: size * 0.17)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.05, style: .continuous).strokeBorder(Color.inkFixed, lineWidth: line * 0.6))
                    .rotationEffect(.degrees(14)).offset(x: size * 0.17, y: -size * 0.24)
                face(size * 0.46, blink: blink).offset(y: size * 0.08)
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(Color.ink, lineWidth: line).frame(width: size * 0.88, height: size * 0.94))
            .frame(width: size, height: size)
        }
    }
    /// Shared kawaii face: two eyes that blink, rosy cheeks, a small smile.
    private func face(_ s: CGFloat, blink: Bool) -> some View {
        ZStack {
            HStack(spacing: s * 0.34) {
                Capsule().fill(Color.inkFixed).frame(width: s * 0.1, height: blink ? s * 0.03 : s * 0.17)
                Capsule().fill(Color.inkFixed).frame(width: s * 0.1, height: blink ? s * 0.03 : s * 0.17)
            }.offset(y: -s * 0.12)
            HStack(spacing: s * 0.6) {
                Circle().fill(Color.bubble.opacity(0.85)).frame(width: s * 0.14, height: s * 0.14)
                Circle().fill(Color.bubble.opacity(0.85)).frame(width: s * 0.14, height: s * 0.14)
            }.offset(y: s * 0.05)
            Circle().trim(from: 0.08, to: 0.42).stroke(Color.inkFixed, style: StrokeStyle(lineWidth: max(1.5, s * 0.065), lineCap: .round))
                .frame(width: s * 0.34, height: s * 0.34).offset(y: -s * 0.06)
        }.frame(width: s, height: s)
    }
}
