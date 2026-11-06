import SwiftUI
import PlateCore

extension Color {
    static let plateMint = Color(red: 0.25, green: 0.72, blue: 0.57)
    static let plateCarb = Color(red: 0.92, green: 0.65, blue: 0.33)
    static let plateFat = Color(red: 0.64, green: 0.55, blue: 0.83)
}
extension DayStatus {
    var color: Color { switch self { case .calm: Color.plateMint; case .almost: .orange; case .hit: .green; case .over: .red } }
}
struct GlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background { if reduceTransparency { RoundedRectangle(cornerRadius: 30).fill(.background) } }
            .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(scheme == .dark ? 0.12 : 0.58), lineWidth: 0.7))
            .shadow(color: .black.opacity(scheme == .dark ? 0.20 : 0.065), radius: 24, y: 10)
    }
}
extension View { func plateCard() -> some View { modifier(GlassCard()) } }
struct PlateBackground: View {
    let status: DayStatus
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                (scheme == .dark ? Color(red: 0.045, green: 0.065, blue: 0.09) : Color(red: 0.976, green: 0.973, blue: 0.958))
                Circle().fill(Color.plateFat.opacity(scheme == .dark ? 0.14 : 0.07)).frame(width: 640, height: 640).position(x: geometry.size.width + 40, y: 40)
                Circle().fill(status.color.opacity(scheme == .dark ? 0.10 : 0.07)).frame(width: 540, height: 540).position(x: -100, y: geometry.size.height * 0.7)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: "camera.fill"); Text("Log a meal").fontWeight(.semibold) }.padding(.horizontal, 24).padding(.vertical, 17)
        }.buttonStyle(PlatePress()).foregroundStyle(.primary)
            .glassEffect(reduceTransparency ? .identity : .regular.tint(Color.plateMint.opacity(0.22)).interactive(), in: .capsule)
            .accessibilityHint("Take a photo, read a label, or enter food manually")
    }
}
struct FoodPhoto: View {
    let path: String?
    @Environment(PlateModel.self) private var model
    @State private var data: Data?
    var body: some View {
        ZStack {
            Rectangle().fill(Color.plateMint.opacity(0.09))
            if let data, let image = platformImage(data) { image.resizable().scaledToFill() }
            else { Image(systemName: "fork.knife").font(.title2).foregroundStyle(Color.plateMint) }
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
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(2.5).foregroundStyle(.secondary) }
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
struct PlateIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 42
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: size * 0.31))
            .overlay(RoundedRectangle(cornerRadius: size * 0.31).stroke(.white.opacity(0.4), lineWidth: 0.8))
            .shadow(color: tint.opacity(hovering ? 0.4 : 0.22), radius: hovering ? 13 : 7, y: 5)
            .rotation3DEffect(.degrees(hovering && !reduced ? -12 : 0), axis: (x: 0.3, y: 1, z: 0))
            .animation(reduced ? nil : .spring(response: 0.5, dampingFraction: 0.65), value: hovering)
            .onHover { hovering = $0 }.accessibilityHidden(true)
    }
}
struct PlateSculpture: View {
    @State private var turned = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { withAnimation(reduced ? nil : .spring(response: 0.7, dampingFraction: 0.45)) { turned.toggle() } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 32).fill(Color.plateCarb.gradient).frame(width: 95, height: 108).rotationEffect(.degrees(turned ? 18 : -18)).offset(x: -12, y: -5)
                RoundedRectangle(cornerRadius: 32).fill(LinearGradient(colors: [.white.opacity(0.96), Color.plateMint.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 95, height: 108).rotationEffect(.degrees(turned ? -20 : 13)).offset(x: 13, y: 5).shadow(color: .black.opacity(0.16), radius: 14, y: 10)
                Image(systemName: "fork.knife").font(.system(size: 34, weight: .medium)).foregroundStyle(Color(red: 0.08, green: 0.32, blue: 0.25)).rotationEffect(.degrees(turned ? -20 : 13)).offset(x: 13, y: 5)
                Image(systemName: "sparkle").font(.title3).foregroundStyle(Color.plateCarb).offset(x: turned ? -52 : 55, y: turned ? -48 : -42)
            }.frame(width: 145, height: 145).rotation3DEffect(.degrees(reduced ? 0 : turned || hovering ? 12 : -7), axis: (x: 0.3, y: 1, z: 0))
        }.buttonStyle(PlatePress()).onHover { value in withAnimation(reduced ? nil : .spring(response: 0.5)) { hovering = value } }
            .accessibilityLabel("Play with the Plate illustration").accessibilityHint("Tilts the illustration without changing your food log")
    }
}
struct PlateSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, title in
                Button { withAnimation(reduced ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { selection = index } } label: {
                    Text(title).font(.system(.caption, design: .rounded, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background { if selection == index { Capsule().fill(Color.plateMint.opacity(0.20)).matchedGeometryEffect(id: "segment", in: highlight) } }
                }.buttonStyle(PlatePress()).foregroundStyle(.primary).accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(4).background(.primary.opacity(0.045), in: .capsule).sensoryFeedback(.selection, trigger: selection)
    }
}
struct PlatePageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(text: eyebrow)
            Text(title).font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1.4)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// Tactile plate illustration. The orbit represents calorie progress; dragging only tilts the artwork.
struct EnergyOrbit: View {
    let value: Double
    let target: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var tilt = CGSize.zero
    @State private var showRemaining = false
    private var progress: Double { min(1, max(0, value / max(1, target))) }
    var body: some View {
        Button { withAnimation(reduced ? nil : .spring(response: 0.6, dampingFraction: 0.7)) { showRemaining.toggle() } } label: {
            ZStack {
                Circle().fill(tint.opacity(0.12)).blur(radius: 22).padding(-10)
                Circle().stroke(tint.opacity(0.10), lineWidth: 1).padding(2)
                Circle().stroke(tint.opacity(0.10), lineWidth: 1).padding(18)
                Circle().fill(.ultraThinMaterial).padding(32)
                    .shadow(color: tint.opacity(0.15), radius: 24, y: 16)
                Circle().stroke(.white.opacity(0.45), lineWidth: 1).padding(32)
                Circle().stroke(tint.opacity(0.13), lineWidth: 13).padding(22)
                Circle().trim(from: 0, to: progress).stroke(AngularGradient(colors: [tint.opacity(0.4), tint, Color.plateCarb, tint], center: .center), style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(-90)).padding(22)
                Circle().fill(tint.gradient).frame(width: 18, height: 18).offset(y: -108).rotationEffect(.degrees(progress * 360))
                    .shadow(color: tint.opacity(0.4), radius: 8)
                VStack(spacing: 5) {
                    Image(systemName: showRemaining ? "sparkles" : "flame.fill").font(.title3).foregroundStyle(tint).symbolEffect(.bounce, value: showRemaining)
                    Text(Int(showRemaining ? abs(target-value) : value), format: .number)
                        .font(.system(size: 45, weight: .bold, design: .rounded)).tracking(-2).contentTransition(.numericText()).minimumScaleFactor(0.5)
                    Text(showRemaining ? (value > target ? "KCAL OVER" : "KCAL LEFT") : "KCAL EATEN").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                    Text("of \(Int(target)) today").font(.caption).foregroundStyle(.secondary).padding(.top, 3)
                }.padding(45)
            }.frame(width: 260, height: 260)
                .rotation3DEffect(.degrees(reduced ? 0 : Double(tilt.width / 12)), axis: (x: 0, y: 1, z: 0))
                .rotation3DEffect(.degrees(reduced ? 0 : Double(-tilt.height / 12)), axis: (x: 1, y: 0, z: 0))
        }.buttonStyle(PlatePress())
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { tilt = CGSize(width: max(-70,min(70,$0.translation.width)), height: max(-70,min(70,$0.translation.height))) }.onEnded { _ in withAnimation(reduced ? nil : .spring(response: 0.6, dampingFraction: 0.5)) { tilt = .zero } })
            .animation(reduced ? nil : .spring(response: 0.8), value: progress)
            .accessibilityLabel("\(Int(value)) of \(Int(target)) calories. Tap to switch between eaten and remaining.")
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
                        .overlay(alignment: .leading) { Capsule().fill(tint.gradient).frame(width: geo.size.width * min(1,max(0,value/max(1,target)))) }
                }.frame(height: 5)
                if expanded { Text("\(Int(max(0,target-value))) g left\nTarget \(Int(target)) g").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).transition(.opacity.combined(with: .move(edge: .top))) }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.055), in: .rect(cornerRadius: 23)).overlay(RoundedRectangle(cornerRadius: 23).stroke(tint.opacity(0.12)))
        }.buttonStyle(PlatePress()).sensoryFeedback(.selection, trigger: expanded).accessibilityLabel("\(name), \(Int(value)) of \(Int(target)) grams").accessibilityHint("Show remaining grams")
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
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36).background(Color.plateMint.opacity(0.08), in: .circle) }.accessibilityLabel("Previous month")
                Spacer(minLength: 2)
                Text(month, format: .dateTime.month(.wide).year()).font(.system(.headline, design: .rounded)).contentTransition(.numericText())
                Spacer(minLength: 2)
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36).background(Color.plateMint.opacity(0.08), in: .circle) }.accessibilityLabel("Next month").disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
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
                            Text("\(cell-leading+1)").font(.system(.subheadline, design: .rounded, weight: active ? .bold : .medium)).frame(maxWidth: .infinity).frame(height: 36).background(active ? Color.plateMint.opacity(0.25) : .clear, in: .circle).overlay(Circle().stroke(calendar.isDateInToday(day) ? Color.plateMint : .clear))
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
