import SwiftUI
import Charts
import PlateCore

struct HistoryView: View {
    @Environment(PlateModel.self) private var model
    @State private var date = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var selected: Meal?
    private var meals: [Meal] { model.store.meals.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) } }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PlatePageTitle(eyebrow: "YOUR JOURNEY", title: "Every day tells a story.", subtitle: "Revisit the meals that keep you moving.")
                    weekStrip
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
    private var weekStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach((0..<14).reversed(), id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date.now) ?? .now
                    let active = Calendar.current.isDate(day, inSameDayAs: date)
                    let count = model.store.meals.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: day) }.count
                    Button { withAnimation(reduced ? nil : .smooth) { date = day } } label: {
                        VStack(spacing: 9) {
                            Text(day, format: .dateTime.weekday(.abbreviated)).font(.caption2.weight(.semibold))
                            Text(day, format: .dateTime.day()).font(.system(.title3, design: .rounded, weight: .bold))
                            Circle().fill(count > 0 ? Color.plateMint : .clear).frame(width: 5, height: 5)
                        }.frame(width: 52).padding(.vertical, 13).background(active ? Color.plateMint.opacity(0.22) : Color.plateMint.opacity(0.05), in: .rect(cornerRadius: 20))
                    }.buttonStyle(PlatePress()).foregroundStyle(.primary).accessibilityLabel(day.formatted(date: .complete, time: .omitted)).accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }.defaultScrollAnchor(.trailing)
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
    @State private var activeEnergy: Double?
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
                Picker("Period", selection: $range) { Text("Week").tag(7); Text("Month").tag(30) }.pickerStyle(.segmented).frame(maxWidth: 320)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 22, alignment: .top)], alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    stat("On-target streak", "\(HistoryMath.streak(meals: model.store.meals, targets: model.store.targets)) days")
                    stat("Protein average", "\(Int(average.protein)) g")
                }
                chartCard("Calories", subtitle: "Daily intake · line shows your current target") {
                    Chart {
                        ForEach(days) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Calories", point.nutrients.calories)).foregroundStyle(Color.plateMint.gradient).cornerRadius(4)
                        }
                        RuleMark(y: .value("Target", model.store.targets.nutrients.calories)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4]))

                        if let selectedDay, let point = days.min(by: { abs($0.date.timeIntervalSince(selectedDay)) < abs($1.date.timeIntervalSince(selectedDay)) }) {
                            RuleMark(x: .value("Selected", point.date, unit: .day)).foregroundStyle(Color.plateCarb).annotation(position: .top) { Text("\(Int(point.nutrients.calories)) kcal").font(.caption.bold()).padding(7).background(.regularMaterial, in: .capsule) }
                        }
                    }.chartXSelection(value: $selectedDay).chartYAxisLabel("kcal").accessibilityLabel("Daily calorie intake for the past \(range) days, compared with your current target of \(Int(model.store.targets.nutrients.calories)) calories")
                }
                chartCard("Protein consistency", subtitle: "Grams each day · keep showing up") {
                    Chart(days) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Protein", point.nutrients.protein)).foregroundStyle(point.nutrients.protein >= model.store.targets.nutrients.protein ? Color.plateMint : Color.plateMint.opacity(0.35)).cornerRadius(4)
                        RuleMark(y: .value("Protein target", model.store.targets.nutrients.protein)).lineStyle(StrokeStyle(dash: [4,4])).foregroundStyle(.secondary)
                    }.chartYAxisLabel("g").accessibilityLabel("Protein consistency, target \(Int(model.store.targets.nutrients.protein)) grams daily")
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Average macro split").font(.headline)
                    if loggedDays.isEmpty { Text("Log your first meal to see your macro balance.").foregroundStyle(.secondary) }
                    else {
                        Chart {
                            SectorMark(angle: .value("Protein calories", average.protein*4), innerRadius: .ratio(0.68), angularInset: 3).foregroundStyle(Color.plateMint)
                            SectorMark(angle: .value("Carb calories", average.carbs*4), innerRadius: .ratio(0.68), angularInset: 3).foregroundStyle(Color.plateCarb)
                            SectorMark(angle: .value("Fat calories", average.fat*9), innerRadius: .ratio(0.68), angularInset: 3).foregroundStyle(Color.plateFat)
                        }.frame(height: 170).accessibilityLabel("Average macros on logged days: \(Int(average.protein)) grams protein, \(Int(average.carbs)) grams carbs, \(Int(average.fat)) grams fat")
                        Text("\(Int(average.protein)) g protein · \(Int(average.carbs)) g carbs · \(Int(average.fat)) g fat").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Averages include logged days only. Macro percentages use 4/4/9 kcal per gram.").font(.caption2).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).plateCard()
                weightCard
                }
                if let activeEnergy { Label("Active energy today: \(Int(activeEnergy)) kcal", systemImage: "figure.walk").font(.caption).foregroundStyle(.secondary) }
            }.padding(24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }.navigationTitle("Progress").background(PlateBackground(status: .calm))
            .task { if UserDefaults.standard.bool(forKey: "healthEnabled") { activeEnergy = try? await model.health.activeEnergyToday() } }
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
                    LineMark(x: .value("Date", entry.timestamp), y: .value(model.store.account.settings.metric ? "kg" : "lb", displayWeight(entry.kilograms))).foregroundStyle(Color.plateMint).interpolationMethod(.monotone)
                    PointMark(x: .value("Date", entry.timestamp), y: .value("Weight", displayWeight(entry.kilograms))).foregroundStyle(Color.plateMint)
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
                        Button { model.logFood(food); logged.toggle() } label: { Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(Color.plateMint) }.buttonStyle(.plain).accessibilityLabel("Log \(food.item.name)")
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
