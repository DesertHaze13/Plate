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

/// The iPad palette: lilac, peach, mint and translucent glass.
extension Color {
    static let glazeCharcoal = Color(red: 0.067, green: 0.063, blue: 0.059)
    static let glazeSlate = Color(red: 0.114, green: 0.106, blue: 0.098)
    static let glazeRim = Color(red: 0.165, green: 0.153, blue: 0.141)
    static let porcelain = Color(red: 0.975, green: 0.977, blue: 0.953)
    static let saffron = Color(red: 0.918, green: 0.635, blue: 0.227)
    static let terracotta = Color(red: 0.812, green: 0.408, blue: 0.259)
    static let celadon = Color(red: 0.25, green: 0.76, blue: 0.60)
    static let bubble = Color(red: 0.91, green: 0.45, blue: 0.58)
    static let sky = Color(red: 0.36, green: 0.60, blue: 0.88)
    static let glazeRed = Color(red: 0.898, green: 0.318, blue: 0.247)
    /// Roles: the accent doubles as protein; carbs are terracotta; fat is celadon.
    #if os(iOS)
    static let plateAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.69, green: 0.58, blue: 1, alpha: 1)
            : UIColor(red: 0.47, green: 0.31, blue: 0.96, alpha: 1)
    })
    #else
    static let plateAccent = Color(nsColor: NSColor(name: NSColor.Name("PlateAccent")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.69, green: 0.58, blue: 1, alpha: 1)
            : NSColor(red: 0.47, green: 0.31, blue: 0.96, alpha: 1)
    })
    #endif
    static let plateProtein = Color(red: 0.98, green: 0.43, blue: 0.45)
    static let plateCarb = Color(red: 1, green: 0.74, blue: 0.28)
    static let plateFat = celadon
}
extension DayStatus {
    var color: Color { switch self { case .calm: Color.plateAccent; case .almost: .terracotta; case .hit: .celadon; case .over: .glazeRed } }
}
struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(scheme == .dark ? Color(red: 0.09, green: 0.15, blue: 0.14) : .white.opacity(opaque ? 1 : 0.50))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(scheme == .dark ? .white.opacity(0.12) : .white, lineWidth: 1)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.045), radius: 22, y: 10)
        }
    }
}
extension View { func plateCard() -> some View { modifier(GlassCard()) } }

struct PlateBackground: View {
    let status: DayStatus
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.plateMotionActive) private var active
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduced || !active)) { time in
            let phase = reduced ? 0 : time.date.timeIntervalSinceReferenceDate / 22
            let colors: [Color] = scheme == .dark
                ? [Color(red: 0.16, green: 0.10, blue: 0.19), Color(red: 0.14, green: 0.10, blue: 0.24), Color(red: 0.10, green: 0.12, blue: 0.21),
                   Color(red: 0.18, green: 0.11, blue: 0.25), Color(red: 0.10, green: 0.09, blue: 0.18), Color(red: 0.06, green: 0.20, blue: 0.19),
                   Color(red: 0.14, green: 0.10, blue: 0.24), Color(red: 0.09, green: 0.09, blue: 0.14), Color(red: 0.23, green: 0.14, blue: 0.12)]
                : [Color(red: 1, green: 0.88, blue: 0.80), Color(red: 1, green: 0.94, blue: 0.99), Color(red: 0.88, green: 0.87, blue: 1),
                   Color(red: 0.95, green: 0.85, blue: 1), Color(red: 0.96, green: 0.93, blue: 1), Color(red: 0.78, green: 0.97, blue: 0.90),
                   Color(red: 0.87, green: 0.85, blue: 1), Color(red: 1, green: 0.99, blue: 0.95), Color(red: 1, green: 0.87, blue: 0.77)]
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [Float(0.5 + sin(phase) * 0.09), Float(0.5 + cos(phase) * 0.08)], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ], colors: colors)
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
/// Plate's mark: a plate seen from above.
struct PlateMark: View {
    var size: CGFloat = 44
    var body: some View {
        Circle()
            .stroke(AngularGradient(colors: [.plateAccent, .bubble, .plateCarb, .celadon, .plateAccent], center: .center), lineWidth: size * 0.18)
            .padding(size * 0.13)
            .overlay(alignment: .top) { Circle().fill(Color.primary.opacity(0.75)).frame(width: size * 0.13, height: size * 0.13).padding(.top, size * 0.08) }
            .frame(width: size, height: size).accessibilityHidden(true)
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
                Circle().stroke(color.opacity(0.12), style: StrokeStyle(lineWidth: compact ? 6 : 9))
                Circle().trim(from: 0, to: min(1, max(0, value/max(1,target)))).stroke(color.gradient, style: StrokeStyle(lineWidth: compact ? 6 : 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.8), value: value)
                VStack(spacing: 1) {
                    Text(value, format: .number.precision(.fractionLength(0))).font(compact ? .headline : .title2.bold()).contentTransition(.numericText())
                    if !compact { Text("of \(Int(target)) g").font(.caption2).foregroundStyle(.secondary) }
                }
            }.frame(width: compact ? 58 : 88, height: compact ? 58 : 88)
            Text(name).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(name), \(Int(value)) of \(Int(target)) grams")
    }
}
struct CaptureButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Log a meal", systemImage: "camera.fill")
                .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 16)
                .background(Color.plateAccent.gradient, in: .capsule)
        }.buttonStyle(PlatePress()).accessibilityHint("Take a photo, read a label, or enter food manually")
    }
}
struct FoodPhoto: View {
    let path: String?
    @Environment(PlateModel.self) private var model
    @State private var data: Data?
    var body: some View {
        ZStack {
            Rectangle().fill(Color.plateAccent.opacity(0.09))
            if let data, let image = platformImage(data) { image.resizable().scaledToFill() }
            else { Image(systemName: "fork.knife").font(.title2).foregroundStyle(Color.plateAccent) }
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
struct SectionEyebrow: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.plateAccent).frame(width: 5, height: 5)
            Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.8).foregroundStyle(.secondary)
        }
    }
}

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
        content.scaleEffect(reduced ? 1 : pressed ? 0.965 : hovering ? 1.012 : 1)
            .offset(y: hovering && !pressed && !reduced ? -2 : 0)
            .brightness(hovering ? 0.025 : 0)
            .animation(reduced ? nil : .spring(response: 0.32, dampingFraction: 0.68), value: pressed)
            .animation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }
}
/// A small saucer holding a glyph.
struct PlateIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 42
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.40, weight: .semibold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.12)))
            .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 1).padding(size * 0.08))
            .overlay(Circle().stroke(Color.porcelain.opacity(0.12), lineWidth: 0.8))
            .shadow(color: tint.opacity(0.1), radius: hovering ? 10 : 6, y: 4)
            .rotationEffect(.degrees(hovering && !reduced ? 18 : 0))
            .animation(reduced ? nil : .spring(response: 0.5, dampingFraction: 0.6), value: hovering)
            .onHover { hovering = $0 }.accessibilityHidden(true)
    }
}
/// The capture-screen illustration: a place setting. Tap to spin the plate.
struct PlateSculpture: View {
    @State private var spins = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { withAnimation(reduced ? nil : .spring(response: 1.1, dampingFraction: 0.55)) { spins += 1 } } label: {
            HStack(spacing: 14) {
                Image(systemName: "fork").font(.system(size: 30, weight: .light)).foregroundStyle(Color.porcelain.opacity(0.7))
                PlateMark(size: 120).rotationEffect(.degrees(spins * 360))
                Image(systemName: "knife").font(.system(size: 30, weight: .light)).foregroundStyle(Color.porcelain.opacity(0.7))
            }
        }.buttonStyle(PlatePress())
            .accessibilityLabel("Spin the plate").accessibilityHint("Decoration only; it doesn't change your food log")
    }
}
/// Text tabs with a saffron line that glides under the choice.
struct PlateSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        ViewThatFits(in: .horizontal) {
            choices
            ScrollView(.horizontal, showsIndicators: false) { choices }
        }.sensoryFeedback(.selection, trigger: selection)
    }
    private var choices: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(reduced ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { selection = index }
                } label: {
                    Text(title).font(.system(.caption, design: .rounded, weight: .semibold))
                        .fixedSize().padding(.horizontal, 16).frame(minHeight: 44)
                        .foregroundStyle(selection == index ? .white : Color.primary)
                        .background {
                            if selection == index {
                                Capsule().fill(Color.plateAccent.gradient).matchedGeometryEffect(id: "segment", in: highlight)
                            } else {
                                Capsule().fill(.thinMaterial).overlay(Capsule().stroke(.white.opacity(0.65), lineWidth: 1))
                            }
                        }
                }.buttonStyle(PlatePress()).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
    }
}
struct PlatePageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) { Capsule().fill(Color.saffron).frame(width: 22, height: 2.5); SectionEyebrow(text: eyebrow) }
            Text(title).font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.2).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// Today, seen as a plate from above. Each meal is laid down clockwise as a wedge of its protein, carbs and fat; a full plate is the target, and anything past it spills onto the rim.
/// The rim marks the 24 hours of the day, with a dot for each meal and a saffron tick for now.
struct PlateDial: View {
    let meals: [Meal]
    let target: Double
    let tint: Color
    var macroTargets: Nutrients = .zero
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var showRemaining = false
    private var total: Nutrients { meals.reduce(.zero) { $0 + $1.total } }
    var body: some View {
        Button {
            withAnimation(reduced ? nil : .spring(response: 0.5, dampingFraction: 0.8)) { showRemaining.toggle() }
        } label: {
            GeometryReader { geometry in
                let size = geometry.size.width
                let line = size * 0.065
                let progress = min(1, max(0, total.calories / max(1, target)))
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(.white.opacity(scheme == .dark ? 0.15 : 0.85), lineWidth: 1.5))
                        .shadow(color: Color.plateAccent.opacity(0.14), radius: 20, y: 10)
                    Circle().stroke(Color.plateAccent.opacity(0.07), lineWidth: line).padding(line)
                    Circle().trim(from: 0, to: progress)
                        .stroke(AngularGradient(colors: [.plateAccent, .bubble], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.01, progress))), style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(line)
                    ForEach(0..<3) { index in
                        let values = [total.protein, total.carbs, total.fat]
                        let targets = [macroTargets.protein, macroTargets.carbs, macroTargets.fat]
                        let colors: [Color] = [.plateProtein, .plateCarb, .plateFat]
                        let start = Double(index) / 3 + 0.018
                        let span = 1.0 / 3 - 0.036
                        Circle().trim(from: start, to: start + span * min(1, max(0, values[index] / max(1, targets[index]))))
                            .stroke(colors[index], style: StrokeStyle(lineWidth: size * 0.021, lineCap: .round))
                            .rotationEffect(.degrees(-90)).padding(size * 0.18)
                    }
                    VStack(spacing: 6) {
                        Text(showRemaining ? Int(max(0, target - total.calories).rounded()) : Int(total.calories.rounded()), format: .number)
                            .font(.system(size: size * 0.19, weight: .bold, design: .rounded)).tracking(-2)
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)
                        Text(showRemaining ? "kcal left" : "kcal eaten")
                            .font(.system(size: size * 0.045, weight: .semibold, design: .rounded)).foregroundStyle(Color.plateAccent)
                        Text("of \(Int(target).formatted())")
                            .font(.system(size: size * 0.037, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Circle().fill(.white).frame(width: size * 0.026, height: size * 0.026)
                        .offset(y: -size / 2 + line)
                        .rotationEffect(.degrees(progress * 360))
                }
            }.aspectRatio(1, contentMode: .fit)
        }.buttonStyle(PlatePress()).frame(maxWidth: 320)
            .animation(reduced ? nil : .spring(response: 0.9, dampingFraction: 0.85), value: total)
            .accessibilityLabel("\(Int(total.calories)) of \(Int(target)) calories. Tap to switch eaten and left.")
    }
}
struct NutrientTile: View {
    let name: String
    let symbol: String
    let value: Double
    let target: Double
    let tint: Color
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button {
            withAnimation(reduced ? nil : .spring(response: 0.4)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 29, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    Text("g").font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    Capsule().fill(tint.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: geometry.size.width * min(1, max(0, value / max(1, target))))
                        }
                }.frame(height: 5)
                Text(expanded ? "\(Int(max(0, target - value))) g left" : "of \(Int(target)) g")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).plateCard()
        }.buttonStyle(PlatePress()).foregroundStyle(.primary)
            .animation(reduced ? nil : .spring(response: 0.7), value: value)
            .accessibilityLabel("\(name), \(Int(value)) of \(Int(target)) grams")
            .accessibilityHint("Show remaining grams")
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
private struct PlateEntrance: ViewModifier {
    let order: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        content.opacity(appeared || reduced ? 1 : 0)
            .offset(y: appeared || reduced ? 0 : 14)
            .onAppear { withAnimation(reduced ? nil : .spring(response: 0.6, dampingFraction: 0.86).delay(Double(min(order, 6)) * 0.06)) { appeared = true } }
    }
}
extension View { func plateEntrance(_ order: Int = 0) -> some View { modifier(PlateEntrance(order: order)) } }

struct SparkBurst: View {
    let trigger: Int
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Group {
            if !reduced {
                Color.clear.keyframeAnimator(initialValue: 0.0, trigger: trigger) { _, progress in
                    ZStack {
                        ForEach(0..<12, id: \.self) { index in
                            let angle = Double(index) * .pi / 6
                            Circle().fill(tint).frame(width: 4, height: 4)
                                .offset(x: cos(angle) * progress * 125, y: sin(angle) * progress * 125)
                                .opacity(sin(progress * .pi))
                        }
                    }
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 0.8)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
