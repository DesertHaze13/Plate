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


// MARK: - Palette: aurora pastels and clear, confident accents

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
    static let cream = adaptive((0.985, 0.975, 0.97), (0.06, 0.055, 0.09))
    static let surface = adaptive((1.0, 1.0, 1.0), (0.13, 0.12, 0.17))
    static let ink = adaptive((0.09, 0.08, 0.13), (0.97, 0.96, 0.98))
    static let inkFixed = Color(red: 0.09, green: 0.08, blue: 0.13)
    /// Protein.
    static let chili = Color(red: 1.0, green: 0.42, blue: 0.38)
    /// Carbs.
    static let butter = Color(red: 1.0, green: 0.70, blue: 0.26)
    /// Fat.
    static let matcha = Color(red: 0.18, green: 0.78, blue: 0.62)
    /// The accent: electric violet.
    static let ube = Color(red: 0.45, green: 0.33, blue: 1.0)
    static let bubble = Color(red: 1.0, green: 0.55, blue: 0.75)
    static let sky = Color(red: 0.35, green: 0.68, blue: 1.0)
    static let overRed = Color(red: 1.0, green: 0.27, blue: 0.35)
    static let plateAccent = ube
    static let plateCarb = butter
    static let plateFat = matcha
    // Older names, kept so every screen picks up the palette.
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

/// One motion vocabulary for the whole app, so everything moves with the same physics.
enum Motion {
    /// Taps, toggles, selections.
    static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.8)
    /// Things moving to a new place.
    static let fluid = Animation.spring(response: 0.55, dampingFraction: 0.82)
    /// Arrivals with a little life in them.
    static let lively = Animation.spring(response: 0.6, dampingFraction: 0.68)
    /// Slow, ambient drift.
    static let drift = Animation.easeInOut(duration: 2.4)
}
/// A Liquid Glass panel floating over the aurora. Solid when Reduce Transparency is on.
/// Every card arrives by rising out of a soft blur, and breathes with the scroll: it eases back and softens
/// as it nears the edge of the screen, and comes forward, sharp, in the middle.
struct GlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var arrived = false
    func body(content: Content) -> some View {
        surface(content)
            .opacity(arrived || reduced ? 1 : 0)
            .blur(radius: arrived || reduced ? 0 : 10)
            .scaleEffect(arrived || reduced ? 1 : 0.96, anchor: .bottom)
            .offset(y: arrived || reduced ? 0 : 14)
            .scrollTransition(.interactive, axis: .vertical) { view, phase in
                view.scaleEffect(reduced || phase.isIdentity ? 1 : 0.95)
                    .opacity(reduced || phase.isIdentity ? 1 : 0.6)
                    .blur(radius: reduced || phase.isIdentity ? 0 : 2)
                    .offset(y: reduced ? 0 : phase.value * 12)
            }
            .onAppear { withAnimation(reduced ? nil : Motion.lively.delay(0.05)) { arrived = true } }
    }
    @ViewBuilder private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.surface))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }
}
/// Shown while the AI works: an aurora ring that turns, sparkles that pulse, and a line of text that shimmers.
struct AILoader: View {
    var title = "Thinking about your food…"
    var detail: String? = nil
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(AngularGradient(colors: [.ube, .bubble, .chili, .butter, .matcha, .ube], center: .center), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                Image(systemName: "sparkles").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.plateAccent)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduced)
            }.frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                    .phaseAnimator([0.45, 1.0]) { view, glow in view.opacity(reduced ? 1 : glow) } animation: { _ in .easeInOut(duration: 0.9) }
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassEffect(.regular.tint(Color.plateAccent.opacity(0.12)), in: .rect(cornerRadius: 22))
        .transition(.blurReplace)
        .onAppear { guard !reduced else { return }; withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { spinning = true } }
        .accessibilityElement(children: .combine)
    }
}
extension View { func plateCard() -> some View { modifier(GlassCard()) } }

/// The aurora: a soft mesh of peach, lilac and mint that drifts slowly, tinted by how the day is going.
struct PlateBackground: View {
    let status: DayStatus
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.plateMotionActive) private var motionActive
    private var colors: [Color] {
        let tint = status.color
        if scheme == .dark {
            let plum = Color(red: 0.16, green: 0.10, blue: 0.26), navy = Color(red: 0.07, green: 0.11, blue: 0.20)
            let teal = Color(red: 0.05, green: 0.17, blue: 0.17), rose = Color(red: 0.22, green: 0.09, blue: 0.17), base = Color(red: 0.06, green: 0.055, blue: 0.09)
            return [plum, base, navy, rose, tint.mix(with: base, by: 0.7), teal, navy, base, plum]
        }
        let peach = Color(red: 1.0, green: 0.85, blue: 0.76), lilac = Color(red: 0.86, green: 0.82, blue: 1.0)
        let mint = Color(red: 0.80, green: 0.96, blue: 0.90), pink = Color(red: 1.0, green: 0.86, blue: 0.92), base = Color(red: 0.99, green: 0.98, blue: 0.97)
        return [peach, base, lilac, pink, tint.mix(with: base, by: 0.78), mint, lilac, base, peach]
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduced || !motionActive)) { timeline in
            let t = reduced ? 0 : timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, Float(0.5 + 0.12 * sin(t * 0.21))], [Float(0.5 + 0.16 * sin(t * 0.17)), Float(0.5 + 0.14 * cos(t * 0.13))], [1, Float(0.5 + 0.12 * cos(t * 0.19))],
                [0, 1], [Float(0.5 + 0.12 * cos(t * 0.15)), 1], [1, 1]
            ], colors: colors)
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        .animation(.easeInOut(duration: 1.4), value: status)
    }
}

// MARK: - Small pieces

/// Plate's mark: an aurora ring.
struct PlateMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().stroke(AngularGradient(colors: [.ube, .chili, .butter, .matcha, .ube], center: .center), lineWidth: size * 0.2)
                .padding(size * 0.1)
            Circle().fill(Color.ink).frame(width: size * 0.16, height: size * 0.16).offset(y: -size * 0.4 + size * 0.1)
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
                Circle().stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: compact ? 7 : 10))
                Circle().trim(from: 0, to: min(1, max(0, value / max(1, target)))).stroke(color, style: StrokeStyle(lineWidth: compact ? 7 : 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.8), value: value)
                VStack(spacing: 1) {
                    Text(value, format: .number.precision(.fractionLength(0))).font(.system(compact ? .headline : .title2, design: .rounded, weight: .bold)).contentTransition(.numericText())
                    if !compact { Text("of \(Int(target)) g").font(.caption2).foregroundStyle(.secondary) }
                }
            }.frame(width: compact ? 58 : 88, height: compact ? 58 : 88)
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(name), \(Int(value)) of \(Int(target)) grams")
    }
}
struct CaptureButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: "camera.fill"); Text("Log a meal").fontWeight(.semibold) }
                .foregroundStyle(.white).padding(.horizontal, 24).padding(.vertical, 16)
                .background { if reduceTransparency { Capsule().fill(Color.plateAccent) } }
        }.buttonStyle(PlatePress())
            .glassEffect(reduceTransparency ? .identity : .regular.tint(Color.plateAccent).interactive(), in: .capsule)
            .accessibilityHint("Take a photo, read a label, or enter food manually")
    }
}
struct FoodPhoto: View {
    let path: String?
    @Environment(PlateModel.self) private var model
    @State private var data: Data?
    var body: some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.05))
            if let data, let image = platformImage(data) { image.resizable().scaledToFill() }
            else { Image(systemName: "fork.knife").font(.title2).foregroundStyle(.secondary) }
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
/// A quiet label above each section: an accent dot and tracked capitals.
struct SectionEyebrow: View {
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.plateAccent).frame(width: 6, height: 6)
            Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
/// Buttons settle down a touch when pressed and spring back.
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
            .scaleEffect(reduced ? 1 : pressed ? 0.96 : hovering ? 1.015 : 1)
            .animation(reduced ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: pressed)
            .animation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: hovering)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, isPressed in isPressed }
            .onHover { hovering = $0 }
    }
}
/// A glass disc holding a tinted glyph.
struct PlateIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 42
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: .circle)
            .scaleEffect(hovering && !reduced ? 1.06 : 1)
            .animation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }.accessibilityHidden(true)
    }
}
/// The capture-screen illustration: a slowly turning aurora orb inside a glass ring. Tap to spin it.
struct PlateSculpture: View {
    @State private var turning = false
    @State private var spins = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { withAnimation(reduced ? nil : .spring(response: 1, dampingFraction: 0.7)) { spins += 1 } } label: {
            ZStack {
                Circle().fill(AngularGradient(colors: [.ube, .bubble, .butter, .matcha, .sky, .ube], center: .center))
                    .blur(radius: 18).padding(22)
                    .rotationEffect(.degrees(turning ? 360 : 0))
                Circle().fill(.clear).glassEffect(.regular, in: .circle).padding(10)
                Image(systemName: "fork.knife").font(.system(size: 34, weight: .semibold)).foregroundStyle(Color.ink.opacity(0.8))
            }.frame(width: 150, height: 150).rotationEffect(.degrees(spins * 360))
        }.buttonStyle(PlatePress())
            .onAppear { guard !reduced else { return }; withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { turning = true } }
            .accessibilityLabel("Spin the orb").accessibilityHint("Decoration only; it doesn't change your food log")
    }
}
/// Choices as real Liquid Glass. Two or three options use the system segmented control, whose glass selection
/// can be dragged with a magnifying lens; more options become a row of glass chips with a tinted glass highlight
/// that melts from chip to chip.
struct PlateSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Group {
            if options.count <= 3 {
                Picker("", selection: $selection) {
                    ForEach(options.indices, id: \.self) { index in Text(options[index]).tag(index) }
                }
                .pickerStyle(.segmented).labelsHidden()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(options.indices, id: \.self) { index in
                                let selected = selection == index
                                Button { withAnimation(reduced ? nil : .spring(response: 0.42, dampingFraction: 0.75)) { selection = index } } label: {
                                    Text(options[index]).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .glassEffect(selected ? Glass.regular.tint(Color.plateAccent).interactive() : Glass.regular.interactive(), in: .capsule)
                                .glassEffectID(index, in: glass)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }.padding(.vertical, 2).padding(.horizontal, 1)
                    }
                }.scrollClipDisabled()
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
struct PlatePageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: eyebrow)
            Text(title).font(.system(size: 40, weight: .bold)).tracking(-1.4).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The energy ring

/// Today's energy on a glass disc. The outer ring fills toward the target with a glowing tip; past it, a red ring traces the overflow.
/// The inner ring shows how your calories split between protein, carbs and fat. Dots on the edge mark when you ate.
struct PlateDial: View {
    let meals: [Meal]
    let target: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var reach: Double = 0
    @State private var split: Double = 0
    @State private var showRemaining = false
    @State private var tilt = CGSize.zero
    @State private var pulse = 0
    @State private var breathe = false
    private let side: CGFloat = 250
    private var alert: LimitState { LimitState(value: eaten, target: target) }
    private var auraColors: [Color] {
        switch alert {
        case .room: [.ube, .bubble, .sky, .ube]
        case .near: [.butter, .chili, .butter]
        case .over: [.overRed, .chili, .overRed]
        }
    }
    private struct Segment: Identifiable { let id: String; let start: Double; let end: Double; let color: Color }
    private var eaten: Double { meals.reduce(0) { $0 + $1.total.calories } }
    private var segments: [Segment] {
        let total = meals.reduce(Nutrients.zero) { $0 + $1.total }
        let parts: [(String, Double, Color)] = [("p", total.protein * 4, .chili), ("c", total.carbs * 4, .butter), ("f", total.fat * 9, .matcha)]
        let sum = parts.reduce(0) { $0 + $1.1 }
        guard sum > 0 else { return [] }
        var cursor = 0.0
        return parts.filter { $0.1 > 0 }.map { part in
            let width = part.1 / sum
            defer { cursor += width }
            return Segment(id: part.0, start: cursor + 0.012, end: cursor + width - 0.012, color: part.2)
        }
    }
    private func dayFraction(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60) / 24
    }
    var body: some View {
        Button {
            withAnimation(reduced ? nil : .spring(response: 0.45, dampingFraction: 0.8)) { showRemaining.toggle() }
            pulse += 1
        } label: {
            ZStack {
                // A soft aura that breathes behind the ring: violet with room, amber when close, red when over.
                Circle().fill(AngularGradient(colors: auraColors, center: .center))
                    .blur(radius: 34).opacity(alert == .room ? 0.35 : 0.55)
                    .scaleEffect(breathe ? 1.04 : 0.9)
                    .animation(reduced ? nil : .easeInOut(duration: alert == .over ? 0.9 : 2.4).repeatForever(autoreverses: true), value: breathe)
                    .animation(.easeInOut(duration: 0.8), value: alert)
                if alert == .over { WarningRipple(color: .overRed) }
                disc
                ring
                inner
                center
            }
            .frame(width: side, height: side)
            .keyframeAnimator(initialValue: 1.0, trigger: pulse) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
                SpringKeyframe(0.97, duration: 0.1)
                SpringKeyframe(1.0, duration: 0.4)
            }
            .rotation3DEffect(.degrees(reduced ? 0 : Double(tilt.width / 9)), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(reduced ? 0 : Double(-tilt.height / 9)), axis: (x: 1, y: 0, z: 0))
        }.buttonStyle(.plain)
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { tilt = CGSize(width: max(-60, min(60, $0.translation.width)), height: max(-60, min(60, $0.translation.height))) }.onEnded { _ in withAnimation(reduced ? nil : .spring(response: 0.6, dampingFraction: 0.6)) { tilt = .zero } })
            .sensoryFeedback(.impact(weight: .light), trigger: pulse)
            .sensoryFeedback(.warning, trigger: alert) { _, new in new != .room }
            .onAppear {
                guard !reduced else { reach = eaten / max(1, target); split = 1; return }
                breathe = true
                withAnimation(.spring(response: 1.6, dampingFraction: 0.85).delay(0.2)) { reach = eaten / max(1, target) }
                withAnimation(.spring(response: 1.4, dampingFraction: 0.85).delay(0.5)) { split = 1 }
            }
            .onChange(of: eaten) { _, new in withAnimation(reduced ? nil : .spring(response: 1.1, dampingFraction: 0.8)) { reach = new / max(1, target) } }
            .onChange(of: target) { _, new in withAnimation(reduced ? nil : .spring(response: 1, dampingFraction: 0.8)) { reach = eaten / max(1, new) } }
            .accessibilityLabel("\(Int(eaten)) of \(Int(target)) calories across \(meals.count) \(meals.count == 1 ? "meal" : "meals"). Tap to switch between eaten and remaining.")
    }
    @ViewBuilder private var disc: some View {
        if reduceTransparency { Circle().fill(Color.surface) }
        else { Circle().fill(.clear).glassEffect(.regular, in: .circle) }
    }
    private var ring: some View {
        let fill = min(1, reach)
        let radius = side / 2 - 22
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: 18).padding(13)
            Circle().trim(from: 0, to: fill)
                .stroke(AngularGradient(colors: [.ube, .bubble, .chili, .butter], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, fill))), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(13)
            // The tip of the ring.
            Circle().fill(.white).frame(width: 8, height: 8)
                .offset(y: -radius).rotationEffect(.degrees(fill * 360)).opacity(fill > 0.02 ? 1 : 0)
            // Past the target, a thin red ring traces the overflow.
            Circle().trim(from: 0, to: min(1, max(0, reach - 1)))
                .stroke(Color.overRed, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(1)
            ForEach(meals) { meal in
                Circle().fill(Color.primary.opacity(0.55)).frame(width: 4, height: 4)
                    .offset(y: -(side / 2 - 3)).rotationEffect(.degrees(dayFraction(meal.timestamp) * 360))
            }
        }
    }
    private var inner: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.05), lineWidth: 6).padding(44)
            ForEach(segments) { segment in
                Circle().trim(from: segment.start * split, to: max(segment.start * split, segment.end * split))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(44)
            }
        }
    }
    private var center: some View {
        let remaining = target - eaten
        return VStack(spacing: 2) {
            Text(Int((showRemaining ? abs(remaining) : eaten).rounded()), format: .number)
                .font(.system(size: 50, weight: .bold, design: .rounded)).tracking(-1.5)
                .contentTransition(.numericText(value: showRemaining ? remaining : eaten)).lineLimit(1).minimumScaleFactor(0.5)
            Text(showRemaining ? (remaining < 0 ? "kcal over" : "kcal left") : "kcal eaten").font(.footnote.weight(.semibold)).foregroundStyle(tint)
            Text("of \(Int(target))").font(.caption2).foregroundStyle(.secondary)
        }.frame(width: side - 110)
    }
}

// MARK: - Limits

/// Where a number sits against its target: plenty of room, getting close (85% and up), or past it.
enum LimitState: Equatable {
    case room, near, over
    init(value: Double, target: Double) {
        guard target > 0 else { self = .room; return }
        let ratio = value / target
        self = ratio > 1.0 ? .over : ratio >= 0.85 ? .near : .room
    }
    var color: Color { switch self { case .room: Color.ube; case .near: .butter; case .over: .overRed } }
}
/// Red rings that keep rippling outward while something is over its target.
struct WarningRipple: View {
    let color: Color
    var cornerRadius: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        if !reduced {
            Group {
                if let cornerRadius { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(color, lineWidth: 2) }
                else { Circle().strokeBorder(color, lineWidth: 2) }
            }
            .phaseAnimator([false, true]) { view, out in
                view.scaleEffect(out ? 1.06 : 1).opacity(out ? 0 : 0.8)
            } animation: { out in out ? .easeOut(duration: 1.3) : .linear(duration: 0.01) }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

// MARK: - Macro tiles

/// One macro: equal-size glass tile with a single-line label, a bar, and a warning that animates
/// when you're close to the target (amber, pulsing) or past it (red, a shake and a ripple).
struct NutrientTile: View {
    let name: String
    let symbol: String
    let value: Double
    let target: Double
    let tint: Color
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var state: LimitState { LimitState(value: value, target: target) }
    private var caption: String {
        switch state {
        case .room: "of \(Int(target)) g"
        case .near: "\(Int(max(0, target - value).rounded(.up))) g to go"
        case .over: "Over +\(Int((value - target).rounded(.up))) g"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if state == .near {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2.weight(.bold)).foregroundStyle(Color.butter)
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduced).transition(.scale.combined(with: .opacity))
                } else if state == .over {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption.weight(.bold)).foregroundStyle(Color.overRed)
                        .symbolEffect(.breathe, isActive: !reduced).transition(.scale.combined(with: .opacity))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(Int(value), format: .number).font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-0.5)
                    .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
                Text("g").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(state == .over ? Color.overRed : tint)
                            .frame(width: geometry.size.width * (grown || reduced ? min(1, max(0, value / max(1, target))) : 0))
                    }
            }.frame(height: 6)
            Text(caption).font(.caption2.weight(state == .room ? .medium : .bold))
                .foregroundStyle(state == .room ? AnyShapeStyle(.secondary) : AnyShapeStyle(state.color))
                .lineLimit(1).minimumScaleFactor(0.7).contentTransition(.numericText())
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .plateCard()
        .overlay {
            if state != .room {
                RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(state.color.opacity(0.75), lineWidth: 1.5).allowsHitTesting(false)
            }
        }
        .overlay { if state == .over { WarningRipple(color: .overRed, cornerRadius: 28) } }
        .keyframeAnimator(initialValue: 0.0, trigger: state) { view, x in view.offset(x: x) } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-7, duration: 0.06)
                LinearKeyframe(7, duration: 0.08)
                LinearKeyframe(-4, duration: 0.07)
                LinearKeyframe(4, duration: 0.07)
                SpringKeyframe(0, duration: 0.25)
            }
        }
        .animation(reduced ? nil : .spring(response: 0.5, dampingFraction: 0.75), value: state)
        .animation(reduced ? nil : .spring(response: 0.8, dampingFraction: 0.8), value: value)
        .sensoryFeedback(.warning, trigger: state) { _, new in new != .room }
        .onAppear { withAnimation(reduced ? nil : .spring(response: 1.1, dampingFraction: 0.85).delay(0.3)) { grown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(Int(value)) of \(Int(target)) grams. \(caption)")
    }
}

struct PlateCalendar: View {
    @Binding var selection: Date
    @Namespace private var highlight
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
                        Button { withAnimation(reduced ? nil : Motion.fluid) { selection = day } } label: {
                            Text("\(cell-leading+1)").font(.system(.subheadline, design: .rounded, weight: active ? .bold : .medium)).frame(maxWidth: .infinity).frame(height: 36).foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)).background { if active { Circle().fill(.clear).glassEffect(Glass.regular.tint(Color.plateAccent).interactive(), in: .circle).matchedGeometryEffect(id: "calendar-day", in: highlight) } }.overlay(Circle().stroke(calendar.isDateInToday(day) ? Color.plateAccent : .clear))
                        }.disabled(day > Date.now).accessibilityLabel(day.formatted(date: .complete, time: .omitted)).accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
            }
        }.buttonStyle(PlatePress()).foregroundStyle(.primary).padding(22).plateCard()
            .onAppear { month = calendar.dateInterval(of: .month, for: selection)?.start ?? month }
            .onChange(of: selection) { _, value in month = calendar.dateInterval(of: .month, for: value)?.start ?? month }
    }
    private func move(_ amount: Int) {
        withAnimation(reduced ? nil : Motion.fluid) { month = calendar.date(byAdding: .month, value: amount, to: month) ?? month }
    }
}

private struct PlateMotionActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var plateMotionActive: Bool {
        get { self[PlateMotionActiveKey.self] }
        set { self[PlateMotionActiveKey.self] = newValue }
    }
}
/// Cards drift up out of a soft blur, one after another.
private struct PlateEntrance: ViewModifier {
    let order: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        content.opacity(appeared || reduced ? 1 : 0)
            .blur(radius: appeared || reduced ? 0 : 12)
            .offset(y: appeared || reduced ? 0 : 18)
            .onAppear { withAnimation(reduced ? nil : .spring(response: 0.7, dampingFraction: 0.88).delay(Double(min(order, 6)) * 0.07)) { appeared = true } }
    }
}
extension View { func plateEntrance(_ order: Int = 0) -> some View { modifier(PlateEntrance(order: order)) } }

/// A soft burst of coloured light when you log food or hit your target.
struct SparkBurst: View {
    let trigger: Int
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        ZStack { if trigger > 0 && !reduced { LightBurst(tint: tint).id(trigger) } }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct LightBurst: View {
    let tint: Color
    @State private var fired = false
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(fired ? 0 : 0.5), lineWidth: 2).scaleEffect(fired ? 1.6 : 0.6)
            ForEach(0..<14, id: \.self) { index in
                let angle = Double(index) / 14 * 2 * .pi
                Circle().fill([Color.ube, .chili, .butter, .matcha][index % 4])
                    .frame(width: 6, height: 6)
                    .offset(x: fired ? cos(angle) * 150 : cos(angle) * 60, y: fired ? sin(angle) * 150 : sin(angle) * 60)
                    .opacity(fired ? 0 : 0.9)
            }
        }.frame(width: 260, height: 260)
            .onAppear { withAnimation(.easeOut(duration: 0.9)) { fired = true } }
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
