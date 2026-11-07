import SwiftUI
import PlateCore

private enum Destination: String, CaseIterable, Identifiable {
    case today = "Today", history = "History", foods = "My Foods", progress = "Progress", settings = "Settings"
    var id: String { rawValue }
    var subtitle: String { switch self { case .today: "Your energy, at a glance"; case .history: "Every meal, remembered"; case .foods: "Favourites within reach"; case .progress: "See your rhythm"; case .settings: "Make yourself at home" } }
    var tint: Color { switch self { case .today: .plateAccent; case .history: .plateCarb; case .foods: .bubble; case .progress: .plateFat; case .settings: .sky } }
    var icon: String { switch self { case .today: "face.smiling.inverse"; case .history: "calendar"; case .foods: "fork.knife"; case .progress: "chart.xyaxis.line"; case .settings: "slider.horizontal.3" } }
}
struct FoundationView: View {
    @State private var model: PlateModel
    // No default argument: a default PlateModel() would be built on every view rebuild.
    init(model: PlateModel) { _model = State(initialValue: model) }
    @AppStorage("plateAppearance") private var appearance: PlateAppearance = .system
    @State private var destination: Destination = .today
    @Namespace private var sidebarSelection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        Group {
            #if os(iOS)
            if sizeClass == .compact { tabs } else { split }
            #else
            split
            #endif
        }
        .environment(model).tint(Color.plateAccent)
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: $model.showCapture) { CaptureView().environment(model) }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView().environment(model).interactiveDismissDisabled() }
        .alert("Plate", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK") { model.notice = nil } } message: { Text(model.notice ?? "") }
        .task { await model.refreshHealth() }
        .task {
            model.showOnboarding = !model.store.account.onboarded
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                model.store.refreshClock()
            }
        }
        .onChange(of: model.store.account.onboarded) { _, done in if done { model.showOnboarding = false } }
        .onChange(of: model.connectivity.online) { _, online in if online { Task { await PhotoOutbox.shared.flush(sync: model.sync) } } }
        .onChange(of: model.sync.userID) { _, uid in if uid != nil { model.showOnboarding = !model.store.account.onboarded; Task { await PhotoOutbox.shared.flush(sync: model.sync) } } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.store.refreshClock(); model.store.publishWidget(); checkCaptureRequest(); Task { await SummaryNotifications.schedule(store: model.store); await PhotoOutbox.shared.flush(sync: model.sync); await model.refreshHealth() } } }
        .onOpenURL { model.handleURL($0) }
        .onReceive(NotificationCenter.default.publisher(for: .plateCapture)) { _ in model.showCapture = true }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { model.importedPhoto = try Data(contentsOf: url); model.showCapture = true; return true }
            catch { model.notice = error.localizedDescription; return false }
        }
    }
    private var split: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 13) {
                        PlateMark(size: 56)
                        VStack(alignment: .leading, spacing: 4) { Text("PLATE").font(.system(size: 22, weight: .black, design: .rounded)).tracking(3); Text("Good energy, daily.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.top, 22)
                    SectionEyebrow(text: "YOUR DAILY SPACE")
                    VStack(spacing: 10) {
                        ForEach(Destination.allCases) { item in
                            Button { withAnimation(reducedMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8)) { destination = item } } label: {
                                HStack(spacing: 13) {
                                    PlateIconTile(symbol: item.icon, tint: item.tint)
                                    VStack(alignment: .leading, spacing: 4) { Text(item.rawValue).font(.system(.headline, design: .rounded)); Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                    Spacer(minLength: 0)
                                    if destination == item { Circle().fill(item.tint).frame(width: 5, height: 5) }
                                }.padding(12).background {
                                    if destination == item { RoundedRectangle(cornerRadius: 22).fill(item.tint.opacity(0.12)).overlay(RoundedRectangle(cornerRadius: 22).stroke(item.tint.opacity(0.2))).matchedGeometryEffect(id: "sidebar-selection", in: sidebarSelection) }
                                }
                            }.buttonStyle(PlatePress()).foregroundStyle(.primary).accessibilityAddTraits(destination == item ? .isSelected : [])
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "A LITTLE REMINDER")
                        Text("Progress starts\nwith your next plate.").font(.system(.title3, design: .rounded, weight: .bold))
                        Image(systemName: "leaf.fill").font(.title).foregroundStyle(Color.plateAccent)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).plateCard()
                    Label(model.sync.status, systemImage: model.sync.userID == nil ? "internaldrive" : "checkmark.icloud").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                }.padding(18)
            }.background(PlateBackground(status: .calm)).navigationSplitViewColumnWidth(min: 245, ideal: 265)
            .safeAreaInset(edge: .bottom) { CaptureButton { model.showCapture = true }.padding(18) }

        } detail: {
            NavigationStack { screen(destination) }
        }
        .toolbar { ToolbarItem { Button("Log a meal", systemImage: "camera") { model.showCapture = true }.keyboardShortcut("n") } }
    }
    #if os(iOS)
    private var tabs: some View {
        ZStack {
            ForEach(Destination.allCases) { item in
                NavigationStack {
                    screen(item).toolbarBackground(.visible, for: .navigationBar)
                }
                .environment(\.plateMotionActive, destination == item)
                .opacity(destination == item ? 1 : 0)
                .scaleEffect(destination == item || reducedMotion ? 1 : 0.97)
                .offset(y: destination == item || reducedMotion ? 0 : 12)
                .allowsHitTesting(destination == item)
                .accessibilityHidden(destination != item)
                .zIndex(destination == item ? 1 : 0)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 12) {
            PhoneNavigationDock(selection: $destination) { model.showCapture = true }
                .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
    #endif
    @ViewBuilder private func screen(_ item: Destination) -> some View {
        switch item { case .today: TodayView(); case .history: HistoryView(); case .foods: FoodsView(); case .progress: ProgressViewScreen(); case .settings: SettingsView() }
    }
    private func checkCaptureRequest() {
        if UserDefaults(suiteName: SharedSnapshot.appGroup)?.bool(forKey: "openCapture") == true {
            UserDefaults(suiteName: SharedSnapshot.appGroup)?.set(false, forKey: "openCapture")
            UserDefaults(suiteName: SharedSnapshot.appGroup)?.set(true, forKey: "directCamera")
            model.showCapture = true
        }
    }
}
struct TodayView: View {
    @Environment(PlateModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var mealCount: Int { model.store.today.count }
    @State private var storyMode = 0
    @State private var mealFilter = 0
    private var visibleMeals: [Meal] { model.store.today.filter { mealFilter == 0 || $0.type == MealType.allCases[mealFilter - 1] } }
    @State private var selectedMeal: Meal?
    @State private var burst = 0
    @Namespace private var mealNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        todayContent
        .background(PlateBackground(status: model.store.guidance.state)).navigationTitle("Today")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $selectedMeal) { meal in
            #if os(iOS)
            if reduceMotion { MealDetailView(meal: meal).environment(model) }
            else { MealDetailView(meal: meal).environment(model).navigationTransition(.zoom(sourceID: meal.id, in: mealNamespace)) }
            #else
            MealDetailView(meal: meal).environment(model)
            #endif
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: mealFilter)
        .onChange(of: mealCount) { old, new in if new > old && overages.isEmpty { burst += 1 } }
        .onChange(of: model.store.guidance.state) { _, state in if state == .hit && overages.isEmpty { burst += 1 } }
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8), value: mealCount)
        .sensoryFeedback(.success, trigger: model.store.guidance.state == .hit && overages.isEmpty)
        .sensoryFeedback(.warning, trigger: overages.map(\.id))
    }
    private var todayContent: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 720
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        masthead(wide: wide)
                        if wide { CaptureButton { model.showCapture = true } }
                    }
                    let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
                    layout {
                        VStack(spacing: 22) {
                            dashboardHeader.plateEntrance(0)
                            quickCapture.plateEntrance(1)
                            if !model.energyDays.isEmpty { MovementCard().plateEntrance(2) }
                            if wide { DailySummaryCard(meals: model.store.today, target: model.store.effectiveTargets) }
                        }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 18) {
                            dayStory.plateEntrance(2)
                            HStack {
                                VStack(alignment: .leading, spacing: 5) { SectionEyebrow(text: "02 / THE FOOD JOURNAL"); Text("What made the day.").font(.system(.title, design: .rounded, weight: .bold)) }
                                Spacer()
                                Text("\(model.store.today.count)").font(.headline.monospacedDigit()).frame(width: 38, height: 38).background(Color.plateAccent.opacity(0.12), in: .circle)
                            }.padding(.top, 6)
                            if model.store.today.isEmpty { emptyJournal }
                            PlateSegmentedControl(options: ["All"] + MealType.allCases.map { $0.rawValue.capitalized }, selection: $mealFilter)
                            if visibleMeals.isEmpty && !model.store.today.isEmpty { Text("No meals in this moment yet.").font(.subheadline).foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity).plateCard() }
                            ForEach(visibleMeals) { meal in mealCard(meal).transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 30)), removal: .opacity.combined(with: .scale(scale: 0.95)))) }
                            if !wide && !model.store.today.isEmpty { DailySummaryCard(meals: model.store.today, target: model.store.effectiveTargets) }
                            if let error = model.store.error ?? model.sync.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(geometry.size.width < 500 ? 20 : 30).frame(maxWidth: 1440).frame(maxWidth: .infinity)
            }
        }
    }
    private func masthead(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                PlateMark(size: 34)
                Text("plate").font(.system(size: 22, weight: .black, design: .rounded)).tracking(-0.5)
                Spacer(minLength: 12)
                if !wide { FruitTrio(size: 48) }
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    headline
                    dateSticker
                }
                if wide { Spacer(minLength: 16); FruitTrio(size: 112).padding(.trailing, 8) }
            }
            Text("snap it, tell it, log it. Plato does the maths.")
                .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color.ink.opacity(0.65))
            StickerShelf()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
    }
    private var dateSticker: some View {
                Text(model.store.clock, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(Color.inkFixed)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.matcha, in: .capsule).overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
                    .rotationEffect(.degrees(3))
    }
    private var headline: some View {
            (Text("eat ") + Text("good").foregroundStyle(Color.chili) + Text(",\nfeel ") + Text("good").foregroundStyle(Color.ube) + Text(" ✨"))
                .font(.system(size: 52, weight: .black, design: .rounded)).tracking(-1.5)
                .lineSpacing(-4).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Eat good, feel good")
    }
    private var emptyJournal: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.butter.opacity(0.35)).overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ink, lineWidth: 2)).frame(height: 130)
                HStack(spacing: 6) {
                    ForEach(["🥕", "🥗", "🐟"], id: \.self) { emoji in WobbleSticker(emoji: emoji, size: 34, draggable: true) }
                }
            }
            Text("Your next good thing.").font(.system(.title2, design: .rounded, weight: .bold))
            Text("A quick photo, a familiar favourite, or something new. Every meal is a fresh start.").font(.subheadline).foregroundStyle(.secondary)
            Button { model.showCapture = true } label: { Label("Add your first plate", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(15).background(Color.plateAccent.opacity(0.15), in: .capsule) }.buttonStyle(PlatePress())
        }.padding(24).plateCard()
    }
    private var quickCapture: some View {
        Button { model.showCapture = true } label: {
            HStack(spacing: 15) {
                Image(systemName: "viewfinder").font(.system(size: 27, weight: .light)).frame(width: 56, height: 56).background(Color.plateAccent.opacity(0.16), in: .rect(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 5) { Text("A plate worth remembering.").font(.system(.headline, design: .rounded)); Text("Photo · nutrition label · manual entry").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.headline)
            }.padding(20).plateCard()
        }.buttonStyle(PlatePress()).foregroundStyle(.primary)
    }
    private var dayStory: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("The daily read.").font(.system(.title2, design: .rounded, weight: .bold)); Spacer(); Image(systemName: "sun.max.fill").foregroundStyle(Color.plateCarb).symbolEffect(.bounce, value: reduceMotion ? 0 : storyMode) }
            PlateSegmentedControl(options: ["Energy", "Protein", "Balance"], selection: $storyMode)
            VStack(alignment: .leading, spacing: 14) {
                Text(storyMode == 0 ? model.store.guidance.title : storyMode == 1 ? "Build a stronger plate." : "Every macro has a role.").font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.7)
                Text(storyMode == 0 ? "\(Int(abs(model.store.guidance.remaining))) kcal \(model.store.guidance.remaining < 0 ? "over" : "left")" : storyMode == 1 ? "\(Int(model.store.todayTotal.protein)) / \(Int(model.store.effectiveTargets.nutrients.protein)) g" : "\(Int(model.store.todayTotal.protein)) P · \(Int(model.store.todayTotal.carbs)) C · \(Int(model.store.todayTotal.fat)) F").font(.system(size: 32, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(storyMode == 0 ? model.store.guidance.message : storyMode == 1 ? "\(Int(max(0,model.store.effectiveTargets.nutrients.protein-model.store.todayTotal.protein))) g of protein left toward today’s target. Tap a meal below to explore what’s on your plate." : "Protein and carbs provide about 4 kcal per gram; fat provides about 9. Your logged food determines this split.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.id(storyMode).transition(.opacity.combined(with: .offset(y: 6)))
            if model.store.account.settings.trainingDayTargets != nil {
                Toggle(isOn: Binding(get: { model.store.trainingToday }, set: { model.store.trainingToday = $0; model.sync.saveAccount(); model.store.publishWidget() })) { Label("Training day", systemImage: "dumbbell.fill").font(.subheadline.bold()) }.tint(Color.plateAccent)
            }
            HStack { Label("\(model.store.today.count) \(model.store.today.count == 1 ? "meal" : "meals")", systemImage: "fork.knife"); Spacer(); Label(model.sync.status, systemImage: model.sync.userID == nil ? "internaldrive" : "icloud") }.font(.caption).foregroundStyle(.secondary)
        }.padding(24).plateCard().sensoryFeedback(.selection, trigger: storyMode)
    }
    @ViewBuilder private func mealCard(_ meal: Meal) -> some View {
        #if os(iOS)
        Button { selectedMeal = meal } label: { MealCard(meal: meal).matchedTransitionSource(id: meal.id, in: mealNamespace) }.buttonStyle(PlatePress())
        #else
        Button { selectedMeal = meal } label: { MealCard(meal: meal) }.buttonStyle(PlatePress())
        #endif
    }
    private var overages: [NutritionOverage] {
        NutritionOverage.evaluate(eaten: model.store.todayTotal, target: model.store.effectiveTargets.nutrients)
    }
    private var overTargetNotice: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30, weight: .bold))
                    .accessibilityHidden(true)
                Text("TARGET\nTERLEWATI").font(.system(size: 30, weight: .black)).tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            ForEach(overages) { overage in
                VStack(alignment: .leading, spacing: 6) {
                    Text(warningName(overage.id)).font(.caption.bold()).tracking(1.4)
                    Text("+\((overage.unit == "kcal" ? ceil(overage.excess) : max(0.1, overage.excess)).formatted(.number.precision(.fractionLength(0...1)))) \(overage.unit)")
                        .font(.system(size: 36, weight: .heavy, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                    Text("\(overage.consumed.formatted(.number.precision(.fractionLength(0...1)))) / \(overage.target.formatted(.number.precision(.fractionLength(0...1)))) \(overage.unit) · \((overage.consumed / overage.target).formatted(.percent.precision(.fractionLength(0)))) dari target")
                        .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9))
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(warningName(overage.id)), lebih \(overage.excess.formatted(.number.precision(.fractionLength(0...1)))) \(overage.unit) dari target")
                if overage.id != overages.last?.id { Rectangle().fill(.white.opacity(0.25)).frame(height: 1) }
            }
            Text("Cek catatan dan porsimu. Angka ini dibandingkan dengan target harian yang kamu atur.")
                .font(.caption).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }.padding(20).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.68, green: 0.045, blue: 0.09), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.25), lineWidth: 1))
    }
    private func warningName(_ id: String) -> String {
        switch id { case "calories": "KALORI"; case "protein": "PROTEIN · P"; case "carbs": "KARBOHIDRAT · C"; default: "LEMAK · F" }
    }
    private var dashboardHeader: some View {
        VStack(spacing: 18) {
            if !overages.isEmpty { overTargetNotice }
            HStack {
                SectionEyebrow(text: "01 / DAILY ENERGY")
                Spacer()
                Text(overages.isEmpty ? model.store.guidance.title : "TARGET TERLEWATI").font(.caption.weight(.semibold)).foregroundStyle(model.store.guidance.state.color).padding(.horizontal, 10).padding(.vertical, 7).background(model.store.guidance.state.color.opacity(0.10), in: .capsule)
            }
            PlateDial(meals: model.store.today, target: model.store.effectiveTargets.nutrients.calories, tint: model.store.guidance.state.color)
                .overlay { SparkBurst(trigger: burst, tint: model.store.guidance.state.color) }
            Text("Tap the plate to explore your energy").font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 9) {
                NutrientTile(name: "Protein", symbol: "bolt.fill", value: model.store.todayTotal.protein, target: model.store.effectiveTargets.nutrients.protein, tint: overages.contains { $0.id == "protein" } ? .red : .plateAccent)
                NutrientTile(name: "Carbs", symbol: "leaf.fill", value: model.store.todayTotal.carbs, target: model.store.effectiveTargets.nutrients.carbs, tint: overages.contains { $0.id == "carbs" } ? .red : .plateCarb)
                NutrientTile(name: "Fat", symbol: "drop.fill", value: model.store.todayTotal.fat, target: model.store.effectiveTargets.nutrients.fat, tint: overages.contains { $0.id == "fat" } ? .red : .plateFat)
            }
        }.padding(22)
            // Flat, like every other surface; a quiet red wash only when a target is passed.
            .plateCard()
            .overlay {
                if !overages.isEmpty {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.glazeRed.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.glazeRed.opacity(0.45), lineWidth: 1))
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.7), value: model.store.todayTotal)
    }
}

/// Today's burn and workouts from Apple Health, next to what you've eaten.
struct MovementCard: View {
    @Environment(PlateModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var today: EnergyDay? { model.energyDays.last.flatMap { Calendar.current.isDateInToday($0.date) ? $0 : nil } }
    var body: some View {
        let eaten = model.store.todayTotal.calories
        let burned = today?.burned ?? 0
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionEyebrow(text: "Your movement today")
                Spacer()
                Image(systemName: "flame.fill").foregroundStyle(.orange).symbolEffect(.breathe, isActive: !reduced)
            }
            HStack(alignment: .top, spacing: 12) {
                stat("Eaten", eaten, .plateAccent)
                stat("Burned so far", burned, .orange)
                stat(eaten <= burned ? "Below burn" : "Above burn", abs(burned - eaten), eaten <= burned ? .plateAccent : .plateCarb)
            }
            if model.workoutsToday.isEmpty {
                Text("No workouts yet today. Burned includes resting energy and everyday movement.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.workoutsToday.enumerated()), id: \.element.id) { index, workout in
                    HStack(spacing: 12) {
                        PlateIconTile(symbol: workout.symbol, tint: .orange, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.name).font(.system(.headline, design: .rounded))
                            Text("\(workout.start.formatted(.dateTime.hour().minute())) · \(Int((workout.duration / 60).rounded())) min").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(workout.kcal)) kcal").font(.subheadline.weight(.semibold).monospacedDigit())
                    }.plateEntrance(index + 1)
                }
            }
            Text("Workout calories aren't added to your target. Your activity setting already counts your training.").font(.caption2).foregroundStyle(.secondary)
        }.padding(22).plateCard()
    }
    private func stat(_ title: String, _ value: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Int(value.rounded()), format: .number).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(tint).contentTransition(.numericText(value: value))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduced ? nil : .spring(response: 0.7), value: value)
    }
}
struct MealCard: View {
    let meal: Meal
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            FoodPhoto(path: meal.thumbnailPath ?? meal.photoPath).frame(width: 80, height: 100).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text(meal.type.rawValue.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
                Text(meal.items.map(\.name).joined(separator: ", ")).font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(3)
                Text("\(meal.timestamp.formatted(.dateTime.hour().minute())) · \(Int(meal.total.protein)) g protein").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(meal.total.calories, format: .number.precision(.fractionLength(0))).font(.system(size: 25, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Text("KCAL").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
            }.fixedSize(horizontal: true, vertical: false)
        }.padding(.vertical, 18)
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.18)).frame(height: 0.75) }
            .foregroundStyle(.primary).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}
struct MealDetailView: View {
    @State var meal: Meal
    @Environment(PlateModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: String?
    @State private var confirmDelete = false
    @State private var aiItem: FoodItem?
    @State private var addingWithAI = false
    @State private var photoData: Data?
    @State private var hasChanges = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if meal.photoPath != nil { FoodPhoto(path: meal.photoPath).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 24)) }
                    Text("\(Int(meal.total.calories)) kcal · \(Int(meal.total.protein)) g protein").font(.title2.bold())
                    ForEach(meal.items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            Button { editing = item.id } label: {
                                HStack { VStack(alignment: .leading, spacing: 5) { Text(item.name).font(.headline); Text("\(item.quantity.formatted()) × \(item.servingDescription)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(Int(item.total.calories)) kcal").monospacedDigit() }
                            }.buttonStyle(.plain)
                            Button { aiItem = item } label: { Label("Edit with AI (photo + words)", systemImage: "sparkles").fontWeight(.semibold) }
                                .buttonStyle(.bordered).tint(Color.plateAccent).font(.caption)
                        }.padding(18).plateCard()
                    }
                    Button { addingWithAI = true } label: {
                        Label("Add food with AI (photo + words)", systemImage: "plus.bubble.fill").fontWeight(.semibold).frame(maxWidth: .infinity).padding(6)
                    }.buttonStyle(.borderedProminent).tint(Color.plateAccent)
                    if !meal.isValid { Label("Check portions and nutrition values before saving.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                    if hasChanges { Text("Tap Done to save your changes and update Apple Health when connected.").font(.caption).foregroundStyle(.secondary) }
                    Button("Repeat this meal", systemImage: "arrow.clockwise") { model.repeatMeal(meal); dismiss() }.buttonStyle(.borderedProminent).tint(Color.plateAccent)
                    Button("Save foods to My Foods", systemImage: "bookmark") { for item in meal.items { model.store.saveFood(item) }; model.sync.saveAccount(); model.notice = "Saved to My Foods." }
                    Button("Delete meal", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }.padding(24)
            }.navigationTitle(meal.type.rawValue.capitalized).background(PlateBackground(status: .calm))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.updateMeal(meal); dismiss() }.disabled(!meal.isValid || meal.items.contains { !($0.needsReviewFields ?? []).isEmpty }) } }
            .sheet(item: $aiItem) { item in
                DescribeFoodSheet(original: item, photo: photoData) { proposal in
                    meal.items = FoodReview.applying(proposal, replacing: item.id, to: meal.items)
                    hasChanges = true
                }.environment(model)
            }
            .sheet(isPresented: $addingWithAI) {
                DescribeFoodSheet(original: nil, photo: photoData) { proposal in
                    meal.items = FoodReview.applying(proposal, replacing: nil, to: meal.items)
                    hasChanges = true
                }.environment(model)
            }
            .task(id: meal.photoPath) {
                if let path = meal.photoPath { photoData = await PhotoStore.shared.load(path: path, sync: model.sync) }
            }
            .onChange(of: meal.items) { _, _ in hasChanges = true }
            .interactiveDismissDisabled(hasChanges)
            .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) { if let index = meal.items.firstIndex(where: { $0.id == editing }) { FoodItemEditor(item: $meal.items[index]) } }
            .confirmationDialog("Delete this meal?", isPresented: $confirmDelete) { Button("Delete meal", role: .destructive) { model.deleteMeal(meal); dismiss() } }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #endif
    }
}
struct DailySummaryCard: View {
    let meals: [Meal]
    let target: Targets
    private var total: Nutrients { meals.reduce(.zero) { $0 + $1.total } }
    private var ranked: [Meal] { meals.filter { $0.total.calories > 0 }.sorted { $0.total.protein/$0.total.calories > $1.total.protein/$1.total.calories } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(text: "Your daily picture")
            Text(DailyGuidance(eaten: total, target: target).title).font(.title3.weight(.semibold))
            Text("\(Int(total.protein)) g protein · \(Int(total.carbs)) g carbs · \(Int(total.fat)) g fat").font(.subheadline).foregroundStyle(.secondary)
            if let best = ranked.first { Label("Most protein per calorie: \(best.type.rawValue)", systemImage: "arrow.up.right").font(.caption) }
            if ranked.count > 1, let last = ranked.last { Label("Room to add protein: \(last.type.rawValue)", systemImage: "leaf").font(.caption).foregroundStyle(.secondary) }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).plateCard()
    }
}
#Preview { FoundationView(model: PlateModel()) }

#if os(iOS)
private struct PhoneNavigationDock: View {
    @Binding var selection: Destination
    let capture: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectedTab
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 64
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Destination.allCases) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.55)) { selection = item }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.icon).font(.system(size: 19, weight: .black)).frame(height: 23)
                                .symbolEffect(.bounce, value: selection == item)
                            Text(item == .foods ? "Foods" : item.rawValue)
                                .font(.system(size: 10, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(selection == item ? Color.inkFixed : Color.ink.opacity(0.65))
                        .frame(maxWidth: .infinity).frame(height: height - 14)
                        .background {
                            if selection == item {
                                Capsule().fill(item.tint).overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
                                    .matchedGeometryEffect(id: "selected-tab", in: selectedTab)
                            }
                        }.contentShape(Capsule())
                    }.buttonStyle(PlatePress()).accessibilityLabel(item.rawValue)
                        .accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            }.padding(6)
                .background(Capsule().fill(Color.surface))
                .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2.5))
            Button(action: capture) {
                Image(systemName: "camera.fill").font(.system(size: 22, weight: .black))
                    .foregroundStyle(Color.inkFixed).frame(width: height, height: height)
                    .background(Circle().fill(Color.chili)).overlay(Circle().strokeBorder(Color.ink, lineWidth: 2.5))
                    .contentShape(Circle())
            }.buttonStyle(PlatePress())
                .accessibilityLabel("Log a meal")
                .accessibilityHint("Take a photo, import an image, or enter food manually")
        }.frame(maxWidth: 600).sensoryFeedback(.selection, trigger: selection)
    }
}
#endif
