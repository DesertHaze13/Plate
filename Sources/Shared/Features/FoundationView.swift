import SwiftUI
import PlateCore

private enum Destination: String, CaseIterable, Identifiable {
    case today = "Today", history = "History", foods = "My Foods", progress = "Progress", settings = "Settings"
    var id: String { rawValue }
    var subtitle: String { switch self { case .today: "Your energy, at a glance"; case .history: "Every meal, remembered"; case .foods: "Favourites within reach"; case .progress: "See your rhythm"; case .settings: "Make yourself at home" } }
    var tint: Color { switch self { case .today: .plateMint; case .history: .plateCarb; case .foods: Color(red: 0.85, green: 0.42, blue: 0.48); case .progress: .plateFat; case .settings: Color(red: 0.35, green: 0.55, blue: 0.9) } }
    var icon: String { switch self { case .today: "circle.inset.filled"; case .history: "calendar"; case .foods: "fork.knife"; case .progress: "chart.xyaxis.line"; case .settings: "slider.horizontal.3" } }
}
#if os(iOS)
private enum CompactDestination: Hashable { case today, history, foods, progress, capture }
#endif
struct FoundationView: View {
    @State private var model: PlateModel
    // No default argument: a default PlateModel() would be built on every view rebuild.
    init(model: PlateModel) { _model = State(initialValue: model) }
    @State private var destination: Destination = .today
    #if os(iOS)
    @State private var compactDestination: CompactDestination = .today
    @State private var lastCompactDestination: CompactDestination = .today
    @State private var showCompactSettings = false
    #endif
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("plate✳︎").font(.system(size: 43, weight: .black, design: .rounded)).tracking(-2)
                        HStack { Text("FOOD / BODY / DAILY").font(.system(size: 9, weight: .semibold, design: .monospaced)); Spacer(); Image(systemName: "circle.inset.filled").foregroundStyle(Color.plateMint) }
                        Rectangle().fill(.primary).frame(height: 3)
                    }.padding(.top, 20)
                    SectionEyebrow(text: "THE DAILY INDEX")
                    VStack(spacing: 10) {
                        ForEach(Destination.allCases) { item in
                            Button { withAnimation(reducedMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8)) { destination = item } } label: {
                                HStack(spacing: 13) {
                                    PlateIconTile(symbol: item.icon, tint: item.tint)
                                    VStack(alignment: .leading, spacing: 4) { Text(item.rawValue).font(.system(.headline, design: .rounded)); Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                    Spacer(minLength: 0)
                                    if destination == item { Circle().fill(item.tint).frame(width: 5, height: 5) }
                                }.padding(12).background {
                                    if destination == item { RoundedRectangle(cornerRadius: 7).fill(Color.plateMint.opacity(0.10)).overlay(alignment: .leading) { Rectangle().fill(Color.plateMint).frame(width: 3) }.matchedGeometryEffect(id: "sidebar-selection", in: sidebarSelection) }
                                }
                            }.buttonStyle(PlatePress()).foregroundStyle(.primary).accessibilityAddTraits(destination == item ? .isSelected : [])
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Rectangle().fill(.primary.opacity(0.25)).frame(height: 1)
                        Text("A LITTLE\nMORE YUM.").font(.system(size: 29, weight: .black, design: .rounded)).tracking(-1)
                        Text("A record of how you fuel your life.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 8).padding(.vertical, 18)
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
    // System TabView owns hit testing, the lifted selection lens, refraction and
    // accessibility. A glassEffect over hand-built buttons cannot provide those.
    private var tabs: some View {
        TabView(selection: $compactDestination) {
            Tab("Today", systemImage: "circle.inset.filled", value: CompactDestination.today) { compactScreen(.today) }
            Tab("History", systemImage: "calendar", value: CompactDestination.history) { compactScreen(.history) }
            Tab("My Foods", systemImage: "fork.knife", value: CompactDestination.foods) { compactScreen(.foods) }
            Tab("Progress", systemImage: "chart.xyaxis.line", value: CompactDestination.progress) { compactScreen(.progress) }
            Tab("Log a meal", systemImage: "camera.fill", value: CompactDestination.capture, role: captureTabRole) {
                PlateBackground(status: .calm).overlay {
                    CaptureButton { model.showCapture = true }
                }
            }
        }
        .onChange(of: compactDestination) { _, selected in
            if selected == .capture { model.showCapture = true }
            else { lastCompactDestination = selected }
        }
        .onChange(of: model.showCapture) { _, showing in
            if !showing && compactDestination == .capture { compactDestination = lastCompactDestination }
        }
         .sheet(isPresented: $showCompactSettings) {
            NavigationStack { SettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showCompactSettings = false } } } }.environment(model)
        }
    }
    private var captureTabRole: TabRole? {
        if #available(iOS 27.0, *) { .prominent } else { nil }
    }
    private func compactScreen(_ item: Destination) -> some View {
        NavigationStack {
            screen(item)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "slider.horizontal.3") { showCompactSettings = true }
                } }
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
    private var goalStates: [TargetFillState] { TargetProgress.all(eaten: dayTotal, targets: dayTargets).map(\.state) }
    @State private var browsedDate: Date?
    @State private var showDayPicker = false
    private var selectedDate: Date { browsedDate ?? model.store.clock }
    private var isToday: Bool { Calendar.current.isDate(selectedDate, inSameDayAs: model.store.clock) }
    private var dayTitle: String { isToday ? "Today" : selectedDate.formatted(.dateTime.day().month(.abbreviated).year()) }
    private var dayMeals: [Meal] { model.store.meals.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: selectedDate) } }
    private var dayTotal: Nutrients { dayMeals.reduce(.zero) { $0 + $1.total } }
    private var dayTargets: Targets {
        HistoryMath.targets(on: selectedDate, rest: model.store.targets, training: model.store.account.settings.trainingDayTargets, trainingDayKeys: model.store.account.settings.trainingDayKeys ?? [])
    }
    private var dayGuidance: DailyGuidance { DailyGuidance(eaten: dayTotal, target: dayTargets) }
    private var dateBinding: Binding<Date> { Binding(get: { selectedDate }, set: { selectDay($0) }) }
    private func selectDay(_ date: Date) {
        let clamped = min(Calendar.current.startOfDay(for: date), Calendar.current.startOfDay(for: model.store.clock))
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            browsedDate = Calendar.current.isDate(clamped, inSameDayAs: model.store.clock) ? nil : clamped
            mealFilter = 0
        }
    }
    @State private var warningFeedback = 0
    @State private var metFeedback = 0
    @State private var storyMode = 0
    @State private var mealFilter = 0
    private var visibleMeals: [Meal] { dayMeals.filter { mealFilter == 0 || $0.type == MealType.allCases[mealFilter - 1] } }
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
                    statementHeader
                    daySelector
                    dashboardHeader
                    TargetWarningStrip(progress: TargetProgress.all(eaten: dayTotal, targets: dayTargets))
                    let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
                    layout {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) { SectionEyebrow(text: "02 / THE FOOD RECORD"); Text("What made the plate.").font(.system(.title2, design: .rounded, weight: .bold)) }
                                Spacer()
                                Text("\(dayMeals.count)").font(.headline.monospacedDigit()).frame(width: 38, height: 38).background(Color.plateMint.opacity(0.12), in: .circle)
                            }.padding(.top, 6)
                            if dayMeals.isEmpty {
                                if isToday { emptyJournal }
                                else { ContentUnavailableView("Belum ada catatan", systemImage: "calendar", description: Text("Tidak ada makanan tercatat pada tanggal ini.")).plateCard() }
                            }
                            PlateSegmentedControl(options: ["All"] + MealType.allCases.map { $0.rawValue.capitalized }, selection: $mealFilter)
                            if visibleMeals.isEmpty && !dayMeals.isEmpty { Text("No meals in this moment yet.").font(.subheadline).foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity).plateCard() }
                            ForEach(visibleMeals) { meal in mealCard(meal).transition(.opacity.combined(with: .move(edge: .bottom))) }
                            DisclosureGroup("Read the day") { dayStory }.font(.subheadline.bold())
                            if let error = model.store.error ?? model.sync.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        }.frame(maxWidth: .infinity)
                        VStack(spacing: 22) {
                            TargetWarningsCard(eaten: dayTotal, targets: dayTargets, dayLabel: isToday ? "Hari ini" : "\(dayTitle) · target saat ini")
                            if isToday { quickCapture }
                        }.frame(maxWidth: wide ? 360 : .infinity)
                    }
                }.padding(geometry.size.width < 500 ? 20 : 30).frame(maxWidth: 1440).frame(maxWidth: .infinity)
            }
            .scrollEdgeEffectHidden(true, for: .top)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 440 } action: { _, pinned in pinnedHeader = pinned }
        }
        .safeAreaInset(edge: .top, spacing: 0) { if pinnedHeader { pinnedSummary.padding(.horizontal, 18).padding(.bottom, 8).transition(.move(edge: .top).combined(with: .opacity)) } }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: pinnedHeader)
        .background(PlateBackground(status: dayGuidance.state)).navigationTitle(dayTitle)
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        #else
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .toolbar { ToolbarItem(placement: .principal) {
            Button { showDayPicker = true } label: {
                HStack(spacing: 6) { Text(dayTitle).font(.headline); Image(systemName: "chevron.down").font(.caption2.bold()) }
            }.buttonStyle(.plain).accessibilityLabel("Pilih tanggal, \(dayTitle)")
        } }
        .sheet(isPresented: $showDayPicker) {
            NavigationStack {
                VStack(spacing: 18) {
                    PlateCalendar(selection: dateBinding)
                    Button("Kembali ke Today") { selectDay(model.store.clock); showDayPicker = false }.buttonStyle(.borderedProminent)
                    Text("Pilih tanggal untuk melihat makanan, grafik dan total hari itu. Perbandingan memakai target yang saat ini diatur.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).navigationTitle("Pilih hari")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { showDayPicker = false } } }
            }
            #if os(macOS)
            .frame(width: 430, height: 500)
            #else
            .presentationDetents([.large])
            #endif
        }
        .sheet(item: $selectedMeal) { meal in
            #if os(iOS)
            if reduceMotion { MealDetailView(meal: meal).environment(model) }
            else { MealDetailView(meal: meal).environment(model).navigationTransition(.zoom(sourceID: meal.id, in: mealNamespace)) }
            #else
            MealDetailView(meal: meal).environment(model)
            #endif
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: mealFilter)
        .onChange(of: goalStates) { old, new in targetStatesChanged(from: old, to: new) }
        .sensoryFeedback(.warning, trigger: warningFeedback)
        .sensoryFeedback(.success, trigger: metFeedback)
    }
    private func targetStatesChanged(from old: [TargetFillState], to new: [TargetFillState]) {
        guard isToday else { return }
        var warn = false
        var met = false
        for (index, state) in new.enumerated() where old.indices.contains(index) && old[index] != state {
            if state == .near || state == .over { warn = true }
            if state == .met { met = true }
        }
        if warn { warningFeedback += 1 }
        else if met { metFeedback += 1 }
    }

    private var statementHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("PLATE / \(selectedDate.formatted(.dateTime.day().month(.abbreviated)))").font(.system(.caption, design: .monospaced, weight: .bold)); Spacer(); Text("LET’S EAT ✳︎").font(.caption.bold()).padding(9).background(Color.plateCarb.opacity(0.16), in: .capsule).rotationEffect(.degrees(-5)) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { playfulTitle.frame(minWidth: 260); BitePlayground().frame(width: 340) }
                VStack(alignment: .leading, spacing: 4) { playfulTitle; BitePlayground().frame(maxWidth: .infinity) }
            }
            PlayfulTicker()
        }.padding(.bottom, 4)
    }
    private var playfulTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BIG BITES.\nGOOD ENERGY.").font(.system(size: 49, weight: .black, design: .rounded)).tracking(-2).lineSpacing(-5).lineLimit(2).minimumScaleFactor(0.65).fixedSize(horizontal: false, vertical: true)
            Text(isToday ? "Your daily dose of delicious." : "Rewind the bites. Keep the good stuff.").font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var daySelector: some View {
        VStack(spacing: 12) {
            HStack {
                Button { selectDay(Calendar.current.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }.accessibilityLabel("Tujuh hari sebelumnya")
                Spacer()
                Button { showDayPicker = true } label: { Label(selectedDate.formatted(.dateTime.month(.wide).year()), systemImage: "calendar").font(.subheadline.bold()) }
                Spacer()
                Button { selectDay(Calendar.current.date(byAdding: .day, value: 7, to: selectedDate) ?? selectedDate) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }.disabled(isToday).accessibilityLabel("Tujuh hari berikutnya")
            }
            HStack(spacing: 4) {
                ForEach((0..<7).reversed(), id: \.self) { offset in
                    let end = Calendar.current.isDate(selectedDate, equalTo: model.store.clock, toGranularity: .weekOfYear) ? model.store.clock : selectedDate
                    let date = Calendar.current.date(byAdding: .day, value: -offset, to: end) ?? end
                    let active = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    let hasMeals = model.store.meals.contains { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
                    Button { selectDay(date) } label: {
                        VStack(spacing: 7) {
                            Text(date, format: .dateTime.weekday(.abbreviated)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Text(date, format: .dateTime.day()).font(.system(.headline, design: .rounded))
                            Circle().fill(hasMeals ? Color.plateMint : .clear).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(active ? Color.plateMint.opacity(0.22) : Color.plateMint.opacity(0.04), in: .rect(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(active ? Color.plateMint.opacity(0.55) : .clear))
                    }.accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(hasMeals ? "ada catatan makanan" : "tanpa catatan")").accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            if !isToday { Button("Kembali ke Today") { selectDay(model.store.clock) }.font(.caption.bold()) }
        }.buttonStyle(PlatePress()).foregroundStyle(.primary).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.2)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.2)).frame(height: 1) }
    }

    private var emptyJournal: some View {
        VStack(alignment: .leading, spacing: 18) {
            BitePlayground().frame(maxWidth: .infinity)
            Text("Your next delicious plot twist.").font(.system(.title3, design: .rounded, weight: .black))
            Text("Drop a photo, tell AI what’s on the plate, and make it yours.").font(.subheadline).foregroundStyle(.secondary)
            Button { model.showCapture = true } label: { Label("Feed the plot", systemImage: "camera.fill").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(16).foregroundStyle(.white).background(Color.plateCobalt, in: .capsule) }.buttonStyle(PlatePress())
        }.padding(22).plateCard()
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
                Text(storyMode == 0 ? (isToday ? dayGuidance.title : "Ringkasan hari terpilih") : storyMode == 1 ? "Build a stronger plate." : "Every macro has a role.").font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.7)
                Text(storyMode == 0 ? "\(Int(abs(dayGuidance.remaining))) kcal \(dayGuidance.remaining < 0 ? "over" : "left")" : storyMode == 1 ? "\(Int(dayTotal.protein)) / \(Int(dayTargets.nutrients.protein)) g" : "\(Int(dayTotal.protein)) P · \(Int(dayTotal.carbs)) C · \(Int(dayTotal.fat)) F").font(.system(size: 32, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(storyMode == 0 ? (isToday ? dayGuidance.message : "Ringkasan makanan pada \(dayTitle). Perbandingan menggunakan target yang saat ini diatur.") : storyMode == 1 ? "\(Int(max(0,dayTargets.nutrients.protein-dayTotal.protein))) g of protein left toward today’s target. Tap a meal below to explore what’s on your plate." : "Protein and carbs provide about 4 kcal per gram; fat provides about 9. Your logged food determines this split.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.id(storyMode).transition(.opacity.combined(with: .offset(y: 6)))
            if isToday && model.store.account.settings.trainingDayTargets != nil {
                Toggle(isOn: Binding(get: { model.store.trainingToday }, set: { model.store.trainingToday = $0; model.sync.saveAccount(); model.store.publishWidget() })) { Label("Training day", systemImage: "dumbbell.fill").font(.subheadline.bold()) }.tint(Color.plateMint)
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
    @ViewBuilder private var pinnedSummary: some View {
        let progress = TargetProgress.all(eaten: dayTotal, targets: dayTargets)
        if progress.contains(where: { $0.state == .over }) { TargetWarningStrip(progress: progress, compact: true).background(.background, in: .rect(cornerRadius: 22)) }
        else { stickyHeader }
    }
    private var stickyHeader: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 10) {
                HStack {
                    Text("\(Int(dayTotal.calories)) / \(Int(dayTargets.nutrients.calories)) kcal").font(.headline.monospacedDigit()).contentTransition(.numericText())
                    Spacer()
                    Text("\(Int(abs(dayGuidance.remaining))) \(dayGuidance.remaining < 0 ? "over" : "left")").font(.subheadline.weight(.semibold)).foregroundStyle(dayGuidance.state.color).contentTransition(.numericText())
                }
                HStack {
                    Text("P \(Int(dayTotal.protein))/\(Int(dayTargets.nutrients.protein))g").foregroundStyle(Color.plateMint)
                    Spacer()
                    Text("C \(Int(dayTotal.carbs))/\(Int(dayTargets.nutrients.carbs))g").foregroundStyle(Color.plateCarb)
                    Spacer()
                    Text("F \(Int(dayTotal.fat))/\(Int(dayTargets.nutrients.fat))g").foregroundStyle(Color.plateFat)
                }.font(.caption.monospacedDigit())
            }.padding(15)
                .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 20))
                .glassEffectID("nutrition-glance", in: headerNamespace)
                .background { if reduceTransparency { RoundedRectangle(cornerRadius: 20).fill(.background) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily progress. \(Int(dayTotal.calories)) of \(Int(dayTargets.nutrients.calories)) calories. Protein \(Int(dayTotal.protein)) of \(Int(dayTargets.nutrients.protein)) grams. Carbs \(Int(dayTotal.carbs)) grams. Fat \(Int(dayTotal.fat)) grams.")
        }
    }
    private var dashboardHeader: some View {
        SlimPlateHero(meals: dayMeals, targets: dayTargets, dayTitle: isToday ? "TODAY" : dayTitle.uppercased(), energyTitle: isToday ? "Energi hari ini" : "Energi tercatat").id(DayKey.make(selectedDate))
    }

}

struct MealCard: View {
    let meal: Meal
    var body: some View {
        HStack(spacing: 16) {
            FoodPhoto(path: meal.thumbnailPath ?? meal.photoPath).frame(width: 82, height: 92).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 7) {
                Text(meal.type.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
                Text(meal.items.map(\.name).joined(separator: ", ")).font(.system(.headline, design: .rounded)).lineLimit(2)
                Text("\(meal.timestamp.formatted(.dateTime.hour().minute())) · \(Int(meal.total.protein)) g protein").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) { Text(meal.total.calories, format: .number.precision(.fractionLength(0))).font(.title3.weight(.semibold).monospacedDigit()); Text("kcal").font(.caption2).foregroundStyle(.secondary) }
        }.padding(18).plateCard().foregroundStyle(.primary).contentShape(RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .combine)
    }
}
struct MealDetailView: View {
    @State var meal: Meal
    @Environment(PlateModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: String?
    @State private var aiEditing: String?
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if meal.photoPath != nil { FoodPhoto(path: meal.photoPath).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 24)) }
                    Text("\(Int(meal.total.calories)) kcal · \(Int(meal.total.protein)) g protein").font(.title2.bold())
                    Text("Hasil AI adalah draf. Tekan Simpan untuk memperbarui catatan; Batal mempertahankan catatan sebelumnya.").font(.caption).foregroundStyle(.secondary)
                    ForEach(meal.items) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { editing = item.id } label: { HStack { VStack(alignment: .leading) { Text(item.name).font(.headline); Text("\(item.quantity.formatted()) × \(item.servingDescription)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(Int(item.total.calories)) kcal"); Image(systemName: "slider.horizontal.3") }.padding(18).plateCard() }.buttonStyle(.plain)
                            HStack {
                                Button("Edit dengan AI", systemImage: "sparkles") { aiEditing = item.id }.buttonStyle(.bordered)
                                if !(item.needsReviewFields ?? []).isEmpty { Button("Periksa hasil") { editing = item.id }.foregroundStyle(.orange) }
                            }.font(.caption.bold())
                        }
                    }
                    Button("Repeat this meal", systemImage: "arrow.clockwise") { model.repeatMeal(meal); dismiss() }.buttonStyle(.borderedProminent).tint(Color.plateMint)
                    Button("Save foods to My Foods", systemImage: "bookmark") { for item in meal.items { model.store.saveFood(item) }; model.sync.saveAccount(); model.notice = "Saved to My Foods." }
                    Button("Delete meal", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }.padding(24)
            }.navigationTitle(meal.type.rawValue.capitalized).background(PlateBackground(status: .calm))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Simpan") { meal.updatedAt = .now; model.sync.save(meal); dismiss() }.disabled(!meal.isValid || meal.items.contains { !($0.needsReviewFields ?? []).isEmpty }) } }
            .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) { if let index = meal.items.firstIndex(where: { $0.id == editing }) { FoodItemEditor(item: $meal.items[index], existingPhotoPath: meal.photoPath) } }
            .sheet(isPresented: Binding(get: { aiEditing != nil }, set: { if !$0 { aiEditing = nil } })) { if let index = meal.items.firstIndex(where: { $0.id == aiEditing }) { FoodAIRevisionView(item: $meal.items[index], existingPhotoPath: meal.photoPath).environment(model) } }
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
