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

/// Warm paper, sea-glass green and small accents of coral and lilac.
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
            ? UIColor(red: 0.36, green: 0.84, blue: 0.68, alpha: 1)
            : UIColor(red: 0.08, green: 0.46, blue: 0.35, alpha: 1)
    })
    #else
    static let plateAccent = Color(nsColor: NSColor(name: NSColor.Name("PlateAccent")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.36, green: 0.84, blue: 0.68, alpha: 1)
            : NSColor(red: 0.08, green: 0.46, blue: 0.35, alpha: 1)
    })
    #endif
    static let plateCarb = terracotta
    static let plateFat = Color(red: 0.65, green: 0.53, blue: 0.86)
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
                .fill(scheme == .dark ? Color(red: 0.09, green: 0.15, blue: 0.14) : .white.opacity(opaque ? 1 : 0.78))
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
        GeometryReader { geometry in
            ZStack {
                (scheme == .dark ? Color(red: 0.045, green: 0.085, blue: 0.08) : .porcelain)
                TimelineView(.animation(minimumInterval: 1 / 24, paused: reduced || !active)) { time in
                    let phase = reduced ? 0 : time.date.timeIntervalSinceReferenceDate / 18
                    Ellipse()
                        .fill(Color.celadon.opacity(scheme == .dark ? 0.10 : 0.13))
                        .frame(width: geometry.size.width * 1.3, height: geometry.size.height * 0.7)
                        .rotationEffect(.degrees(sin(phase) * 12 - 24))
                        .position(x: geometry.size.width * 0.05, y: geometry.size.height * 0.88)
                    Ellipse()
                        .fill(Color.plateFat.opacity(scheme == .dark ? 0.07 : 0.055))
                        .frame(width: geometry.size.width, height: geometry.size.height * 0.55)
                        .rotationEffect(.degrees(cos(phase) * 10 + 28))
                        .position(x: geometry.size.width * 0.97, y: geometry.size.height * 0.28)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
/// Plate's mark: a plate seen from above.
struct PlateMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color.glazeRim, Color.glazeCharcoal], center: .center, startRadius: 0, endRadius: size / 2))
            Circle().stroke(Color.porcelain.opacity(0.25), lineWidth: 1).padding(size * 0.14)
            Circle().trim(from: 0, to: 0.62).stroke(Color.saffron, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)).rotationEffect(.degrees(-90)).padding(size * 0.25)
            Circle().stroke(AngularGradient(colors: [.clear, Color.porcelain.opacity(0.6), .clear], center: .center, startAngle: .degrees(200), endAngle: .degrees(290)), lineWidth: 1.2)
        }.frame(width: size, height: size).shadow(color: .black.opacity(0.5), radius: size * 0.15, y: size * 0.08).accessibilityHidden(true)
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
            HStack(spacing: 10) { Image(systemName: "camera.fill"); Text("Log a meal").fontWeight(.semibold) }
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(Color.glazeCharcoal)
                .padding(.horizontal, 24).padding(.vertical, 16)
                .background(Capsule().fill(LinearGradient(colors: [Color.porcelain, Color(red: 0.86, green: 0.81, blue: 0.73)], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().stroke(Color.saffron, lineWidth: 1.5).padding(-4))
                .shadow(color: Color.saffron.opacity(0.35), radius: 16, y: 6)
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
    var body: some View { Text(text.uppercased()).font(.system(size: 10.5, weight: .bold, design: .rounded)).tracking(1.6).foregroundStyle(Color.secondary) }
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
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, title in
                Button { withAnimation(reduced ? nil : .spring(response: 0.38, dampingFraction: 0.78)) { selection = index } } label: {
                    VStack(spacing: 7) {
                        Text(title).font(.system(.subheadline, design: .rounded, weight: selection == index ? .bold : .regular))
                            .foregroundStyle(selection == index ? Color.primary : Color.secondary)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 2.5)
                            if selection == index { Capsule().fill(Color.saffron).frame(height: 2.5).shadow(color: Color.saffron.opacity(0.7), radius: 5).matchedGeometryEffect(id: "segment", in: highlight) }
                        }
                    }.frame(maxWidth: .infinity).padding(.top, 8).contentShape(Rectangle())
                }.buttonStyle(PlatePress()).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1) }
            .sensoryFeedback(.selection, trigger: selection)
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
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var reach: Double = 0
    @State private var showRemaining = false
    @State private var tilt = CGSize.zero
    @State private var gleam = false
    private let side: CGFloat = 300
    private let bandWidth: CGFloat = 44
    private struct Slice: Identifiable { let id: String; let start: Double; let end: Double; let color: Color }
    private var eaten: Double { meals.reduce(0) { $0 + $1.total.calories } }
    private var slices: [Slice] {
        var cursor = 0.0
        var result: [Slice] = []
        let scale = 1 / max(1, target)
        for meal in meals.sorted(by: { $0.timestamp < $1.timestamp }) {
            let total = meal.total
            let span = total.calories * scale
            guard span > 0 else { continue }
            let parts: [(key: String, kcal: Double, color: Color)] = [("p", total.protein * 4, .celadon), ("c", total.carbs * 4, .terracotta), ("f", total.fat * 9, .plateFat)]
            let sum = parts.reduce(0) { $0 + $1.kcal }
            let gap = min(0.006, span * 0.2)
            var start = cursor
            if sum <= 0 {
                result.append(Slice(id: meal.id, start: start, end: start + span - gap, color: Color.porcelain.opacity(0.6)))
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
        return p >= c && p >= f ? .celadon : c >= f ? .terracotta : .plateFat
    }
    var body: some View {
        Button { withAnimation(reduced ? nil : .spring(response: 0.6, dampingFraction: 0.7)) { showRemaining.toggle() } } label: {
            ZStack { plate; rim; band; well }
                .frame(width: side, height: side)
                .rotation3DEffect(.degrees(reduced ? 0 : Double(tilt.width / 9)), axis: (x: 0, y: 1, z: 0))
                .rotation3DEffect(.degrees(reduced ? 0 : Double(-tilt.height / 9)), axis: (x: 1, y: 0, z: 0))
        }.buttonStyle(PlatePress())
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { tilt = CGSize(width: max(-70, min(70, $0.translation.width)), height: max(-70, min(70, $0.translation.height))) }.onEnded { _ in withAnimation(reduced ? nil : .spring(response: 0.6, dampingFraction: 0.5)) { tilt = .zero } })
            .onAppear {
                guard !reduced else { reach = eaten / max(1, target); return }
                withAnimation(.spring(response: 1.8, dampingFraction: 0.9).delay(0.25)) { reach = eaten / max(1, target) }
                withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { gleam = true }
            }
            .onChange(of: eaten) { _, newValue in withAnimation(reduced ? nil : .spring(response: 1.3, dampingFraction: 0.85)) { reach = newValue / max(1, target) } }
            .onChange(of: target) { _, newValue in withAnimation(reduced ? nil : .spring(response: 1, dampingFraction: 0.85)) { reach = eaten / max(1, newValue) } }
            .accessibilityLabel("\(Int(eaten)) of \(Int(target)) calories across \(meals.count) \(meals.count == 1 ? "meal" : "meals"). Tap to switch between eaten and remaining.")
    }
    private var plate: some View {
        ZStack {
            Circle().fill(Color.celadon.opacity(0.18)).blur(radius: 18).padding(10)
            Circle().fill(RadialGradient(colors: [Color(red: 0.12, green: 0.39, blue: 0.33), Color(red: 0.09, green: 0.27, blue: 0.24), Color(red: 0.06, green: 0.19, blue: 0.18)], center: UnitPoint(x: 0.42, y: 0.33), startRadius: 8, endRadius: side * 0.56))
            Circle().stroke(LinearGradient(colors: [Color.porcelain.opacity(0.3), .clear, Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5).padding(side * 0.115)
            Circle().stroke(Color.porcelain.opacity(0.08), lineWidth: 1).padding(side * 0.12)
            // A glint that travels slowly round the glaze.
            Circle().stroke(AngularGradient(colors: [.clear, Color.porcelain.opacity(0.5), .clear], center: .center, startAngle: .degrees(0), endAngle: .degrees(70)), lineWidth: 2.5).padding(2)
                .rotationEffect(.degrees(gleam ? 360 : 0))
        }
    }
    private var rim: some View {
        let radius = side * 0.44
        let now = dayFraction(.now)
        return ZStack {
            ForEach(0..<24, id: \.self) { hour in
                Capsule().fill(Color.porcelain.opacity(hour % 6 == 0 ? 0.5 : 0.16))
                    .frame(width: hour % 6 == 0 ? 2 : 1.2, height: hour % 6 == 0 ? 10 : 6)
                    .offset(y: -radius).rotationEffect(.degrees(Double(hour) / 24 * 360))
            }
            ForEach(meals) { meal in
                Circle().fill(dominant(meal)).frame(width: 7, height: 7).shadow(color: dominant(meal).opacity(0.9), radius: 4)
                    .offset(y: -radius).rotationEffect(.degrees(dayFraction(meal.timestamp) * 360))
                    .transition(.scale.combined(with: .opacity))
            }
            Capsule().fill(Color.saffron).frame(width: 3, height: 15).shadow(color: Color.saffron, radius: 5)
                .offset(y: -radius).rotationEffect(.degrees(now * 360))
        }
    }
    private var band: some View {
        let diameter = side * 0.547
        let fill = min(1, reach)
        return ZStack {
            Circle().stroke(Color.black.opacity(0.32), lineWidth: bandWidth).frame(width: diameter, height: diameter)
            Circle().stroke(Color.porcelain.opacity(0.035), lineWidth: bandWidth).frame(width: diameter, height: diameter)
            ForEach(slices) { slice in
                let from = min(slice.start, 1)
                Circle().trim(from: from, to: max(from, min(slice.end, reach, 1)))
                    .stroke(slice.color.gradient, style: StrokeStyle(lineWidth: bandWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90)).frame(width: diameter, height: diameter)
            }
            // The glaze: a soft highlight across the food.
            Circle().trim(from: 0, to: fill)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.28), .clear, Color.black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: bandWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90)).frame(width: diameter, height: diameter).blendMode(.overlay)
            // Past the target, food spills onto the rim.
            Circle().trim(from: 0, to: min(1, max(0, reach - 1)))
                .stroke(Color.glazeRed, style: StrokeStyle(lineWidth: 4, lineCap: .round)).shadow(color: Color.glazeRed, radius: 6)
                .rotationEffect(.degrees(-90)).frame(width: side * 0.73, height: side * 0.73)
        }
    }
    private var well: some View {
        let value = reach * max(1, target)
        let remaining = target - value
        return ZStack {
            Circle().fill(RadialGradient(colors: [Color.glazeCharcoal, Color.glazeSlate], center: .center, startRadius: 0, endRadius: 60)).frame(width: 118, height: 118)
                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 3).blur(radius: 2).offset(y: 2).mask(Circle()))
                .overlay(Circle().stroke(Color.porcelain.opacity(0.09), lineWidth: 1))
            VStack(spacing: 2) {
                Text(Int((showRemaining ? abs(remaining) : value).rounded()), format: .number)
                    .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Color.porcelain)
                    .contentTransition(.numericText(value: value)).minimumScaleFactor(0.6).lineLimit(1)
                Text(showRemaining ? (remaining < 0 ? "KCAL OVER" : "KCAL LEFT") : "KCAL ON PLATE").font(.system(size: 7.5, weight: .bold, design: .monospaced)).tracking(1.4).foregroundStyle(tint)
                Text("of \(Int(target))").font(.system(size: 10, design: .rounded)).foregroundStyle(Color.porcelain.opacity(0.5))
            }.frame(width: 102)
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
        Button { withAnimation(reduced ? nil : .spring(response: 0.4)) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(tint).frame(width: 32, height: 32).background(tint.opacity(0.13), in: .circle)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "minus" : "plus").font(.caption2.bold()).foregroundStyle(.secondary)
                }
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) { Text(Int(value), format: .number).font(.system(size: 27, weight: .bold, design: .rounded)).contentTransition(.numericText()); Text("g").font(.caption).foregroundStyle(.secondary) }
                GeometryReader { geo in
                    Capsule().fill(tint.opacity(0.13))
                        .overlay(alignment: .leading) { Capsule().fill(tint.gradient).frame(width: geo.size.width * (grown || reduced ? min(1,max(0,value/max(1,target))) : 0)).shadow(color: tint.opacity(0.6), radius: 4) }
                }.frame(height: 5)
                    .onAppear { withAnimation(reduced ? nil : .spring(response: 1.1, dampingFraction: 0.8).delay(0.35)) { grown = true } }
                    .animation(reduced ? nil : .spring(response: 0.8, dampingFraction: 0.75), value: value)
                if expanded { Text("\(Int(max(0,target-value))) g left\nTarget \(Int(target)) g").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).transition(.opacity.combined(with: .move(edge: .top))) }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(LinearGradient(colors: [Color.glazeRim, Color.glazeSlate], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tint.opacity(0.28))).overlay(alignment: .top) { Capsule().fill(tint).frame(width: 26, height: 2.5).padding(.top, 1) }
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
