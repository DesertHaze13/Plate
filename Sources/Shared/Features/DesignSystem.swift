import SwiftUI
import Charts
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
    let nutrient: TrackedNutrient
    var name: String { nutrient.title }
    var warningFraction = 0.85
    private var progress: TargetProgress { TargetProgress(nutrient: nutrient, amount: value, target: target, warningFraction: warningFraction) }
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
                Label(progress.state == .under ? "\(targetDifference(progress.remaining, unit: "g")) left" : progress.state.label, systemImage: progress.state.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(progress.state == .under ? tint : progress.state.tint).fixedSize(horizontal: false, vertical: true)
                if expanded { Text("\(targetDifference(progress.state == .over ? progress.excess : progress.remaining, unit: "g")) \(progress.state == .over ? "over" : "left")\nTarget \(Int(target)) g").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).transition(.opacity.combined(with: .move(edge: .top))) }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.055), in: .rect(cornerRadius: 23)).overlay(RoundedRectangle(cornerRadius: 23).stroke(tint.opacity(0.12)))
        }.buttonStyle(PlatePress()).sensoryFeedback(.selection, trigger: expanded).accessibilityLabel("\(name), \(value.formatted()) of \(target.formatted()) grams. \(progress.state.label).").accessibilityHint("Show remaining grams")
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


extension TargetFillState {
    var tint: Color { switch self { case .under, .unset: .secondary; case .near: .orange; case .met: .plateMint; case .over: .orange } }
    var symbol: String { switch self { case .under: "circle.dashed"; case .near: "exclamationmark.circle.fill"; case .met: "checkmark.circle.fill"; case .over: "exclamationmark.triangle.fill"; case .unset: "minus.circle" } }
    var label: String { switch self { case .under: "Masih tersedia"; case .near: "Hampir penuh"; case .met: "Target tercapai"; case .over: "Melebihi target"; case .unset: "Belum diatur" } }
}
func targetDifference(_ amount: Double, unit: String) -> String {
    if amount > 0 && amount < 0.1 { return "Less than 0.1 \(unit)" }
    return "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
}
struct TargetWarningStrip: View {
    let progress: [TargetProgress]
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var pulse = false
    private var flagged: [TargetProgress] { progress.filter { $0.state == .over || $0.state == .near || $0.state == .met } }
    private var over: Bool { flagged.contains { $0.state == .over } }
    var body: some View {
        if !flagged.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: over ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .font(.title2).scaleEffect(pulse ? 1.12 : 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(over ? "Perhatian, asupan melewati target" : "Perhatikan target harian").font(.system(.subheadline, design: .rounded, weight: .bold))
                    ForEach(compact ? flagged.filter { $0.state == .over } : flagged) { item in
                        Text("\(item.nutrient.indonesianTitle) · \(item.indonesianDifference)").font(.caption.weight(.semibold))
                    }
                    if over && !compact { Text("Bandingkan dengan target harianmu saat memilih porsi berikutnya.").font(.caption2) }
                }
                Spacer(minLength: 0)
            }.foregroundStyle(over ? Color(red: 0.9, green: 0.29, blue: 0.2) : .orange)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(over ? Color.red.opacity(0.10) : Color.orange.opacity(0.10), in: .rect(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(over ? Color.red.opacity(0.35) : Color.orange.opacity(0.3)))
                .accessibilityElement(children: .combine)
                .task(id: flagged.map(\.state)) {
                    guard !reduced else { return }
                    withAnimation(.easeInOut(duration: 0.65).repeatCount(4, autoreverses: true)) { pulse = true }
                    try? await Task.sleep(for: .seconds(3)); pulse = false
                }
        }
    }
}
struct TargetWarningsCard: View {
    let eaten: Nutrients
    let targets: Targets
    var projected = false
    var dayLabel = "Hari ini"
    private var progress: [TargetProgress] { TargetProgress.all(eaten: eaten, targets: targets) }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                PlateIconTile(symbol: "checklist", tint: .plateMint, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(projected ? "Setelah makan ini" : "Cek target harian").font(.system(.headline, design: .rounded))
                    Text(projected ? "\(dayLabel) · perkiraan total" : "\(dayLabel) · total tercatat").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ForEach(progress) { item in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.nutrient.indonesianTitle).font(.subheadline.bold())
                        Spacer()
                        Label(item.state == .met && item.nutrient == .calories ? "Dalam rentang target" : item.state.label, systemImage: item.state.symbol).font(.caption.weight(.semibold)).foregroundStyle(item.state.tint)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(item.amount.formatted(.number.precision(.fractionLength(0...1)))) / \(item.target.formatted(.number.precision(.fractionLength(0...1)))) \(item.nutrient.unit)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Text(detail(item)).font(.caption.weight(.medium)).foregroundStyle(item.state == .under ? Color.secondary : item.state.tint)
                    }
                    GeometryReader { geo in
                        Capsule().fill(item.state.tint.opacity(0.10)).overlay(alignment: .leading) { Capsule().fill(item.state == .under ? Color.plateMint : item.state.tint).frame(width: geo.size.width * min(1,max(0,item.fraction))) }
                    }.frame(height: 4)
                }.accessibilityElement(children: .combine)
            }
            Text("Peringatan mengikuti target pribadi. Mulai mendekati target pada \(Int(targets.warningFraction * 100))%. Kalori mengikuti toleransi yang kamu atur.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(22).plateCard()
    }
    private func detail(_ item: TargetProgress) -> String { item.indonesianDifference }
}


private struct PieContribution: Identifiable {
    let meal: Meal
    let item: FoodItem
    let energy: Double
    var id: String { meal.id + "/" + item.id }
}
struct PlatePieExplorer: View {
    let meals: [Meal]
    let targets: Targets
    var loggedDays = 1
    var isPeriod = false
    var title = "Explore your plate"
    @Environment(PlateModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var mode = 0
    @State private var angle: Double?
    @State private var selectedID: String?
    @State private var showAll = false
    @State private var detailMeal: Meal?
    private var totals: Nutrients { meals.reduce(.zero) { $0 + $1.total } }
    private var slices: [PlatePieSlice] { mode == 0 ? PieBreakdown.macros(totals) : PieBreakdown.foodCategories(meals) }
    private var totalEnergy: Double { slices.reduce(0) { $0 + $1.calories } }
    private var selected: PlatePieSlice? { slices.first { $0.id == selectedID } }
    private var contributions: [PieContribution] {
        guard let selected else { return [] }
        return meals.flatMap { meal in meal.items.compactMap { item -> PieContribution? in
            let energy: Double
            if let nutrient = selected.nutrient { energy = nutrient.amount(in: item.total) * (nutrient == .fat ? 9 : 4) }
            else { energy = item.category == selected.category ? item.total.calories : 0 }
            guard energy.isFinite, energy > 0 else { return nil }
            return PieContribution(meal: meal, item: item, energy: energy)
        } }.sorted { $0.energy > $1.energy }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(title).font(.system(.title3, design: .rounded, weight: .bold)); Spacer(); Image(systemName: "chart.pie.fill").foregroundStyle(Color.plateFat) }
            PlateSegmentedControl(options: ["Macros", "Food categories"], selection: $mode)
            if totalEnergy > 0 { pie }
            else { ContentUnavailableView("No slices yet", systemImage: "chart.pie", description: Text("Log a meal to explore its nutrition and food categories.")).frame(height: 200) }
            ForEach(slices) { slice in legendRow(slice) }
            if let selected {
                detail(selected).transition(.opacity.combined(with: .move(edge: .top)))
            } else if totalEnergy > 0 { Text("Tap a slice or category to explore its foods.").font(.caption).foregroundStyle(.secondary) }
            Text(isPeriod ? "Period totals across \(loggedDays) logged \(loggedDays == 1 ? "day" : "days"). Macro shares use 4/4/9 kcal per gram; food categories use logged calories." : "Macro shares use 4/4/9 kcal per gram; food categories use logged calories. These totals may differ from label calories.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(22).plateCard()
            .animation(reduced ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: selectedID)
            .sensoryFeedback(.selection, trigger: selectedID)
            .onChange(of: angle) { _, value in if let value { selectedID = PieBreakdown.slice(at: value, in: slices)?.id } }
            .onChange(of: mode) { _, _ in angle = nil; selectedID = nil; showAll = false }
            .onChange(of: slices) { _, values in if let selectedID, !values.contains(where: { $0.id == selectedID }) { self.selectedID = nil }; angle = nil }
            .sheet(item: $detailMeal) { MealDetailView(meal: $0).environment(model) }
    }
    private var pie: some View {
        Chart(slices.filter { $0.calories > 0 }) { slice in
            SectorMark(angle: .value("Energy", slice.calories), innerRadius: .ratio(0.61), outerRadius: .ratio(selectedID == slice.id ? 1 : 0.91), angularInset: 3)
                .cornerRadius(5).foregroundStyle(color(slice).gradient)
                .opacity(selectedID == nil || selectedID == slice.id ? 1 : 0.35)
                .accessibilityLabel(slice.title).accessibilityValue("\(slice.calories.formatted(.number.precision(.fractionLength(0...1)))) kcal")
        }.chartLegend(.hidden).chartAngleSelection(value: $angle)
            .chartGesture { proxy in
                DragGesture(minimumDistance: 0)
                    .onChanged { proxy.selectAngleValue(at: proxy.angle(at: $0.location)) }
                    .onEnded { proxy.selectAngleValue(at: proxy.angle(at: $0.location)) }
            }
            .frame(height: 235)
            .overlay {
                VStack(spacing: 4) {
                    Text(selected?.title ?? "All categories").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(selected.map { "\(Int(($0.calories / (totalEnergy > 0 ? totalEnergy : 1) * 100).rounded()))%" } ?? totalEnergy.formatted(.number.precision(.fractionLength(0)))).font(.system(size: 32, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    Text(selected == nil ? "kcal in this chart" : "of chart energy").font(.caption2).foregroundStyle(.secondary)
                }.frame(width: 140).multilineTextAlignment(.center).allowsHitTesting(false).accessibilityHidden(true)
            }
    }
    private func legendRow(_ slice: PlatePieSlice) -> some View {
        Button { select(slice) } label: {
            HStack(spacing: 10) {
                Circle().fill(color(slice).gradient).frame(width: 11, height: 11)
                Text(slice.title).font(.subheadline.weight(selectedID == slice.id ? .bold : .medium))
                Spacer(minLength: 0)
                Text("\(Int((slice.calories / (totalEnergy > 0 ? totalEnergy : 1) * 100).rounded()))%").font(.subheadline.bold().monospacedDigit())
                Image(systemName: selectedID == slice.id ? "chevron.up" : "chevron.right").font(.caption2.bold())
            }.padding(12).background(selectedID == slice.id ? color(slice).opacity(0.12) : .primary.opacity(0.025), in: .rect(cornerRadius: 16))
        }.buttonStyle(PlatePress()).foregroundStyle(.primary).accessibilityLabel("Explore \(slice.title)").accessibilityAddTraits(selectedID == slice.id ? .isSelected : [])
    }
    private func detail(_ slice: PlatePieSlice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(slice.title).font(.system(.title2, design: .rounded, weight: .bold))
                Spacer()
                Text("\(slice.calories.formatted(.number.precision(.fractionLength(0...1)))) kcal").font(.subheadline.bold()).foregroundStyle(color(slice))
            }
            if let nutrient = slice.nutrient, let grams = slice.grams {
                let average = grams / Double(max(1,loggedDays))
                let progress = TargetProgress(nutrient: nutrient, amount: average, target: nutrient.amount(in: targets.nutrients), warningFraction: targets.warningFraction)
                Text("\(grams.formatted(.number.precision(.fractionLength(0...1)))) g \(isPeriod ? "in this period" : "today")").font(.headline)
                Label("\(isPeriod ? "Daily average" : "Today"): \(average.formatted(.number.precision(.fractionLength(0...1)))) / \(progress.target.formatted(.number.precision(.fractionLength(0...1)))) g · \(progress.state.label)", systemImage: progress.state.symbol).font(.caption).foregroundStyle(progress.state.tint).fixedSize(horizontal: false, vertical: true)
            }
            Text("Foods contributing to this slice").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(showAll ? contributions : Array(contributions.prefix(5))) { contribution in
                Button { detailMeal = contribution.meal } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(contribution.item.name).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading); Text("\(contribution.meal.timestamp.formatted(.dateTime.month(.abbreviated).day())) · \(contribution.meal.type.rawValue.capitalized)").font(.caption2).foregroundStyle(.secondary) }
                        Spacer(minLength: 8)
                        Text("\(contribution.energy.formatted(.number.precision(.fractionLength(0...1)))) kcal").font(.caption.monospacedDigit())
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }.padding(.vertical, 6)
                }.buttonStyle(PlatePress()).foregroundStyle(.primary).accessibilityHint("Open this meal to inspect its food items")
            }
            if contributions.isEmpty { Text("No logged food contributes to this category yet.").font(.caption).foregroundStyle(.secondary) }
            if contributions.count > 5 { Button(showAll ? "Show top five" : "Show all \(contributions.count) foods") { showAll.toggle() }.font(.caption.bold()).buttonStyle(PlatePress()) }
            Button("Show all slices") { selectedID = nil; angle = nil }.font(.caption.bold()).buttonStyle(PlatePress())
        }.padding(16).background(color(slice).opacity(0.06), in: .rect(cornerRadius: 22))
    }
    private func select(_ slice: PlatePieSlice) { angle = nil; selectedID = selectedID == slice.id ? nil : slice.id; showAll = false }
    private func color(_ slice: PlatePieSlice) -> Color {
        if let nutrient = slice.nutrient { switch nutrient { case .protein: return .plateMint; case .carbs: return .plateCarb; case .fat: return .plateFat; case .calories: return .teal } }
        switch slice.category { case .protein: return .teal; case .carbs: return .orange; case .fats: return .purple; case .vegetables: return .green; case .fruit: return .pink; case .dairy: return .blue; case .drinks: return .cyan; case .snacks: return .brown; case .sauces: return .red; case nil: return .secondary }
    }
}

/// Thin, selectable macro ring. Only its decorative halo moves; data stays put for accurate taps.
struct SlimPlateHero: View {
    let meals: [Meal]
    let targets: Targets
    var dayTitle = "TODAY"
    var energyTitle = "Energi hari ini"
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var angle: Double?
    @State private var selectedID: String?
    @State private var glow = false
    @State private var showDetails = false
    private var totals: Nutrients { meals.reduce(.zero) { $0 + $1.total } }
    private var slices: [PlatePieSlice] { PieBreakdown.macros(totals) }
    private var selected: PlatePieSlice? { slices.first { $0.id == selectedID } }
    private var energy: Double { slices.reduce(0) { $0 + $1.calories } }
    private func tint(_ slice: PlatePieSlice) -> Color {
        switch slice.nutrient { case .protein: .plateMint; case .carbs: .plateCarb; default: .plateFat }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(dayTitle) / YOUR PLATE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button { showDetails = true } label: { Image(systemName: "arrow.up.right").font(.subheadline.bold()).frame(width: 36, height: 36).background(.white.opacity(0.1), in: .circle) }.buttonStyle(PlatePress()).accessibilityLabel("Lihat rincian makanan dan kategori")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) { ring; readout.frame(maxWidth: .infinity, alignment: .leading) }
                VStack(alignment: .leading, spacing: 18) { ring.frame(maxWidth: .infinity); readout }
            }
            HStack(spacing: 8) { ForEach(slices) { slice in macroButton(slice) } }
            Text(energy > 0 ? "Ketuk irisan untuk melihat makro · Rincian ↗" : "Catat makanan untuk mengisi diagrammu.").font(.caption2).foregroundStyle(.white.opacity(0.55))
        }.padding(22).foregroundStyle(.white)
            .background {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [Color(red: 0.10, green: 0.28, blue: 0.25), Color(red: 0.045, green: 0.14, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(Color.plateMint.opacity(glow ? 0.16 : 0.06)).frame(width: 260, height: 260).blur(radius: 35).offset(x: 100, y: -110).scaleEffect(glow ? 1.15 : 0.85)
                }.clipShape(.rect(cornerRadius: 34))
            }
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.13)))
            .shadow(color: Color.plateMint.opacity(0.16), radius: 24, y: 12)
            .environment(\.colorScheme, .dark)
            .animation(reduced ? nil : .spring(response: 0.45, dampingFraction: 0.78), value: selectedID)
            .animation(reduced ? nil : .smooth(duration: 0.6), value: totals)
            .onChange(of: angle) { _, value in if let value { selectedID = PieBreakdown.slice(at: value, in: slices)?.id } }
            .onChange(of: slices) { _, values in angle = nil; if let selectedID, !values.contains(where: { $0.id == selectedID && $0.calories > 0 }) { self.selectedID = nil } }
            .sensoryFeedback(.selection, trigger: selectedID)
            .onAppear { if !reduced { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { glow = true } } }
            .onChange(of: reduced) { _, value in if value { glow = false } }
            .sheet(isPresented: $showDetails) {
                NavigationStack {
                    ScrollView { PlatePieExplorer(meals: meals, targets: targets).padding(20) }
                        .navigationTitle("Rincian piringmu")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { showDetails = false } } }
                }.frame(minWidth: 320, minHeight: 460)
            }
    }
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.07), lineWidth: 11).padding(12)
            if energy > 0 {
                Chart(slices.filter { $0.calories > 0 }) { slice in
                    SectorMark(angle: .value("Energi", slice.calories), innerRadius: .ratio(0.81), outerRadius: .ratio(selectedID == slice.id ? 1 : 0.93), angularInset: 3)
                        .cornerRadius(4).foregroundStyle(tint(slice).gradient)
                        .opacity(selectedID == nil || selectedID == slice.id ? 1 : 0.3)
                }.chartLegend(.hidden).chartAngleSelection(value: $angle)
                    .chartGesture { proxy in DragGesture(minimumDistance: 0).onChanged { proxy.selectAngleValue(at: proxy.angle(at: $0.location)) }.onEnded { proxy.selectAngleValue(at: proxy.angle(at: $0.location)) } }
            }
            VStack(spacing: 3) {
                Text(selected.map { "\(Int(($0.calories / max(1,energy) * 100).rounded()))%" } ?? "\(meals.count)").font(.system(size: 29, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(selected == nil ? "meals" : "energi makro").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }.allowsHitTesting(false).accessibilityHidden(true)
        }.frame(width: 148, height: 148)
    }
    private var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selected?.nutrient?.indonesianTitle ?? energyTitle).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.65))
            Text(selected.map { "\(($0.grams ?? 0).formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "\(Int(totals.calories))").font(.system(size: 35, weight: .bold, design: .rounded)).contentTransition(.numericText()).minimumScaleFactor(0.7).lineLimit(1)
            if let nutrient = selected?.nutrient {
                let progress = TargetProgress(nutrient: nutrient, amount: nutrient.amount(in: totals), target: nutrient.amount(in: targets.nutrients), warningFraction: targets.warningFraction)
                Text(progress.indonesianDifference).font(.caption.weight(.semibold)).foregroundStyle(progress.state == .over ? Color.plateCarb : .white.opacity(0.8))
            } else { Text("/ \(Int(targets.nutrients.calories)) kcal target").font(.caption).foregroundStyle(.white.opacity(0.65)) }
            if selected != nil { Button("Lihat total") { selectedID = nil; angle = nil }.font(.caption).foregroundStyle(Color.plateMint) }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func macroButton(_ slice: PlatePieSlice) -> some View {
        Button { selectedID = selectedID == slice.id ? nil : slice.id; angle = nil } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) { Circle().fill(tint(slice)).frame(width: 5, height: 5); Text(slice.nutrient?.indonesianTitle ?? slice.title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65) }
                Text("\(Int(slice.grams ?? 0)) g").font(.system(.subheadline, design: .rounded, weight: .bold)).contentTransition(.numericText())
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(tint(slice).opacity(selectedID == slice.id ? 0.23 : 0.08), in: .rect(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(tint(slice).opacity(selectedID == slice.id ? 0.65 : 0.15)))
        }.buttonStyle(PlatePress()).accessibilityLabel("\(slice.nutrient?.indonesianTitle ?? slice.title), \(Int(slice.grams ?? 0)) gram").accessibilityAddTraits(selectedID == slice.id ? .isSelected : [])
    }
}
