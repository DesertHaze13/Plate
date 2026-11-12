import SwiftUI
import Charts
import PlateCore

struct HistoryView: View {
    @Environment(PlateModel.self) private var model
    @State private var date = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var selected: Meal?
    @State private var chartDate: Date?
    private var meals: [Meal] { model.store.meals.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) } }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PlatePageTitle(eyebrow: "YOUR JOURNEY", title: "Every day tells a story.", subtitle: "Revisit the meals that keep you moving.")
                    weekStrip
                    dayTotalCard
                    calorieComparison
                    let wide = geometry.size.width > 800
                    let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
                    layout {
                        PlateCalendar(selection: $date).frame(maxWidth: wide ? 360 : .infinity)
                        VStack(alignment: .leading, spacing: 18) {
                            HStack { Text(date, format: .dateTime.month(.wide).day()); Spacer(); Text("\(meals.count) \(meals.count == 1 ? "meal" : "meals")").foregroundStyle(.secondary) }.font(.system(.headline, design: .rounded))
                            if meals.isEmpty { ContentUnavailableView("A quiet plate", systemImage: "calendar", description: Text("No meals were logged on this day.")).frame(maxWidth: .infinity).padding(.vertical, 30).plateCard() }
                            ForEach(meals) { meal in Button { selected = meal } label: { MealCard(meal: meal) }.buttonStyle(PlatePress()) }
                            if !meals.isEmpty { DailySummaryCard(meals: meals, target: model.store.targets) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }
        }.navigationTitle("History").background(PlateBackground(status: .calm))
            .sheet(item: $selected) { MealDetailView(meal: $0).environment(model) }
    }
    private var target: Double { model.store.targets.capped(at: model.store.account.profile.calorieCap).nutrients.calories }
    private func kcal(on day: Date) -> Double { HistoryMath.totals(model.store.meals, on: day).calories }
    private func hasMeals(on day: Date) -> Bool { model.store.meals.contains { Calendar.current.isDate($0.timestamp, inSameDayAs: day) } }
    private func tint(for value: Double) -> Color {
        let state = DailyGuidance(eaten: .init(calories: value), target: model.store.targets.capped(at: model.store.account.profile.calorieCap)).state
        return state == .calm ? Color.plateAccent : state.color
    }
    /// The selected day's total, against the target and the day before.
    private var dayTotalCard: some View {
        let total = kcal(on: date)
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        let previous = kcal(on: previousDay)
        let gap = total - target
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(meals.isEmpty ? "—" : Int(total.rounded()).formatted()).font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.5)
                    .contentTransition(.numericText(value: total)).foregroundStyle(meals.isEmpty ? Color.secondary : tint(for: total))
                Text(meals.isEmpty ? "No meals logged" : "kcal logged").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if !meals.isEmpty {
                    Text(abs(gap) <= model.store.targets.tolerance ? "On target" : "\(Int(abs(gap).rounded())) \(gap < 0 ? "under" : "over")")
                        .font(.caption.weight(.semibold)).foregroundStyle(tint(for: total))
                        .padding(.horizontal, 10).padding(.vertical, 6).background(tint(for: total).opacity(0.12), in: .capsule)
                }
            }
            GeometryReader { geo in
                Capsule().fill(Color.primary.opacity(0.07))
                    .overlay(alignment: .leading) { Capsule().fill(tint(for: total).gradient).frame(width: geo.size.width * min(1, total / max(1, target))) }
                    .overlay(alignment: .trailing) { if total > target { Capsule().fill(Color.red.opacity(0.35)).frame(width: geo.size.width * min(0.3, (total - target) / max(1, target))) } }
            }.frame(height: 8)
            HStack {
                Text("Target \(Int(target.rounded())) kcal").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if hasMeals(on: previousDay) && !meals.isEmpty {
                    let change = total - previous
                    Label("\(change >= 0 ? "+" : "−")\(Int(abs(change).rounded())) vs \(previousDay.formatted(.dateTime.weekday(.abbreviated)))", systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).contentTransition(.numericText(value: change))
                }
            }
        }.padding(20).plateCard()
            .animation(reduced ? nil : .spring(response: 0.5, dampingFraction: 0.82), value: date)
            .accessibilityElement(children: .combine)
    }
    private var weekStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach((0..<14).reversed(), id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date.now) ?? .now
                    let active = Calendar.current.isDate(day, inSameDayAs: date)
                    let logged = hasMeals(on: day)
                    let total = kcal(on: day)
                    Button { withAnimation(reduced ? nil : .smooth) { date = day } } label: {
                        VStack(spacing: 7) {
                            Text(day, format: .dateTime.weekday(.abbreviated)).font(.caption2.weight(.semibold))
                            Text(day, format: .dateTime.day()).font(.system(.title3, design: .rounded, weight: .bold))
                            // Bar height is the day's calories relative to the target; the tick marks the target.
                            ZStack(alignment: .bottom) {
                                Capsule().fill(Color.primary.opacity(0.06)).frame(width: 8, height: 46)
                                Capsule().fill(logged ? tint(for: total).gradient : Color.clear.gradient).frame(width: 8, height: logged ? max(4, 46 * min(1.25, total / max(1, target)) / 1.25) : 0)
                                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 14, height: 1.5).offset(y: -46 / 1.25)
                            }.frame(height: 46)
                            Text(logged ? (total >= 1000 ? String(format: "%.1fk", total / 1000) : "\(Int(total))") : "–")
                                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(logged ? tint(for: total) : .secondary)
                        }.frame(width: 56).padding(.vertical, 12).background(active ? Color.plateAccent.opacity(0.22) : Color.plateAccent.opacity(0.05), in: .rect(cornerRadius: 20))
                    }.buttonStyle(PlatePress()).foregroundStyle(.primary)
                        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(logged ? "\(Int(total)) calories" : "nothing logged")")
                        .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }.defaultScrollAnchor(.trailing)
    }

    private var comparisonDays: [DayPoint] {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
        return (0..<7).compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DayPoint(date: day, nutrients: HistoryMath.totals(model.store.meals, on: day))
        }
    }
    private var calorieComparison: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Day by day").font(.headline)
                Spacer()
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 44) }.accessibilityLabel("Previous week")
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 44) }.accessibilityLabel("Next week")
                    .disabled(comparisonDays.contains { Calendar.current.isDateInToday($0.date) } || date > .now)
            }.buttonStyle(.plain)
            Chart(comparisonDays) { point in
                BarMark(x: .value("Day", point.date, unit: .day), y: .value("Calories", point.nutrients.calories))
                    .foregroundStyle(Calendar.current.isDate(point.date, inSameDayAs: date) ? Color.plateAccent : Color.plateAccent.opacity(0.4))
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        if model.store.meals.contains(where: { Calendar.current.isDate($0.timestamp, inSameDayAs: point.date) }) {
                            Text(point.nutrients.calories, format: .number.precision(.fractionLength(0))).font(.system(size: 9, weight: .semibold)).monospacedDigit()
                        }
                    }
                    .accessibilityLabel(point.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .accessibilityValue(model.store.meals.contains(where: { Calendar.current.isDate($0.timestamp, inSameDayAs: point.date) }) ? "\(Int(point.nutrients.calories)) calories logged" : "No meals logged")
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .chartYAxisLabel("kcal")
            .chartYScale(domain: 0...max(100, (comparisonDays.map { $0.nutrients.calories }.max() ?? 0) * 1.2))
            .chartXSelection(value: $chartDate)
            .frame(height: 190)
            .onChange(of: chartDate) { _, value in
                guard let value, let closest = comparisonDays.min(by: { abs($0.date.timeIntervalSince(value)) < abs($1.date.timeIntervalSince(value)) }) else { return }
                date = closest.date
            }
            Text("Select a day to see its meals. Totals include logged food only; blank days have no meals logged.").font(.caption).foregroundStyle(.secondary)
        }.padding(22).plateCard()
    }
    private func moveWeek(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: offset * 7, to: date) { date = min(next, .now); chartDate = nil }
    }

}
/// Food eaten against energy burned (from Apple Health), with what that means for your weight.
struct EnergyBalanceCard: View {
    let range: Int
    let grown: Bool
    @Environment(PlateModel.self) private var model
    private struct Point: Identifiable { let date: Date; let eaten: Double; let burned: Double; let logged: Bool; var id: Date { date } }
    private var points: [Point] {
        model.energyDays.suffix(range).map { day in
            let meals = model.store.meals.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: day.date) }
            return Point(date: day.date, eaten: meals.reduce(0) { $0 + $1.total.calories }, burned: day.burned, logged: !meals.isEmpty)
        }
    }
    /// Finished days with both food and Health data. Today is left out because it isn't over.
    private var complete: [Point] { points.filter { $0.logged && $0.burned > 0 && !Calendar.current.isDateInToday($0.date) } }
    private var averageGap: Double { complete.isEmpty ? 0 : complete.reduce(0) { $0 + ($1.eaten - $1.burned) } / Double(complete.count) }
    private var averageBurn: Double { complete.isEmpty ? 0 : complete.reduce(0) { $0 + $1.burned } / Double(complete.count) }
    private var actualKgPerWeek: Double? {
        let start = Calendar.current.date(byAdding: .day, value: -max(range, 14), to: .now) ?? .now
        let weights = model.store.account.weights.filter { $0.timestamp >= start }.sorted { $0.timestamp < $1.timestamp }
        guard let first = weights.first, let last = weights.last, last.timestamp.timeIntervalSince(first.timestamp) > 6 * 86400 else { return nil }
        return (last.kilograms - first.kilograms) / (last.timestamp.timeIntervalSince(first.timestamp) / (7 * 86400))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Energy balance").font(.headline)
            Text("Food eaten · line shows energy burned from Apple Health").font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Eaten", grown ? point.eaten : 0)).foregroundStyle(Color.plateAccent.gradient).cornerRadius(4)
                }
                ForEach(points.filter { $0.burned > 0 }) { point in
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Burned", grown ? point.burned : 0)).foregroundStyle(Color.orange).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value("Burned", grown ? point.burned : 0)).foregroundStyle(Color.orange).symbolSize(28)
                }
            }.chartYAxisLabel("kcal").frame(height: 190)
                .accessibilityLabel("Calories eaten each day compared with energy burned over the past \(range) days")
            if complete.count < 3 {
                Label("Log food on more days to compare recorded intake with estimated burn.", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
            } else {
                insight(symbol: averageGap < 0 ? "arrow.down.right" : "arrow.up.right", tint: averageGap < 0 ? .plateAccent : .plateCarb,
                        title: "\(Int(abs(averageGap).rounded())) kcal a day \(averageGap < 0 ? "below" : "above") your burn",
                        detail: "Across \(complete.count) days with logs. Food logs may be incomplete, and Health energy is an estimate; this does not predict weight change.")
                let assumed = NutritionCalculator.breakdown(for: model.store.account.profile).maintenance
                if abs(averageBurn - assumed) > 150 {
                    insight(symbol: "scope", tint: .plateFat, title: "Health saw \(Int(averageBurn.rounded())) kcal burned a day",
                            detail: "Your target assumes \(Int(assumed.rounded())). Switch Settings › Activity to your Apple Health data to match.")
                }
                if let actual = actualKgPerWeek {
                    insight(symbol: "scalemass", tint: .plateAccent, title: "Scale: \(actual < 0 ? "−" : "+")\(String(format: "%.2f", abs(actual))) kg a week",
                            detail: "Observed weight trend from recorded measurements. Hydration and measurement timing can affect it.")
                }
            }
        }.padding(22).plateCard()
    }
    private func insight(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.subheadline.bold()).foregroundStyle(tint).frame(width: 30, height: 30).background(tint.opacity(0.13), in: .circle)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
private struct DayPoint: Identifiable {
    let date: Date
    let nutrients: Nutrients
    var id: Date { date }
}
struct ProgressViewScreen: View {
    @Environment(PlateModel.self) private var model
    @State private var range = 7
    @State private var selectedDay: Date?
    @State private var weight = ""
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var days: [DayPoint] {
        (0..<range).reversed().compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: .now)) else { return nil }
            return DayPoint(date: day, nutrients: HistoryMath.totals(model.store.meals, on: day))
        }
    }
    private var loggedDays: [DayPoint] { days.filter { point in model.store.meals.contains { Calendar.current.isDate($0.timestamp, inSameDayAs: point.date) } } }
    private var average: Nutrients { loggedDays.isEmpty ? .zero : loggedDays.reduce(.zero) { $0 + $1.nutrients }.scaled(by: 1/Double(loggedDays.count)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlatePageTitle(eyebrow: "THE BIGGER PICTURE", title: "Small steps. Real progress.", subtitle: "Explore your rhythm, one day at a time.")
                PlateSegmentedControl(options: ["Week", "Month"], selection: Binding(get: { range == 7 ? 0 : 1 }, set: { range = $0 == 0 ? 7 : 30; selectedDay = nil })).frame(maxWidth: 320)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 22, alignment: .top)], alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    stat("On-target streak", "\(HistoryMath.streak(meals: model.store.meals, targets: model.store.targets)) days")
                    stat("Protein average", "\(Int(average.protein)) g")
                }
                chartCard("Calories", subtitle: "Daily intake · line shows your current target") {
                    Chart {
                        ForEach(days) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Calories", grown ? point.nutrients.calories : 0)).foregroundStyle(Color.plateAccent.gradient).cornerRadius(4)
                        }
                        RuleMark(y: .value("Target", model.store.targets.capped(at: model.store.account.profile.calorieCap).nutrients.calories)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4]))

                        if let selectedDay, let point = days.min(by: { abs($0.date.timeIntervalSince(selectedDay)) < abs($1.date.timeIntervalSince(selectedDay)) }) {
                            RuleMark(x: .value("Selected", point.date, unit: .day)).foregroundStyle(Color.plateCarb).annotation(position: .top) { Text("\(Int(point.nutrients.calories)) kcal").font(.caption.bold()).padding(7).background(.regularMaterial, in: .capsule) }
                        }
                    }.chartXSelection(value: $selectedDay).chartYAxisLabel("kcal").accessibilityLabel("Daily calorie intake for the past \(range) days, compared with your current target of \(Int(model.store.targets.capped(at: model.store.account.profile.calorieCap).nutrients.calories)) calories")
                }
                chartCard("Protein consistency", subtitle: "Grams each day · keep showing up") {
                    Chart(days) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Protein", grown ? point.nutrients.protein : 0)).foregroundStyle(point.nutrients.protein >= model.store.targets.nutrients.protein ? Color.plateAccent : Color.plateAccent.opacity(0.35)).cornerRadius(4)
                        RuleMark(y: .value("Protein target", model.store.targets.nutrients.protein)).lineStyle(StrokeStyle(dash: [4,4])).foregroundStyle(.secondary)
                    }.chartYAxisLabel("g").accessibilityLabel("Protein consistency, target \(Int(model.store.targets.nutrients.protein)) grams daily")
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Average macro split").font(.headline)
                    if loggedDays.isEmpty { Text("Log your first meal to see your macro balance.").foregroundStyle(.secondary) }
                    else {
                        Chart {
                            SectorMark(angle: .value("Protein calories", average.protein*4), innerRadius: .ratio(0.68), angularInset: 3).foregroundStyle(Color.plateAccent)
                            SectorMark(angle: .value("Carb calories", average.carbs*4), innerRadius: .ratio(0.68), angularInset: 3).foregroundStyle(Color.plateCarb)
                            SectorMark(angle: .value("Fat calories", average.fat*9), innerRadius: .ratio(0.68), angularInset: 3).foregroundStyle(Color.plateFat)
                        }.frame(height: 170).accessibilityLabel("Average macros on logged days: \(Int(average.protein)) grams protein, \(Int(average.carbs)) grams carbs, \(Int(average.fat)) grams fat")
                        Text("\(Int(average.protein)) g protein · \(Int(average.carbs)) g carbs · \(Int(average.fat)) g fat").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Averages include logged days only. Macro percentages use 4/4/9 kcal per gram.").font(.caption2).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).plateCard()
                if !model.energyDays.isEmpty { EnergyBalanceCard(range: range, grown: grown) }
                weightCard
                }
            }.padding(24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }.navigationTitle("Progress").background(PlateBackground(status: .calm))
            .onAppear { withAnimation(reduced ? nil : .spring(response: 1.1, dampingFraction: 0.8).delay(0.2)) { grown = true } }
            .onChange(of: range) { _, _ in
                guard !reduced else { return }
                grown = false
                withAnimation(.spring(response: 1, dampingFraction: 0.8).delay(0.05)) { grown = true }
            }
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.weight(.semibold).monospacedDigit()) }.padding(22).frame(maxWidth: .infinity, alignment: .leading).plateCard()
    }
    private func chartCard<C: View>(_ title: String, subtitle: String, @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary); chart().frame(height: 190) }.padding(22).plateCard()
    }
    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Body weight").font(.headline)
            if !model.store.account.weights.isEmpty {
                Chart(model.store.account.weights.sorted { $0.timestamp < $1.timestamp }) { entry in
                    LineMark(x: .value("Date", entry.timestamp), y: .value(model.store.account.settings.metric ? "kg" : "lb", displayWeight(entry.kilograms))).foregroundStyle(Color.plateAccent).interpolationMethod(.monotone)
                    PointMark(x: .value("Date", entry.timestamp), y: .value("Weight", displayWeight(entry.kilograms))).foregroundStyle(Color.plateAccent)
                }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 170).accessibilityLabel("Body-weight trend with \(model.store.account.weights.count) entries")
            } else { Text("Watch the trend over weeks, not single weigh-ins.").font(.subheadline).foregroundStyle(.secondary) }
            HStack {
                TextField(model.store.account.settings.metric ? "Weight in kg" : "Weight in lb", text: $weight).textFieldStyle(.roundedBorder)
                Button("Log weight") {
                    guard let value = Double(weight), value > 0, value.isFinite else { return }
                    model.store.account.weights.append(WeightEntry(kilograms: model.store.account.settings.metric ? value : value/2.2046226218)); model.sync.saveAccount(); weight = ""
                }.buttonStyle(.bordered).disabled((Double(weight) ?? 0) <= 0)
            }
        }.padding(22).plateCard()
    }
    private func displayWeight(_ kg: Double) -> Double { model.store.account.settings.metric ? kg : kg*2.2046226218 }
}
struct FoodsView: View {
    @Environment(PlateModel.self) private var model
    @State private var query = ""
    @State private var logged = false
    private var foods: [SavedFood] { model.store.account.foods.filter { query.isEmpty || $0.item.name.localizedCaseInsensitiveContains(query) || ($0.barcode?.contains(query) ?? false) }.sorted { $0.updatedAt > $1.updatedAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlatePageTitle(eyebrow: "YOUR PERSONAL PANTRY", title: "Good things, on repeat.", subtitle: "Your favourites. Always within reach.")
                Text("Your scanned labels and saved foods. Tap + to log one serving instantly.").foregroundStyle(.secondary)
                if foods.isEmpty { ContentUnavailableView.search(text: query).overlay { if query.isEmpty { ContentUnavailableView("Your own food library", systemImage: "bookmark", description: Text("Scan a nutrition label or save an item from a meal. Your favourites will live here.")) } } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                ForEach(foods) { food in
                    HStack {
                        VStack(alignment: .leading, spacing: 6) { Text(food.item.name).font(.headline); Text("\(Int(food.item.total.calories)) kcal · \(Int(food.item.total.protein)) g protein").font(.caption).foregroundStyle(.secondary); if let barcode = food.barcode { Text(barcode).font(.caption2.monospaced()).foregroundStyle(.secondary) } }
                        Spacer()
                        Button { model.logFood(food); logged.toggle() } label: { Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(Color.plateAccent) }.buttonStyle(.plain).accessibilityLabel("Log \(food.item.name)")
                    }.padding(20).plateCard()
                }
                }
                if !model.store.meals.isEmpty {
                    SectionEyebrow(text: "Repeat a past meal")
                    ForEach(Array(model.store.meals.prefix(10))) { meal in HStack { MealCard(meal: meal); Button("Repeat", systemImage: "arrow.clockwise") { model.repeatMeal(meal); logged.toggle() }.labelStyle(.iconOnly).buttonStyle(.bordered).accessibilityLabel("Repeat \(meal.items.map(\.name).joined(separator: ", "))") } }
                }
            }.padding(24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }.searchable(text: $query, prompt: "Search foods or barcode").navigationTitle("My Foods").background(PlateBackground(status: .calm)).sensoryFeedback(.success, trigger: logged)
    }
}
#Preview { HistoryView().environment(PlateModel()) }
