import SwiftUI

import PlateCore

struct OnboardingView: View {
    @Environment(PlateModel.self) private var model
    @State private var profile = Profile()
    @State private var metric = true
    @State private var page = 0
    private var valid: Bool { (18...100).contains(profile.age) && (100...250).contains(profile.heightCM) && (30...350).contains(profile.weightKG) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack { Image(systemName: "circle.inset.filled").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Color.plateAccent); Spacer(); SectionEyebrow(text: "Plate / Welcome") }
                    PlatePageTitle(eyebrow: "A FRESH START", title: "Good energy starts here.", subtitle: "A little context. A plan that feels like you.")
                    Text("A little context helps us set your starting targets. You can change every number later.").foregroundStyle(.secondary)
                    if model.sync.configured, model.sync.userID == nil {
                        Button { Task { await model.sync.signInWithGoogle() } } label: { Label("Continue with Google", systemImage: "person.crop.circle").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.bordered).disabled(model.sync.signingIn)
                        if let error = model.sync.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    }
                    #if os(iOS)
                    Button {
                        Task {
                            do { try await model.connectHealth(); if let reading = model.healthProfile { withAnimation(.spring(response: 0.6)) { profile = PlateModel.merge(reading, into: profile) } } }
                            catch { model.notice = error.localizedDescription }
                        }
                    } label: { Label("Fill in from Apple Health", systemImage: "heart.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.bordered).tint(.pink).plateEntrance(1)
                    #endif
                    ProfileFields(profile: $profile, metric: $metric).plateEntrance(2)
                    EnergyMathCard(profile: profile).plateEntrance(3)
                    Button {
                        model.store.account.settings.metric = metric
                        model.finishOnboarding(profile: profile, targets: NutritionCalculator.targets(for: profile))
                    } label: { Text("Make room for progress").fontWeight(.semibold).frame(maxWidth: .infinity).padding(10) }.buttonStyle(.borderedProminent).tint(Color.plateAccent).disabled(!valid)
                }.padding(28).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(PlateBackground(status: .calm))
        }
        #if os(macOS)
        .frame(width: 640, height: 800)
        #endif
    }
}
struct ProfileFields: View {
    @Binding var profile: Profile
    @Binding var metric: Bool
    @Environment(PlateModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PlateSegmentedControl(options: ["Lean bulk", "Recomp", "Cut"], selection: Binding(get: { [Goal.leanBulk, .recomp, .cut].firstIndex(of: profile.goal) ?? 0 }, set: { profile.goal = [Goal.leanBulk, .recomp, .cut][$0] })).accessibilityLabel("Goal")
            PlateSegmentedControl(options: ["Metric", "Imperial"], selection: Binding(get: { metric ? 0 : 1 }, set: { metric = $0 == 0 })).accessibilityLabel("Units")
            HStack { Text("Age"); Spacer(); TextField("Years", value: $profile.age, format: .number).multilineTextAlignment(.trailing).frame(width: 100); Text("years").font(.caption).foregroundStyle(.secondary) }
            Picker("Sex for BMR calculation", selection: $profile.male) { Text("Male").tag(true); Text("Female").tag(false) }
            HStack { Text("Height"); Spacer(); TextField("Height", value: Binding(get: { metric ? profile.heightCM : profile.heightCM/2.54 }, set: { profile.heightCM = metric ? $0 : $0*2.54 }), format: .number.precision(.fractionLength(0...1))).multilineTextAlignment(.trailing).frame(width: 100); Text(metric ? "cm" : "in").font(.caption).foregroundStyle(.secondary) }
            HStack { Text("Weight"); Spacer(); TextField("Weight", value: Binding(get: { metric ? profile.weightKG : profile.weightKG*2.2046226218 }, set: { profile.weightKG = metric ? $0 : $0/2.2046226218 }), format: .number.precision(.fractionLength(0...1))).multilineTextAlignment(.trailing).frame(width: 100); Text(metric ? "kg" : "lb").font(.caption).foregroundStyle(.secondary) }
            if let measured = profile.measuredActiveKcal {
                HStack {
                    Label { VStack(alignment: .leading, spacing: 2) { Text("Activity from Apple Health"); Text("\(Int(measured)) kcal a day, 14-day average").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "applewatch.radiowaves.left.and.right").foregroundStyle(.pink).symbolEffect(.variableColor.iterative) }
                    Spacer()
                    Button("Use estimate") { withAnimation(.spring(response: 0.45)) { profile.measuredActiveKcal = nil } }.font(.caption)
                }.transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                Picker("Daily activity, including training", selection: $profile.activityMultiplier) { Text("Mostly seated").tag(1.2); Text("Lightly active").tag(1.375); Text("Moderately active").tag(1.55); Text("Very active").tag(1.725); Text("Physical work + training").tag(1.9) }
                #if os(iOS)
                Button {
                    Task {
                        do {
                            try await model.connectHealth()
                            if let average = await model.health.averageActiveEnergy() { withAnimation(.spring(response: 0.45)) { profile.measuredActiveKcal = average.rounded() } }
                            else { model.notice = "Apple Health needs at least 3 days of activity data first." }
                        } catch { model.notice = error.localizedDescription }
                    }
                } label: { Label("Use my real activity from Apple Health", systemImage: "heart.text.square") }.font(.subheadline)
                #endif
            }
            Stepper("Training: \(profile.trainingDays) days / week", value: $profile.trainingDays, in: 0...7)
            Text("Your daily calorie ceiling").font(.headline)
            Text("This is a maximum, independent of the goal estimate. Training and workout calories never raise it.").font(.caption).foregroundStyle(.secondary)
            if profile.dailyCalorieCeiling > 0 {
                HStack { Text("Never go above"); Spacer(); TextField("kcal", value: Binding(get: { profile.dailyCalorieCeiling }, set: { if $0.isFinite && $0 > 0 { profile.calorieCap = $0 } }), format: .number.precision(.fractionLength(0))).multilineTextAlignment(.trailing).frame(width: 100); Text("kcal").font(.caption).foregroundStyle(.secondary) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                if let cap = profile.calorieCap, cap < NutritionCalculator.bmr(for: profile) { Text("That's below your resting burn. Going this low for long is hard to sustain.").font(.caption).foregroundStyle(.orange) }
            }
        }.textFieldStyle(.roundedBorder).padding(22).plateCard()
    }
}
struct SettingsView: View {
    @Environment(PlateModel.self) private var model
    @State private var profile = Profile()
    @State private var targets = NutritionCalculator.targets(for: Profile())
    @State private var settings = AppSettings()
    @State private var trainingTargets = NutritionCalculator.targets(for: Profile())
    @State private var separateTraining = false
    @State private var healthEnabled = UserDefaults.standard.bool(forKey: "healthEnabled")
    @AppStorage("cloudRecognitionAllowed") private var cloudAllowed = true
    @AppStorage("geminiModel") private var geminiModel = "gemini-3.5-flash-lite"
    @AppStorage("plateAppearance") private var appearance: PlateAppearance = .system
    @State private var saved = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var valid: Bool { targets.nutrients.isValid && targets.nutrients.calories > 0 && targets.nutrients.protein > 0 && (0.5...1).contains(targets.warningFraction) && targets.tolerance >= 0 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlatePageTitle(eyebrow: "MAKE IT YOURS", title: "Built around you.", subtitle: "Your goals, your rhythm, your Plate.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 22, alignment: .top)], alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow(text: "Appearance")
                    Picker("Appearance", selection: $appearance) {
                        ForEach(PlateAppearance.allCases) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.segmented)
                    Text("Light uses warm porcelain; Dark uses charcoal. System follows your device. Your choice is saved on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).plateCard()

                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow(text: "Across your devices")
                    Label(model.sync.status, systemImage: "icloud").font(.headline)
                    if model.sync.configured {
                        if model.sync.userID == nil { Button { Task { await model.sync.signInWithGoogle() } } label: { Label(model.sync.signingIn ? "Signing in…" : "Continue with Google", systemImage: "person.crop.circle").padding(8) }.buttonStyle(.bordered).disabled(model.sync.signingIn) }
                        else { Text("Your meals, foods, targets and weight log sync with your Google account.").font(.caption).foregroundStyle(.secondary); Button("Sign out", action: model.sync.signOut) }
                    } else { Text("Firebase configuration is unavailable in this build. Your data is saved on this device.").font(.caption).foregroundStyle(.secondary) }
                    if let error = model.sync.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).plateCard()
                VStack(spacing: 14) {
                    ProfileFields(profile: $profile, metric: $settings.metric)
                    EnergyMathCard(profile: profile)
                    Button("Reset targets to this calculation") { withAnimation(.spring(response: 0.5)) { recalculate() } }.buttonStyle(.bordered).tint(Color.plateAccent)
                }.buttonStyle(.bordered)
                TargetFields(title: "Daily targets", targets: $targets)
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Different targets on training days", isOn: $separateTraining).tint(Color.plateAccent)
                    if let cap = profile.calorieCap { Text("Training days also stay at or under \(Int(cap)) kcal.").font(.caption).foregroundStyle(.secondary) }
                    if separateTraining { TargetFields(title: "Training day", targets: $trainingTargets) }
                    HStack { Text("Almost-there threshold"); Spacer(); TextField("Fraction", value: $targets.warningFraction, format: .percent).multilineTextAlignment(.trailing).frame(width: 90) }
                    HStack { Text("On-target tolerance"); Spacer(); TextField("kcal", value: $targets.tolerance, format: .number).multilineTextAlignment(.trailing).frame(width: 90); Text("kcal").foregroundStyle(.secondary) }
                }.padding(22).plateCard()
                VStack(alignment: .leading, spacing: 16) {
                    SectionEyebrow(text: "Meal photos")
                    Text("Photos belong in your cloud, not your camera roll.").font(.headline)
                    Text("When signed in, photos upload to Firebase. Temporary upload copies are removed after success; the upload queue is limited to 20 MB. Downloaded photos stay in memory only. Offline or failed uploads wait safely for a retry.").font(.caption).foregroundStyle(.secondary)
                    Text(model.sync.userID == nil ? "Sign in to keep meal photos. Until then, new meals save nutrition only." : "Cloud photo storage is ready for your account.").font(.caption).foregroundStyle(.secondary)
                    Text("Firebase also manages a disk cache with a 100 MB cleanup target; it can temporarily exceed that target.").font(.caption).foregroundStyle(.secondary)
                    Button("Clear downloaded photo copies") { PhotoStore.shared.clearDownloadedCache(); model.notice = "Downloaded photo copies cleared. Pending uploads were kept safe." }
                }.padding(22).plateCard()
                AIAccountsCard()
                VStack(alignment: .leading, spacing: 16) {
                    SectionEyebrow(text: "Recognition")
                    Toggle("Allow cloud fallback", isOn: $cloudAllowed).tint(Color.plateAccent)
                    Text("Allow photos and food descriptions to be sent to your enabled AI accounts, in order, followed by the configured Gemini fallback. Printed-label OCR runs on your device. Apple Intelligence is available as a final fallback.").font(.caption).foregroundStyle(.secondary)
                    TextField("Gemini model", text: $geminiModel).textFieldStyle(.roundedBorder)
                }.padding(22).plateCard()
                VStack(alignment: .leading, spacing: 16) {
                    SectionEyebrow(text: "Evening check-in")
                    Toggle("Daily summary notification", isOn: $settings.summaryEnabled).tint(Color.plateAccent).onChange(of: settings.summaryEnabled) { _, enabled in if enabled { Task { do { if !(try await SummaryNotifications.request()) { settings.summaryEnabled = false; model.notice = "Notifications are off. You can enable them in system settings." } } catch { model.notice = error.localizedDescription } } } }
                    Stepper("Summary at \(settings.summaryHour):00", value: $settings.summaryHour, in: 0...23)
                    Text("Plate updates today's scheduled summary when you open the app or log a meal.").font(.caption).foregroundStyle(.secondary)
                }.padding(22).plateCard()
                #if os(iOS)
                VStack(alignment: .leading, spacing: 16) {
                    HStack { SectionEyebrow(text: "Apple Health"); Spacer(); Image(systemName: "heart.fill").foregroundStyle(.pink).symbolEffect(.pulse, isActive: healthEnabled) }
                    Toggle("Sync with Apple Health", isOn: $healthEnabled).tint(Color.plateAccent).onChange(of: healthEnabled) { _, enabled in
                        if enabled { Task { do { try await model.connectHealth() } catch { healthEnabled = false; model.notice = error.localizedDescription } } }
                        else { UserDefaults.standard.set(false, forKey: "healthEnabled") }
                    }
                    Text("Every food you log is saved to Health as a food, with its calories, protein, carbs, fat, fiber and sugar. Coffee and other drinks include caffeine when you enter or confirm its amount. Plate reads your age, sex, height and weight from Health so you don't have to type them, and uses your workouts and energy burned on the Progress screen.").font(.caption).foregroundStyle(.secondary)
                    Text("Health controls its own categories: coffee is saved by name as food, with its dietary caffeine. Missing or unshared Health values remain editable here. Blood pressure is for reference only.").font(.caption).foregroundStyle(.secondary)
                    if healthEnabled, let reading = model.healthProfile, !reading.isEmpty { HealthBodyGrid(reading: reading, metric: settings.metric).transition(.opacity.combined(with: .scale(scale: 0.96))) }
                    if healthEnabled {
                        if let message = model.nutritionSyncMessage {
                            HStack(alignment: .top, spacing: 10) {
                                if model.nutritionSyncing { ProgressView().controlSize(.small) }
                                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("Your meal history syncs automatically when you open Plate, connect Health or save changes. Failed entries are retried. You can review Plate’s nutrition permissions in Apple Health.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Refresh", systemImage: "arrow.triangle.2.circlepath") { Task { await model.refreshHealth(); model.notice = "Updated from Apple Health." } }
                            Spacer()
                            Button("Sync meal history", systemImage: "square.and.arrow.up") {
                                model.scheduleNutritionSync(refresh: true)
                            }.disabled(model.nutritionSyncing)
                        }.font(.subheadline)
                    }
                }.padding(22).plateCard().animation(reduced ? nil : .spring(response: 0.5), value: model.healthProfile)
                #endif
                }
                Button {
                    model.store.account.profile = profile; model.store.targets = targets
                    settings.trainingDayTargets = separateTraining ? trainingTargets.capped(at: profile.dailyCalorieCeiling) : nil; model.store.account.settings = settings
                    model.sync.saveAccount(); saved = true; Task { await SummaryNotifications.schedule(store: model.store) }
                } label: { Text(saved ? "Saved" : "Save changes").fontWeight(.semibold).frame(maxWidth: .infinity).padding(10) }.buttonStyle(.borderedProminent).tint(Color.plateAccent).disabled(!valid)
                Text("Plate 1.0 · Native on iPhone, iPad and Mac").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.navigationTitle("Settings").background(PlateBackground(status: .calm))
        .onAppear { profile = model.store.account.profile; targets = model.store.targets; settings = model.store.account.settings; separateTraining = settings.trainingDayTargets != nil; trainingTargets = (settings.trainingDayTargets ?? targets).capped(at: profile.dailyCalorieCeiling) }
        // Targets follow profile edits; you can still fine-tune them afterwards.
        .onChange(of: profile) { _, newValue in if newValue != model.store.account.profile { recalculate(); saved = false } }
        .onChange(of: targets) { _, value in
            let capped = value.capped(at: profile.dailyCalorieCeiling)
            if capped != value { targets = capped }
        }
        .onChange(of: trainingTargets) { _, value in
            let capped = value.capped(at: profile.dailyCalorieCeiling)
            if capped != value { trainingTargets = capped }
        }
        // Values pulled in from Apple Health appear here straight away.
        .onChange(of: model.store.account.profile) { _, newValue in profile = newValue; targets = model.store.targets }
    }
    private func recalculate() {
        var next = NutritionCalculator.targets(for: profile)
        next.warningFraction = targets.warningFraction; next.tolerance = targets.tolerance
        targets = next
        trainingTargets = trainingTargets.capped(at: profile.dailyCalorieCeiling)
    }
}
/// Shows each step from resting burn to the daily target, so the number never feels arbitrary.
struct EnergyMathCard: View {
    let profile: Profile
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var breakdown: EnergyBreakdown { NutritionCalculator.breakdown(for: profile) }
    private var macros: Nutrients { NutritionCalculator.targets(for: profile).nutrients }
    private var goalName: String { switch profile.goal { case .leanBulk: "Lean bulk"; case .recomp: "Recomp"; case .cut: "Cut" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "How your target is worked out")
            row("Resting burn", "Mifflin–St Jeor, from age, sex, height, weight", breakdown.bmr)
            if breakdown.usesMeasuredActivity { row("Movement", "Apple Health, 14-day average", breakdown.maintenance - breakdown.bmr, signed: true) }
            else { row("Activity", "× \(profile.activityMultiplier.formatted()) (already includes training)", breakdown.maintenance - breakdown.bmr, signed: true) }
            Divider()
            row("Maintenance", "Roughly what you burn in a day", breakdown.maintenance)
            row(goalName, "\(breakdown.goalChange > 0 ? "+" : "")\(Int((breakdown.goalChange * 100).rounded()))% of maintenance", breakdown.goalCalories - breakdown.maintenance, signed: true)
            if breakdown.capped { row("Ceiling", "Your daily maximum", breakdown.calories - breakdown.goalCalories, signed: true).transition(.opacity.combined(with: .move(edge: .top))) }
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Daily target").font(.headline)
                Spacer()
                Text(Int(breakdown.calories.rounded()), format: .number).font(.system(size: 34, weight: .bold, design: .rounded)).contentTransition(.numericText(value: breakdown.calories))
                Text("kcal").font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Int(macros.protein)) g protein · \(Int(macros.carbs)) g carbs · \(Int(macros.fat)) g fat").font(.caption).foregroundStyle(.secondary).contentTransition(.numericText())
            Text("Starting estimates, not a measurement of your metabolism. Adjust as your weight trend develops.").font(.caption2).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).plateCard()
            .animation(reduced ? nil : .spring(response: 0.55, dampingFraction: 0.8), value: breakdown)
    }
    private func row(_ title: String, _ detail: String, _ value: Double, signed: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Text((signed && value > 0 ? "+" : "") + Int(value.rounded()).formatted()).font(.subheadline.monospacedDigit().weight(.semibold)).contentTransition(.numericText(value: value))
        }
    }
}
/// Body readings pulled from Apple Health.
struct HealthBodyGrid: View {
    let reading: HealthProfile
    let metric: Bool
    private var chips: [(symbol: String, title: String, value: String, tint: Color)] {
        var list: [(symbol: String, title: String, value: String, tint: Color)] = []
        if let age = reading.age { list.append(("birthday.cake.fill", "Age", "\(age) years", .plateCarb)) }
        if let height = reading.heightCM { list.append(("ruler.fill", "Height", metric ? "\(Int(height.rounded())) cm" : "\(Int((height / 2.54).rounded())) in", .plateFat)) }
        if let weight = reading.weightKG { list.append(("scalemass.fill", "Weight", metric ? String(format: "%.1f kg", weight) : String(format: "%.1f lb", weight * 2.2046226218), .plateAccent)) }
        if let systolic = reading.systolic, let diastolic = reading.diastolic { list.append(("heart.text.square.fill", "Blood pressure", "\(Int(systolic))/\(Int(diastolic))", .pink)) }
        if let heartRate = reading.restingHeartRate { list.append(("waveform.path.ecg", "Resting heart rate", "\(Int(heartRate)) bpm", .red)) }
        return list
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: chip.symbol).foregroundStyle(chip.tint).symbolEffect(.bounce, value: chip.value)
                    Text(chip.value).font(.system(.headline, design: .rounded)).contentTransition(.numericText())
                    Text(chip.title).font(.caption2).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(chip.tint.opacity(0.08), in: .rect(cornerRadius: 16))
                    .plateEntrance(index)
            }
        }
        if let date = reading.bloodPressureDate { Text("Blood pressure from \(date.formatted(date: .abbreviated, time: .omitted)). Shown for reference; it doesn't change your targets.").font(.caption2).foregroundStyle(.secondary) }
    }
}
struct TargetFields: View {
    let title: String
    @Binding var targets: Targets
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(text: title)
            row("Calories", path: \.calories, unit: "kcal"); row("Protein", path: \.protein, unit: "g"); row("Carbs", path: \.carbs, unit: "g"); row("Fat", path: \.fat, unit: "g")
        }.padding(22).plateCard()
    }
    private func row(_ title: String, path: WritableKeyPath<Nutrients, Double>, unit: String) -> some View {
        HStack { Text(title); Spacer(); TextField(title, value: Binding(get: { targets.nutrients[keyPath: path] }, set: { targets.nutrients[keyPath: path] = $0 }), format: .number.precision(.fractionLength(0...1))).multilineTextAlignment(.trailing).frame(width: 110).textFieldStyle(.roundedBorder); Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 32) }
    }
}
#Preview { SettingsView().environment(PlateModel()) }

struct AIAccountsCard: View {
    @State private var accounts = AIRouter.accounts
    @State private var keys: [UUID: String] = [:]
    @State private var status: [UUID: String] = [:]
    @State private var testing: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(text: "Your AI")
            Text("Scan and describe food with your own AI").font(.headline)
            Text("Add accounts in the order you want Plate to try them. Your API keys are stored in Keychain. If a service fails, Plate tries the next enabled account, then the configured fallback.").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                row(index, account).transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            Menu {
                ForEach(AIProvider.allCases) { provider in
                    Button(provider.title, systemImage: provider.symbol) {
                        let account = AIAccount(provider: provider)
                        accounts.append(account)
                        AIRouter.accounts = accounts
                    }
                }
            } label: { Label("Add an AI account", systemImage: "plus.circle.fill").fontWeight(.semibold) }
        }.padding(22).plateCard()
            .onAppear { for account in accounts { keys[account.id] = AIKeychain.key(for: account.id) ?? "" } }
            .animation(reduced ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: accounts)
    }
    private func row(_ index: Int, _ account: AIAccount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: account.provider.symbol).foregroundStyle(Color.plateAccent)
                Text(account.provider.title).font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Use", isOn: binding(account.id, \.enabled)).labelsHidden().tint(Color.plateAccent)
            }
            TextField("Model", text: binding(account.id, \.model))
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()
            SecureField("Paste API key", text: Binding(get: { keys[account.id] ?? "" }, set: { keys[account.id] = $0 }))
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { accountActions(account) }
                VStack(alignment: .leading, spacing: 12) { accountActions(account) }
            }
            HStack {
                Button("Move up", systemImage: "arrow.up") { move(index, by: -1) }.disabled(index == 0)
                Button("Move down", systemImage: "arrow.down") { move(index, by: 1) }.disabled(index == accounts.count - 1)
                Spacer()
                Button("Remove", systemImage: "trash", role: .destructive) { remove(account) }
            }.labelStyle(.iconOnly).font(.caption).buttonStyle(.bordered)
            if let message = status[account.id] {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 18))
    }
    @ViewBuilder private func accountActions(_ account: AIAccount) -> some View {
        Button("Save key", systemImage: "key") { _ = saveKey(account) }
        Button(testing == account.id ? "Testing…" : "Test", systemImage: "checkmark.seal") { test(account) }
            .disabled(testing != nil || (keys[account.id] ?? "").isEmpty)
        Link("Get a key", destination: account.provider.keyPage)
    }
    private func binding<T>(_ id: UUID, _ path: WritableKeyPath<AIAccount, T>) -> Binding<T> {
        Binding(get: { (accounts.first { $0.id == id } ?? AIAccount(provider: .openAI))[keyPath: path] }, set: { value in
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index][keyPath: path] = value
            AIRouter.accounts = accounts
        })
    }
    private func move(_ index: Int, by offset: Int) {
        accounts.swapAt(index, index + offset)
        AIRouter.accounts = accounts
    }
    private func saveKey(_ account: AIAccount) -> Bool {
        do {
            try AIKeychain.setKey(keys[account.id] ?? "", for: account.id)
            status[account.id] = "Key saved securely."
            return true
        } catch {
            status[account.id] = error.localizedDescription
            return false
        }
    }
    private func remove(_ account: AIAccount) {
        do {
            try AIKeychain.setKey("", for: account.id)
            accounts.removeAll { $0.id == account.id }
            keys.removeValue(forKey: account.id)
            status.removeValue(forKey: account.id)
            AIRouter.accounts = accounts
        } catch { status[account.id] = error.localizedDescription }
    }
    private func test(_ account: AIAccount) {
        guard saveKey(account) else { return }
        let key = keys[account.id] ?? ""
        testing = account.id
        Task {
            defer { testing = nil }
            do {
                _ = try await AIRouter.request(account: account, key: key, prompt: "Estimate one medium banana.", image: nil)
                status[account.id] = "Connected. Nutrition estimates are ready."
            } catch { status[account.id] = error.localizedDescription }
        }
    }
}
