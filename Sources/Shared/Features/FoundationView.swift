import SwiftUI
import PlateCore

private enum Destination: String, CaseIterable, Identifiable {
    case today = "Today", history = "History", foods = "My Foods", progress = "Progress", settings = "Settings"
    var id: String { rawValue }
    var subtitle: String { switch self { case .today: "Your energy, at a glance"; case .history: "Every meal, remembered"; case .foods: "Favourites within reach"; case .progress: "See your rhythm"; case .settings: "Make yourself at home" } }
    var tint: Color { switch self { case .today: .plateMint; case .history: .plateCarb; case .foods: Color(red: 0.85, green: 0.42, blue: 0.48); case .progress: .plateFat; case .settings: Color(red: 0.35, green: 0.55, blue: 0.9) } }
    var icon: String { switch self { case .today: "circle.inset.filled"; case .history: "calendar"; case .foods: "fork.knife"; case .progress: "chart.xyaxis.line"; case .settings: "slider.horizontal.3" } }
}
struct FoundationView: View {
    @State private var model: PlateModel
    // No default argument: a default PlateModel() would be built on every view rebuild.
    init(model: PlateModel) { _model = State(initialValue: model) }
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
        .environment(model).tint(Color.plateMint)
        .sheet(isPresented: $model.showCapture) { CaptureView().environment(model) }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView().environment(model).interactiveDismissDisabled() }
        .alert("Plate", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK") { model.notice = nil } } message: { Text(model.notice ?? "") }
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
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.store.refreshClock(); model.store.publishWidget(); checkCaptureRequest(); Task { await SummaryNotifications.schedule(store: model.store); await PhotoOutbox.shared.flush(sync: model.sync) } } }
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
                        Image(systemName: "circle.inset.filled").font(.system(size: 32, weight: .medium)).foregroundStyle(Color.plateMint).frame(width: 56, height: 56).background(Color.plateMint.opacity(0.13), in: .rect(cornerRadius: 20))
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
                        Image(systemName: "leaf.fill").font(.title).foregroundStyle(Color.plateMint)
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
        TabView(selection: $destination) {
            Tab("Today", systemImage: "circle.inset.filled", value: Destination.today) { NavigationStack { TodayView() } }
            Tab("History", systemImage: "calendar", value: Destination.history) { NavigationStack { HistoryView() } }
            Tab("My Foods", systemImage: "fork.knife", value: Destination.foods) { NavigationStack { FoodsView() } }
            Tab("Progress", systemImage: "chart.xyaxis.line", value: Destination.progress) { NavigationStack { ProgressViewScreen() } }
            Tab("Settings", systemImage: "slider.horizontal.3", value: Destination.settings) { NavigationStack { SettingsView() } }
        }.tint(Color.plateMint).toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    PlateGlassPageBar(selection: $destination, tint: .plateMint)
                    Button { model.showCapture = true } label: { Image(systemName: "camera.fill").font(.title3).frame(width: 56, height: 60) }.buttonStyle(PlatePress()).glassEffect(.regular.tint(Color.plateMint.opacity(0.25)).interactive(), in: .capsule).accessibilityLabel("Log a meal")
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
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
    @State private var macrosOpen = false
    @State private var showEnergyRemaining = false
    @State private var storyMode = 0
    @State private var mealFilter = 0
    private var visibleMeals: [Meal] { model.store.today.filter { mealFilter == 0 || $0.type == MealType.allCases[mealFilter - 1] } }
    @State private var selectedMeal: Meal?
    @State private var pinnedHeader = false
    @Namespace private var mealNamespace
    @Namespace private var headerNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 720
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        PlatePageTitle(eyebrow: "PLATE / \(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))", title: "Good food. Good energy.", subtitle: "A little intention. A stronger you.")
                        if wide { CaptureButton { model.showCapture = true } }
                    }
                    let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
                    layout {
                        VStack(spacing: 22) {
                            dashboardHeader
                            quickCapture
                            if wide { DailySummaryCard(meals: model.store.today, target: model.store.effectiveTargets) }
                        }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 18) {
                            dayStory
                            HStack {
                                VStack(alignment: .leading, spacing: 5) { SectionEyebrow(text: "YOUR FOOD JOURNAL"); Text("On the table").font(.system(.title2, design: .rounded, weight: .bold)) }
                                Spacer()
                                Text("\(model.store.today.count)").font(.headline.monospacedDigit()).frame(width: 38, height: 38).background(Color.plateMint.opacity(0.12), in: .circle)
                            }.padding(.top, 6)
                            if model.store.today.isEmpty { emptyJournal }
                            PlateSegmentedControl(options: ["All"] + MealType.allCases.map { $0.rawValue.capitalized }, selection: $mealFilter)
                            if visibleMeals.isEmpty && !model.store.today.isEmpty { Text("No meals in this moment yet.").font(.subheadline).foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity).plateCard() }
                            ForEach(visibleMeals) { meal in mealCard(meal).transition(.opacity.combined(with: .move(edge: .bottom))) }
                            if !wide && !model.store.today.isEmpty { DailySummaryCard(meals: model.store.today, target: model.store.effectiveTargets) }
                            if let error = model.store.error ?? model.sync.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(geometry.size.width < 500 ? 20 : 30).frame(maxWidth: 1440).frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 440 } action: { _, pinned in pinnedHeader = pinned }
        }
        .safeAreaInset(edge: .top, spacing: 0) { if pinnedHeader { stickyHeader.padding(.horizontal, 18).padding(.bottom, 8).transition(.move(edge: .top).combined(with: .opacity)) } }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: pinnedHeader)
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
        .sensoryFeedback(.success, trigger: model.store.guidance.state == .hit)
        .sensoryFeedback(.warning, trigger: model.store.guidance.state == .over)
    }
    private var emptyJournal: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color.plateCarb.opacity(0.12)).frame(height: 130)
                HStack(spacing: -10) {
                    ForEach(Array(["carrot.fill", "leaf.fill", "fish.fill"].enumerated()), id: \.offset) { index, symbol in
                        Image(systemName: symbol).font(.system(size: 28, weight: .medium)).foregroundStyle([Color.plateCarb, Color.plateMint, Color.plateFat][index]).frame(width: 78, height: 78).background(.ultraThinMaterial, in: .rect(cornerRadius: 25)).rotationEffect(.degrees(Double(index-1)*14)).shadow(color: .black.opacity(0.05), radius: 12, y: 8)
                    }
                }
            }
            Text("Your next good thing.").font(.system(.title2, design: .rounded, weight: .bold))
            Text("A quick photo, a familiar favourite, or something new. Every meal is a fresh start.").font(.subheadline).foregroundStyle(.secondary)
            Button { model.showCapture = true } label: { Label("Add your first plate", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(15).background(Color.plateMint.opacity(0.15), in: .capsule) }.buttonStyle(PlatePress())
        }.padding(24).plateCard()
    }
    private var quickCapture: some View {
        Button { model.showCapture = true } label: {
            HStack(spacing: 15) {
                Image(systemName: "viewfinder").font(.system(size: 27, weight: .light)).frame(width: 56, height: 56).background(Color.plateMint.opacity(0.16), in: .rect(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 5) { Text("Point. Snap. Savour.").font(.system(.headline, design: .rounded)); Text("Photo · nutrition label · manual entry").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.headline)
            }.padding(20).plateCard()
        }.buttonStyle(PlatePress()).foregroundStyle(.primary)
    }
    private var dayStory: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("The day, made simple").font(.system(.title3, design: .rounded, weight: .bold)); Spacer(); Image(systemName: "sun.max.fill").foregroundStyle(Color.plateCarb).symbolEffect(.bounce, value: reduceMotion ? 0 : storyMode) }
            PlateSegmentedControl(options: ["Energy", "Protein", "Balance"], selection: $storyMode)
            VStack(alignment: .leading, spacing: 14) {
                Text(storyMode == 0 ? model.store.guidance.title : storyMode == 1 ? "Build a stronger plate." : "Every macro has a role.").font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.7)
                Text(storyMode == 0 ? "\(Int(abs(model.store.guidance.remaining))) kcal \(model.store.guidance.remaining < 0 ? "over" : "left")" : storyMode == 1 ? "\(Int(model.store.todayTotal.protein)) / \(Int(model.store.effectiveTargets.nutrients.protein)) g" : "\(Int(model.store.todayTotal.protein)) P · \(Int(model.store.todayTotal.carbs)) C · \(Int(model.store.todayTotal.fat)) F").font(.system(size: 32, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(storyMode == 0 ? model.store.guidance.message : storyMode == 1 ? "\(Int(max(0,model.store.effectiveTargets.nutrients.protein-model.store.todayTotal.protein))) g of protein left toward today’s target. Tap a meal below to explore what’s on your plate." : "Protein and carbs provide about 4 kcal per gram; fat provides about 9. Your logged food determines this split.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.id(storyMode).transition(.opacity.combined(with: .offset(y: 6)))
            if model.store.account.settings.trainingDayTargets != nil {
                Toggle(isOn: Binding(get: { model.store.trainingToday }, set: { model.store.trainingToday = $0; model.sync.saveAccount(); model.store.publishWidget() })) { Label("Training day", systemImage: "dumbbell.fill").font(.subheadline.bold()) }.tint(Color.plateMint)
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
    private var stickyHeader: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 10) {
                HStack {
                    Text("\(Int(model.store.todayTotal.calories)) / \(Int(model.store.effectiveTargets.nutrients.calories)) kcal").font(.headline.monospacedDigit()).contentTransition(.numericText())
                    Spacer()
                    Text("\(Int(abs(model.store.guidance.remaining))) \(model.store.guidance.remaining < 0 ? "over" : "left")").font(.subheadline.weight(.semibold)).foregroundStyle(model.store.guidance.state.color).contentTransition(.numericText())
                }
                HStack {
                    Text("P \(Int(model.store.todayTotal.protein))/\(Int(model.store.effectiveTargets.nutrients.protein))g").foregroundStyle(Color.plateMint)
                    Spacer()
                    Text("C \(Int(model.store.todayTotal.carbs))/\(Int(model.store.effectiveTargets.nutrients.carbs))g").foregroundStyle(Color.plateCarb)
                    Spacer()
                    Text("F \(Int(model.store.todayTotal.fat))/\(Int(model.store.effectiveTargets.nutrients.fat))g").foregroundStyle(Color.plateFat)
                }.font(.caption.monospacedDigit())
            }.padding(15)
                .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 20))
                .glassEffectID("nutrition-glance", in: headerNamespace)
                .background { if reduceTransparency { RoundedRectangle(cornerRadius: 20).fill(.background) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily progress. \(Int(model.store.todayTotal.calories)) of \(Int(model.store.effectiveTargets.nutrients.calories)) calories. Protein \(Int(model.store.todayTotal.protein)) of \(Int(model.store.effectiveTargets.nutrients.protein)) grams. Carbs \(Int(model.store.todayTotal.carbs)) grams. Fat \(Int(model.store.todayTotal.fat)) grams.")
        }
    }
    private var dashboardHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label("Energy today", systemImage: "sparkle").font(.subheadline.bold())
                    Spacer()
                    Button { withAnimation(reduceMotion ? nil : .spring(response: 0.5)) { showEnergyRemaining.toggle() } } label: { Image(systemName: showEnergyRemaining ? "arrow.turn.down.left" : "arrow.up.right").font(.subheadline).frame(width: 36, height: 36).background(.white.opacity(0.1), in: .circle) }.buttonStyle(PlatePress()).accessibilityLabel("Switch eaten and remaining calories")
                }
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(showEnergyRemaining ? abs(model.store.guidance.remaining) : model.store.todayTotal.calories, format: .number.precision(.fractionLength(0))).font(.system(size: 57, weight: .bold, design: .rounded)).tracking(-2).contentTransition(.numericText()).minimumScaleFactor(0.55)
                        Text(showEnergyRemaining ? (model.store.guidance.remaining < 0 ? "kcal over target" : "kcal left today") : "kcal eaten today").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        Text("Target \(Int(model.store.effectiveTargets.nutrients.calories)) kcal").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    PlateSculpture().scaleEffect(0.9).frame(width: 120, height: 130)
                }
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.13))
                        .overlay(alignment: .leading) { Capsule().fill(LinearGradient(colors: [Color.plateMint, Color(red: 0.72, green: 0.95, blue: 0.52)], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * min(1,max(0,model.store.todayTotal.calories/max(1,model.store.effectiveTargets.nutrients.calories)))) }
                }.frame(height: 8).accessibilityLabel("Calorie progress")
                Button { withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.82)) { macrosOpen.toggle() } } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: -7) {
                            ForEach(Array([Color.plateMint, .plateCarb, .plateFat].enumerated()), id: \.offset) { index, tint in Text(["P","C","F"][index]).font(.caption2.bold()).frame(width: 27, height: 27).background(tint.gradient, in: .circle).overlay(Circle().stroke(.white.opacity(0.4))) }
                        }
                        VStack(alignment: .leading, spacing: 4) { Text(macrosOpen ? "Tuck away macros" : "Where’s my energy from?").font(.caption.bold()); Text("\(Int(model.store.todayTotal.protein)) P · \(Int(model.store.todayTotal.carbs)) C · \(Int(model.store.todayTotal.fat)) F grams").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.caption.bold()).rotationEffect(.degrees(macrosOpen ? 180 : 0))
                    }.padding(15).background(.white.opacity(0.1), in: .rect(cornerRadius: 20))
                }.buttonStyle(PlatePress())
            }.padding(24).foregroundStyle(.white)
                .background(LinearGradient(colors: [Color(red: 0.13, green: 0.37, blue: 0.31), Color(red: 0.07, green: 0.15, blue: 0.27)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 34))
                .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.15)))
                .shadow(color: Color.plateMint.opacity(0.2), radius: 24, y: 14)
            if macrosOpen {
                HStack(alignment: .top, spacing: 9) {
                    NutrientTile(name: "Protein", symbol: "bolt.fill", value: model.store.todayTotal.protein, target: model.store.effectiveTargets.nutrients.protein, tint: .plateMint)
                    NutrientTile(name: "Carbs", symbol: "leaf.fill", value: model.store.todayTotal.carbs, target: model.store.effectiveTargets.nutrients.carbs, tint: .plateCarb)
                    NutrientTile(name: "Fat", symbol: "drop.fill", value: model.store.todayTotal.fat, target: model.store.effectiveTargets.nutrients.fat, tint: .plateFat)
                }.padding(15).plateCard().padding(.top, 14).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }.sensoryFeedback(.selection, trigger: macrosOpen)
            .animation(reduceMotion ? nil : .spring(response: 0.6), value: model.store.todayTotal)
    }
}

struct MealCard: View {
    let meal: Meal
    var body: some View {
        HStack(spacing: 16) {
            FoodPhoto(path: meal.thumbnailPath ?? meal.photoPath).frame(width: 82, height: 92).clipShape(RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 7) {
                Text(meal.type.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
                Text(meal.items.map(\.name).joined(separator: ", ")).font(.system(.headline, design: .rounded)).lineLimit(2)
                Text("\(meal.timestamp.formatted(.dateTime.hour().minute())) · \(Int(meal.total.protein)) g protein").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) { Text(meal.total.calories, format: .number.precision(.fractionLength(0))).font(.title3.weight(.semibold).monospacedDigit()); Text("kcal").font(.caption2).foregroundStyle(.secondary) }
        }.padding(18).plateCard().foregroundStyle(.primary).contentShape(RoundedRectangle(cornerRadius: 26)).accessibilityElement(children: .combine)
    }
}
struct MealDetailView: View {
    @State var meal: Meal
    @Environment(PlateModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: String?
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if meal.photoPath != nil { FoodPhoto(path: meal.photoPath).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 24)) }
                    Text("\(Int(meal.total.calories)) kcal · \(Int(meal.total.protein)) g protein").font(.title2.bold())
                    ForEach(meal.items) { item in
                        Button { editing = item.id } label: { HStack { VStack(alignment: .leading) { Text(item.name).font(.headline); Text("\(item.quantity.formatted()) × \(item.servingDescription)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(Int(item.total.calories)) kcal") }.padding(18).plateCard() }.buttonStyle(.plain)
                    }
                    Button("Repeat this meal", systemImage: "arrow.clockwise") { model.repeatMeal(meal); dismiss() }.buttonStyle(.borderedProminent).tint(Color.plateMint)
                    Button("Save foods to My Foods", systemImage: "bookmark") { for item in meal.items { model.store.saveFood(item) }; model.sync.saveAccount(); model.notice = "Saved to My Foods." }
                    Button("Delete meal", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }.padding(24)
            }.navigationTitle(meal.type.rawValue.capitalized).background(PlateBackground(status: .calm))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { meal.updatedAt = .now; model.sync.save(meal); dismiss() } } }
            .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) { if let index = meal.items.firstIndex(where: { $0.id == editing }) { FoodItemEditor(item: $meal.items[index]) } }
            .confirmationDialog("Delete this meal?", isPresented: $confirmDelete) { Button("Delete meal", role: .destructive) { model.sync.remove(meal); dismiss() } }
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
private struct PlateGlassPageBar: View {
    @Binding var selection: Destination
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    private let inset: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let itemWidth = max(1, (geometry.size.width - inset * 2) / CGFloat(Destination.allCases.count))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(scheme == .dark ? Color.white.opacity(0.15) : tint.opacity(0.11))
                    .frame(width: itemWidth, height: 52)
                    .offset(x: inset + CGFloat(Destination.allCases.firstIndex(of: selection) ?? 0) * itemWidth)
                    .overlay(Capsule().stroke(.white.opacity(scheme == .dark ? 0.11 : 0.42), lineWidth: 0.6))
                    .shadow(color: tint.opacity(0.12), radius: 10, y: 4)
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.80), value: selection)
                    .allowsHitTesting(false)
                HStack(spacing: 0) {
                    ForEach(Destination.allCases) { destination in
                        Button { select(destination) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: destination.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .symbolEffect(.bounce, value: reduceMotion ? false : selection == destination)
                                    .frame(height: 25)
                                Text(destination.rawValue)
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .lineLimit(1).minimumScaleFactor(0.72)
                            }
                            .foregroundStyle(selection == destination ? tint : Color.primary)
                            .frame(width: itemWidth, height: 52)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(destination.rawValue)
                        .accessibilityAddTraits(selection == destination ? .isSelected : [])
                    }
                }.padding(.horizontal, inset)
            }
            .frame(width: geometry.size.width, height: 60)
            .contentShape(Capsule())
            .glassEffect(reducedTransparency ? .identity : .regular.interactive(), in: .capsule)
            .background { if reducedTransparency { Capsule().fill(.background) } }
            .overlay(Capsule().stroke(.white.opacity(scheme == .dark ? 0.10 : 0.46), lineWidth: 0.7))
            .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.07), radius: 18, y: 8)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard value.location.y >= -10, value.location.y <= 70 else { return }
                        let index = min(Destination.allCases.count - 1, max(0, Int((value.location.x - inset) / itemWidth)))
                        select(Destination.allCases[index])
                    }
            )
            .sensoryFeedback(.selection, trigger: selection)
        }
        .frame(height: 60)
        .accessibilityElement(children: .contain)
    }
    private func select(_ destination: Destination) {
        guard selection != destination else { return }
        selection = destination
    }
}

#endif
