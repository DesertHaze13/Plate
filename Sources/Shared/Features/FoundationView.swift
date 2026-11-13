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
    @State private var showSettings = false
    @Namespace private var sidebarSelection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        Group {
            #if os(iOS)
            // iPhone: Liquid Glass tab bar. iPad: the same tabs float as a glass bar at the top,
            // and expand into a sidebar, exactly like Apple's own apps.
            tabs
            #else
            split
            #endif
        }
        .environment(model).tint(Color.plateAccent)
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: $showSettings) { SettingsView().environment(model) }
        .sheet(isPresented: $model.showCapture) { CaptureView().environment(model) }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView().environment(model).interactiveDismissDisabled() }
        .alert("Plate", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK") { model.notice = nil } } message: { Text(model.notice ?? "") }
        .task { await model.refreshHealth() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                model.store.refreshClock()
            }
        }
        // Only ask for a profile once we actually know there isn't one (not while the saved account is still loading).
        .onChange(of: model.sync.accountReady && !model.store.account.onboarded, initial: true) { _, needed in model.showOnboarding = needed }
        .onChange(of: model.connectivity.online) { _, online in if online { Task { await PhotoOutbox.shared.flush(sync: model.sync) } } }
        .onChange(of: model.sync.userID) { _, uid in if uid != nil { Task { await PhotoOutbox.shared.flush(sync: model.sync) } } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.store.refreshClock(); model.store.publishWidget(); checkCaptureRequest(); Task { await SummaryNotifications.schedule(store: model.store); await PhotoOutbox.shared.flush(sync: model.sync); await model.refreshHealth() } } }
        .onChange(of: model.store.meals, initial: true) { _, _ in Task { await model.syncMealsToHealth() } }
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
                                    if destination == item { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.clear).glassEffect(Glass.regular.tint(item.tint.opacity(0.35)).interactive(), in: .rect(cornerRadius: 22)).matchedGeometryEffect(id: "sidebar-selection", in: sidebarSelection) }
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
    /// The system iOS 26 tab bar, so it gets real Liquid Glass: press and slide across it and the lens magnifies the tabs.
    /// "Log" uses the search role, which iOS draws as its own round glass button beside the bar.
    private var tabs: some View {
        let compact = sizeClass == .compact
        return TabView(selection: tabSelection) {
            // On iPhone, Settings lives behind a toolbar button; on iPad it is a tab like the rest.
            ForEach(Destination.allCases.filter { !compact || $0 != .settings }) { item in
                Tab(LocalizedStringKey(item == .foods && compact ? "Foods" : item.rawValue), systemImage: item.icon, value: TabChoice.page(item)) {
                    NavigationStack {
                        screen(item)
                            .toolbar {
                                if compact && item != .today {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true }
                                    }
                                }
                            }
                    }
                        .environment(\.plateMotionActive, destination == item)
                }
            }
            Tab("Log a meal", systemImage: "camera.fill", value: TabChoice.capture, role: .search) {
                Color.clear
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            HStack(spacing: 12) {
                PlateMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLATE").font(.system(size: 18, weight: .black, design: .rounded)).tracking(2.5)
                    Text("Good energy, daily.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 8)
        }
        .tabViewSidebarFooter {
            VStack(alignment: .leading, spacing: 12) {
                Button { model.showCapture = true } label: {
                    Label("Log a meal", systemImage: "camera.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.glassProminent).tint(Color.plateAccent)
                Label(model.sync.status, systemImage: model.sync.userID == nil ? "internaldrive" : "checkmark.icloud").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
    /// Choosing "Log a meal" opens the camera sheet and leaves you on the tab you were on.
    private var tabSelection: Binding<TabChoice> {
        Binding(get: { .page(destination) }, set: { choice in
            switch choice {
            case .page(let item): destination = item
            case .capture: model.showCapture = true
            }
        })
    }
    #endif
    @ViewBuilder private func screen(_ item: Destination) -> some View {
        switch item { case .today: TodayView(openSettings: sizeClass == .compact ? { showSettings = true } : nil); case .history: HistoryView(); case .foods: FoodsView(); case .progress: ProgressViewScreen(); case .settings: SettingsView() }
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
    var openSettings: (@MainActor () -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(PlateModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var mealCount: Int { model.store.today.count }
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @Namespace private var dayStripNamespace
    private var isToday: Bool { Calendar.current.isDate(selectedDay, inSameDayAs: model.store.clock) }
    private var dayMeals: [Meal] { model.store.meals(on: selectedDay) }
    private var dayTotal: Nutrients { model.store.total(on: selectedDay) }
    private var dayTargets: Targets { model.store.targets(on: selectedDay) }
    private var dayGuidance: DailyGuidance { DailyGuidance(eaten: dayTotal, target: dayTargets) }
    private var dayWord: String { isToday ? "today" : "that day" }
    static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
    private func step(_ offset: Int) {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: offset, to: selectedDay), calendar.startOfDay(for: day) <= calendar.startOfDay(for: model.store.clock) else { return }
        select(day)
    }
    private func select(_ day: Date) {
        let target = Calendar.current.startOfDay(for: day)
        guard target != selectedDay else { return }
        goingBack = target < selectedDay
        withAnimation(reduceMotion ? nil : Motion.turn) { selectedDay = target }
    }
    /// True while moving to an earlier day: text rolls downward, forward rolls upward.
    @State private var goingBack = false
    /// The day the last celebration or warning belonged to, so flipping days never fires them.
    @State private var feedbackDay = ""
    @State private var warn = 0
    private var dayKey: String { DayKey.make(selectedDay) }
    @State private var storyMode = 0
    @State private var mealFilter = 0
    private var visibleMeals: [Meal] { dayMeals.filter { mealFilter == 0 || $0.type == MealType.allCases[mealFilter - 1] } }
    @State private var selectedMeal: Meal?
    @State private var burst = 0
    @State private var typingMeal = false
    @Namespace private var mealNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        todayContent
        .background(PlateBackground(status: dayGuidance.state)).navigationTitle(Self.title(for: selectedDay))
        #if os(iOS)
        .toolbarTitleMenu {
            Button("Today", systemImage: "sun.max") { select(.now) }
            Section("Logged days") {
                ForEach(model.store.loggedDays.prefix(60), id: \.self) { day in
                    Button { select(day) } label: {
                        Label("\(Self.title(for: day)) · \(Int(model.store.total(on: day).calories)) kcal", systemImage: Calendar.current.isDate(day, inSameDayAs: selectedDay) ? "checkmark" : "calendar")
                    }
                }
            }
        }
        #endif
        .sensoryFeedback(.selection, trigger: selectedDay)
        .onChange(of: selectedDay, initial: true) { _, day in model.viewingDay = day }
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        .modifier(TodayChrome(compact: sizeClass == .compact, header: {
            // iPhone: no blurred bar; the title becomes a floating Liquid Glass header over the content.
            FloatingDayHeader(title: Self.title(for: selectedDay), selectedDay: selectedDay, isToday: isToday,
                              loggedDays: model.store.loggedDays, goingBack: goingBack, total: { model.store.total(on: $0).calories },
                              select: select, step: step, openSettings: openSettings)
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
        }, items: {
            // iPad: the same controls join the top row beside the floating tab bar, as glass toolbar buttons.
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("Previous day", systemImage: "chevron.left") { step(-1) }
                Menu {
                    Button("Today", systemImage: "sun.max") { select(.now) }
                    Section("Logged days") {
                        ForEach(model.store.loggedDays.prefix(60), id: \.self) { day in
                            Button { select(day) } label: {
                                Label("\(Self.title(for: day)) · \(Int(model.store.total(on: day).calories)) kcal", systemImage: Calendar.current.isDate(day, inSameDayAs: selectedDay) ? "checkmark" : "calendar")
                            }
                        }
                    }
                } label: {
                    Text(Self.title(for: selectedDay)).font(.headline).contentTransition(.numericText(countsDown: goingBack))
                }
                Button("Next day", systemImage: "chevron.right") { step(1) }.disabled(isToday)
            }
            if !isToday {
                ToolbarSpacer(.fixed, placement: .topBarLeading)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back to today", systemImage: "arrow.uturn.backward") { select(.now) }
                        .buttonStyle(.glassProminent).tint(Color.plateAccent)
                }
            }
        }))
        #endif
        .sheet(isPresented: $typingMeal) {
            DescribeFoodSheet(original: nil, photo: nil) { foods in
                Task { await model.saveMeal(Meal(timestamp: PlateModel.logTime(for: selectedDay), items: foods, source: .manual)) }
            }.environment(model)
        }
        .sheet(item: $selectedMeal) { meal in
            #if os(iOS)
            if reduceMotion { MealDetailView(meal: meal).environment(model) }
            else { MealDetailView(meal: meal).environment(model).navigationTransition(.zoom(sourceID: meal.id, in: mealNamespace)) }
            #else
            MealDetailView(meal: meal).environment(model)
            #endif
        }
        .animation(reduceMotion ? nil : Motion.turn, value: mealFilter)
        .environment(\.plateDay, dayKey)
        // Bursts and buzzes only answer food you log, not a change of day.
        .onChange(of: mealCount) { old, new in if dayKey == feedbackDay, new > old, overages.isEmpty { burst += 1 } }
        .onChange(of: dayGuidance.state) { _, state in if dayKey == feedbackDay, state == .hit, overages.isEmpty { burst += 1 } }
        .onChange(of: overages.map(\.id)) { old, new in if dayKey == feedbackDay, new.count > old.count { warn += 1 } }
        .onChange(of: dayKey, initial: true) { _, key in Task { @MainActor in feedbackDay = key } }
        .animation(reduceMotion ? nil : Motion.turn, value: mealCount)
        .sensoryFeedback(.success, trigger: burst)
        .sensoryFeedback(.warning, trigger: warn)
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
                    dayStrip
                    let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
                    layout {
                        VStack(spacing: 22) {
                            dashboardHeader.plateEntrance(0)
                            quickCapture.plateEntrance(1)
                            if isToday && !model.energyDays.isEmpty { MovementCard().plateEntrance(2) }
                            if wide { DailySummaryCard(meals: dayMeals, target: dayTargets) }
                        }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 18) {
                            dayStory.plateEntrance(2)
                            HStack {
                                VStack(alignment: .leading, spacing: 5) { SectionEyebrow(text: "02 / THE FOOD JOURNAL"); Text("What made the day.").font(.system(.title, design: .rounded, weight: .bold)) }
                                Spacer()
                                Text("\(dayMeals.count)").font(.headline.monospacedDigit()).frame(width: 38, height: 38).background(Color.plateAccent.opacity(0.12), in: .circle)
                            }.padding(.top, 6)
                            if dayMeals.isEmpty { emptyJournal }
                            PlateSegmentedControl(options: ["All"] + MealType.allCases.map { $0.rawValue.capitalized }, selection: $mealFilter)
                            if visibleMeals.isEmpty && !dayMeals.isEmpty { Text("No meals in this moment yet.").font(.subheadline).foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity).plateCard() }
                            ForEach(visibleMeals) { meal in mealCard(meal).transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 30)), removal: .opacity.combined(with: .scale(scale: 0.95)))) }
                            if !wide && !dayMeals.isEmpty { DailySummaryCard(meals: dayMeals, target: dayTargets) }
                            if let error = model.store.error ?? model.sync.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(geometry.size.width < 500 ? 20 : 30).frame(maxWidth: 1440).frame(maxWidth: .infinity)
            }
        }
    }
    /// Every recent day as a chip; days with meals carry a dot. Tap one and the whole dashboard follows.
    private var dayStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: model.store.clock)
        let logged = Set(model.store.loggedDays)
        let fortnight = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let oldest = min(model.store.loggedDays.last ?? fortnight, fortnight)
        let span = min(120, (calendar.dateComponents([.day], from: oldest, to: today).day ?? 13) + 1)
        let days: [Date] = (0..<span).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.reversed()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionEyebrow(text: isToday ? "Your days" : "Looking back")
                Spacer()
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                            let hasMeals = logged.contains(day)
                            Button { select(day) } label: {
                                VStack(spacing: 5) {
                                    Text(day, format: .dateTime.weekday(.abbreviated)).font(.caption2.weight(.semibold))
                                    Text(day, format: .dateTime.day()).font(.system(.headline, design: .rounded, weight: .bold))
                                    Circle().fill(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.plateAccent)).frame(width: 5, height: 5).opacity(hasMeals ? 1 : 0)
                                }
                                .foregroundStyle(selected ? AnyShapeStyle(.white) : hasMeals ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                                .frame(width: 48, height: 68)
                                // One crisp pill that glides to the chosen day (a solid fill morphs cleanly; glass smeared mid-flight).
                                .background {
                                    if selected {
                                        Capsule().fill(LinearGradient(colors: [Color.ube, Color.ube.mix(with: .bubble, by: 0.35)], startPoint: .top, endPoint: .bottom))
                                            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                                            .matchedGeometryEffect(id: "selected-day", in: dayStripNamespace)
                                    }
                                }
                                .contentShape(Capsule())
                            }.buttonStyle(PlatePress()).id(day)
                                .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted))\(hasMeals ? ", \(Int(model.store.total(on: day).calories)) calories" : ", nothing logged")")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }.padding(6)
                }
                .defaultScrollAnchor(.trailing)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
                .onChange(of: selectedDay) { _, day in withAnimation(reduceMotion ? nil : Motion.turn) { proxy.scrollTo(day, anchor: .center) } }
            }
        }
    }
    private func masthead(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                PlateMark(size: 28)
                Text("plate").font(.system(size: 20, weight: .bold)).tracking(-0.5)
                Spacer(minLength: 12)
                if !wide { FruitTrio(size: 48) }
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    headline
                    dateChip
                }
                if wide { Spacer(minLength: 16); FruitTrio(size: 112).padding(.trailing, 8) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
    }
    private var dateChip: some View {
        Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .font(.footnote.weight(.semibold))
            .contentTransition(.numericText(countsDown: goingBack))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }
    private var headline: some View {
        Text("eat good,\nfeel good.")
            .font(.system(size: 56, weight: .heavy)).tracking(-2.2)
            .lineSpacing(-6).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(LinearGradient(colors: [Color.ink, Color.ube, Color.chili], startPoint: .topLeading, endPoint: .bottomTrailing))
            .accessibilityLabel("Eat good, feel good")
    }
    private var emptyJournal: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.primary.opacity(0.04)).frame(height: 130)
                HStack(spacing: 14) {
                    ForEach(Array([("carrot.fill", Color.butter), ("leaf.fill", Color.matcha), ("fish.fill", Color.chili)].enumerated()), id: \.offset) { index, entry in
                        PlateIconTile(symbol: entry.0, tint: entry.1, size: 56)
                            .symbolEffect(.breathe, options: .speed(0.5))
                            .offset(y: index == 1 ? -8 : 4)
                    }
                }
            }
            Text("Your next good thing.").font(.system(.title2, design: .rounded, weight: .bold))
            Text("A quick photo, a familiar favourite, or something new. Every meal is a fresh start.").font(.subheadline).foregroundStyle(.secondary)
            Button { model.showCapture = true } label: { Label("Add your first plate", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(8) }.buttonStyle(.glassProminent).tint(Color.plateAccent)
        }.padding(24).plateCard()
    }
    private var quickCapture: some View {
        VStack(spacing: 12) {
            Button { typingMeal = true } label: {
                HStack(spacing: 15) {
                    Image(systemName: "text.bubble.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.plateAccent)
                        .frame(width: 56, height: 56).background(Color.plateAccent.opacity(0.16), in: .rect(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Type what you ate").font(.headline)
                        Text("\"Mie Gacoan level 3\", \"Kopi Kenangan Mantan\" · no photo needed").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "sparkles").font(.headline).foregroundStyle(Color.plateAccent).symbolEffect(.breathe, isActive: !reduceMotion)
                }.padding(20).plateCard()
            }.buttonStyle(PlatePress()).foregroundStyle(.primary)
            photoCapture
        }
    }
    private var photoCapture: some View {
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
                Text(storyMode == 0 ? dayGuidance.title : storyMode == 1 ? "Build a stronger plate." : "Every macro has a role.").font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.7)
                Text(storyMode == 0 ? "\(Int(abs(dayGuidance.remaining))) kcal \(dayGuidance.remaining < 0 ? "over" : "left")" : storyMode == 1 ? "\(Int(dayTotal.protein)) / \(Int(dayTargets.nutrients.protein)) g" : "\(Int(dayTotal.protein)) P · \(Int(dayTotal.carbs)) C · \(Int(dayTotal.fat)) F").font(.system(size: 32, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(storyMode == 0 ? dayGuidance.message : storyMode == 1 ? "\(Int(max(0,dayTargets.nutrients.protein-dayTotal.protein))) g of protein left toward today’s target. Tap a meal below to explore what’s on your plate." : "Protein and carbs provide about 4 kcal per gram; fat provides about 9. Your logged food determines this split.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.id(storyMode).transition(.opacity.combined(with: .offset(y: 6)))
            if isToday && model.store.account.settings.trainingDayTargets != nil {
                Toggle(isOn: Binding(get: { model.store.trainingToday }, set: { model.store.trainingToday = $0; model.sync.saveAccount(); model.store.publishWidget() })) { Label("Training day", systemImage: "dumbbell.fill").font(.subheadline.bold()) }.tint(Color.plateAccent)
            }
            HStack { Label("\(dayMeals.count) \(dayMeals.count == 1 ? "meal" : "meals")", systemImage: "fork.knife"); Spacer(); Label(model.sync.status, systemImage: model.sync.userID == nil ? "internaldrive" : "icloud") }.font(.caption).foregroundStyle(.secondary)
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
        NutritionOverage.evaluate(eaten: dayTotal, target: dayTargets.nutrients)
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
    /// The day's status, front and centre: room (violet), almost full (amber, pulsing), on target (green) or over (red, rippling).
    private var energyStatus: some View {
        let state = dayGuidance.state
        let target = dayTargets.nutrients.calories
        let eaten = dayTotal.calories
        let left = Int(max(0, target - eaten).rounded())
        let over = Int(max(0, eaten - target).rounded())
        let macroOvers = overages.filter { $0.id != "calories" }
        let info: (icon: String, title: String, detail: String) = switch state {
        case .calm: ("sparkles", macroOvers.isEmpty ? "Room to nourish" : "A macro went over", "\(left) kcal left \(dayWord)")
        case .almost: ("exclamationmark.triangle.fill", "Heads up, almost full", "Only \(left) kcal left \(dayWord)")
        case .hit: ("checkmark.seal.fill", "Bang on target", "You've fuelled the day. Nice.")
        case .over: ("exclamationmark.octagon.fill", "You've gone over", "+\(over) kcal past your \(Int(target)) kcal target")
        }
        let tint = macroOvers.isEmpty || state == .over ? state.color : Color.overRed
        let warning = state == .almost || state == .over || !macroOvers.isEmpty
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: info.icon).font(.system(size: 19, weight: .bold)).foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                .frame(width: 42, height: 42).background(tint.opacity(0.16), in: .circle)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title).font(.headline).contentTransition(.numericText(countsDown: goingBack))
                Text(info.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).contentTransition(.numericText(countsDown: goingBack))
                if !macroOvers.isEmpty {
                    Text(macroOvers.map { "\($0.name) +\(Int($0.excess.rounded(.up))) \($0.unit)" }.joined(separator: " · "))
                        .font(.caption.weight(.bold)).foregroundStyle(Color.overRed)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(warning ? 0.16 : 0.08), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay { if state == .over || !macroOvers.isEmpty { WarningRipple(color: .overRed, cornerRadius: 22).transition(.opacity) } }
        .animation(reduceMotion ? nil : Motion.turn, value: state)
        .accessibilityElement(children: .combine)
    }
    private var dashboardHeader: some View {
        VStack(spacing: 18) {
            energyStatus
            PlateDial(meals: dayMeals, target: dayTargets.nutrients.calories, tint: dayGuidance.state.color)
                .overlay { SparkBurst(trigger: burst, tint: dayGuidance.state.color) }
            Text("Tap the ring to switch eaten and left").font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                NutrientTile(name: "Protein", symbol: "bolt.fill", value: dayTotal.protein, target: dayTargets.nutrients.protein, tint: .chili)
                NutrientTile(name: "Carbs", symbol: "leaf.fill", value: dayTotal.carbs, target: dayTargets.nutrients.carbs, tint: .plateCarb)
                NutrientTile(name: "Fat", symbol: "drop.fill", value: dayTotal.fat, target: dayTargets.nutrients.fat, tint: .plateFat)
            }
        }.padding(20)
            .plateCard()
            .animation(reduceMotion ? nil : Motion.turn, value: dayTotal)
    }
}

/// The floating Liquid Glass header for Today: a day button in the middle with arrows either side, and settings on the right.
/// Everything sits in one glass container, so buttons melt out of and back into each other as they appear and disappear.
/// Swipe the day button sideways to move through days; tap it for every logged day.
private struct FloatingDayHeader: View {
    let title: String
    let selectedDay: Date
    let isToday: Bool
    let loggedDays: [Date]
    var goingBack = false
    let total: @MainActor (Date) -> Double
    let select: @MainActor (Date) -> Void
    let step: @MainActor (Int) -> Void
    let openSettings: (@MainActor () -> Void)?
    @Namespace private var glass
    @State private var drag: CGFloat = 0
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                if !isToday {
                    roundButton("arrow.uturn.backward", label: "Back to today", tint: .plateAccent) { select(.now) }
                        .glassEffectID("today", in: glass)
                }
                roundButton("chevron.left", label: "Previous day") { step(-1) }
                    .glassEffectID("back", in: glass)
                dayMenu.glassEffectID("day", in: glass)
                if !isToday {
                    roundButton("chevron.right", label: "Next day") { step(1) }
                        .glassEffectID("forward", in: glass)
                }
                if let openSettings {
                    roundButton("slider.horizontal.3", label: "Settings", action: openSettings)
                        .glassEffectID("settings", in: glass)
                }
            }
        }
        .animation(reduced ? nil : Motion.turn, value: isToday)
        .frame(maxWidth: .infinity)
        .onAppear { guard !reduced else { return }; withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { turning = true } }
    }
    private var dayMenu: some View {
        Menu {
            Button("Today", systemImage: "sun.max") { select(.now) }
            Section("Logged days") {
                ForEach(loggedDays.prefix(60), id: \.self) { day in
                    Button { select(day) } label: {
                        Label("\(TodayView.title(for: day)) · \(Int(total(day))) kcal", systemImage: Calendar.current.isDate(day, inSameDayAs: selectedDay) ? "checkmark" : "calendar")
                    }
                }
            }
        } label: {
            HStack(spacing: 9) {
                // A tiny aurora orb that keeps turning.
                Circle().fill(AngularGradient(colors: [.ube, .bubble, .butter, .matcha, .sky, .ube], center: .center))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(turning ? 360 : 0))
                Text(title).font(.headline).lineLimit(1)
                    .contentTransition(.numericText(countsDown: goingBack))
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .symbolEffect(.bounce, value: title)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .offset(x: drag)
        .scaleEffect(1 - min(abs(drag), 60) / 900)
        .simultaneousGesture(DragGesture(minimumDistance: 14)
            .onChanged { value in drag = value.translation.width * 0.35 }
            .onEnded { value in
                let move = value.translation.width
                if move > 50 { step(-1) } else if move < -50 { step(1) }
                withAnimation(reduced ? nil : .spring(response: 0.45, dampingFraction: 0.6)) { drag = 0 }
            })
        .accessibilityLabel("\(title). Choose a day")
    }
    private func roundButton(_ symbol: String, label: String, tint: Color? = nil, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
        .transition(.scale(scale: 0.4).combined(with: .opacity))
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
    /// Move the meal to another day or time, or change which meal it was. Saved with Done.
    private var whenCard: some View {
        let calendar = Calendar.current
        return VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "When")
            DatePicker("Day and time", selection: $meal.timestamp, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
            HStack(spacing: 8) {
                ForEach([("Today", 0), ("Yesterday", -1), ("2 days ago", -2)], id: \.1) { title, offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
                    let current = calendar.isDate(meal.timestamp, inSameDayAs: day)
                    Button(title) {
                        let time = calendar.dateComponents([.hour, .minute], from: meal.timestamp)
                        let moved = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { meal.timestamp = min(moved, .now) }
                    }
                    .font(.caption.weight(.semibold)).buttonStyle(.plain)
                    .foregroundStyle(current ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassEffect(current ? Glass.regular.tint(Color.plateAccent).interactive() : Glass.regular.interactive(), in: .capsule)
                }
            }
            Picker("Meal", selection: $meal.type) { ForEach(MealType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
        }.padding(18).plateCard()
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if meal.photoPath != nil { FoodPhoto(path: meal.photoPath).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 24)) }
                    Text("\(Int(meal.total.calories)) kcal · \(Int(meal.total.protein)) g protein").font(.title2.bold())
                    whenCard
                    ForEach(meal.items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            Button { editing = item.id } label: {
                                HStack { VStack(alignment: .leading, spacing: 5) { Text(item.name).font(.headline); Text("\(item.quantity.formatted()) × \(item.servingDescription)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(Int(item.total.calories)) kcal").monospacedDigit() }
                            }.buttonStyle(.plain)
                            Button { aiItem = item } label: { Label("Edit with AI (photo + words)", systemImage: "sparkles").fontWeight(.semibold) }
                                .buttonStyle(.glass).tint(Color.plateAccent).font(.caption)
                        }.padding(18).plateCard()
                    }
                    Button { addingWithAI = true } label: {
                        Label("Add food with AI (photo + words)", systemImage: "plus.bubble.fill").fontWeight(.semibold).frame(maxWidth: .infinity).padding(6)
                    }.buttonStyle(.glassProminent).tint(Color.plateAccent)
                    if !meal.isValid { Label("Check portions and nutrition values before saving.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                    if hasChanges { Text("Tap Done to save your changes and update Apple Health when connected.").font(.caption).foregroundStyle(.secondary) }
                    Button("Repeat this meal", systemImage: "arrow.clockwise") { model.repeatMeal(meal); dismiss() }.buttonStyle(.glassProminent).tint(Color.plateAccent)
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
            .onChange(of: meal.timestamp) { _, stamp in
                // Keep the stored day in step so the meal moves to its new day everywhere.
                meal.dayKey = DayKey.make(stamp); meal.timeZoneID = TimeZone.current.identifier
                hasChanges = true
            }
            .onChange(of: meal.type) { _, _ in hasChanges = true }
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
private enum TabChoice: Hashable { case page(Destination), capture }
#endif

#if os(iOS)
/// iPhone shows Today's day controls as a floating glass header; iPad puts them in the top bar row next to the floating tabs.
private struct TodayChrome<Header: View, Items: ToolbarContent>: ViewModifier {
    let compact: Bool
    @ViewBuilder let header: () -> Header
    @ToolbarContentBuilder let items: () -> Items
    func body(content: Content) -> some View {
        if compact {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { header() }
        } else {
            content
                .toolbar(removing: .title)
                .toolbar { items() }
        }
    }
}
#endif
