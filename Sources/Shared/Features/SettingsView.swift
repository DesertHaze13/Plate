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
                    HStack { Image(systemName: "circle.inset.filled").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Color.plateMint); Spacer(); SectionEyebrow(text: "Plate / Welcome") }
                    PlatePageTitle(eyebrow: "A FRESH START", title: "Good energy starts here.", subtitle: "A little context. A plan that feels like you.")
                    Text("A little context helps us set your starting targets. You can change every number later.").foregroundStyle(.secondary)
                    if model.sync.configured, model.sync.userID == nil {
                        Button { Task { await model.sync.signInWithGoogle() } } label: { Label("Continue with Google", systemImage: "person.crop.circle").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.bordered).disabled(model.sync.signingIn)
                        if let error = model.sync.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    }
                    ProfileFields(profile: $profile, metric: $metric)
                    let targets = NutritionCalculator.targets(for: profile).nutrients
                    HStack { VStack(alignment: .leading, spacing: 8) { SectionEyebrow(text: "Your starting point"); Text("\(Int(targets.calories)) kcal / day").font(.title2.bold()); Text("\(Int(targets.protein)) g protein · \(Int(targets.carbs)) g carbs · \(Int(targets.fat)) g fat").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(22).plateCard()
                    Text("These are starting estimates, not measurements of your metabolism. Adjust them as your weight and training trend develops.").font(.caption).foregroundStyle(.secondary)
                    Button {
                        model.store.account.settings.metric = metric
                        model.finishOnboarding(profile: profile, targets: NutritionCalculator.targets(for: profile))
                    } label: { Text("Make room for progress").fontWeight(.semibold).frame(maxWidth: .infinity).padding(10) }.buttonStyle(.borderedProminent).tint(Color.plateMint).disabled(!valid)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Goal", selection: $profile.goal) { Text("Lean bulk").tag(Goal.leanBulk); Text("Recomp").tag(Goal.recomp); Text("Cut").tag(Goal.cut) }.pickerStyle(.segmented)
            Picker("Units", selection: $metric) { Text("Metric").tag(true); Text("Imperial").tag(false) }.pickerStyle(.segmented)
            HStack { Text("Age"); Spacer(); TextField("Years", value: $profile.age, format: .number).multilineTextAlignment(.trailing).frame(width: 100); Text("years").font(.caption).foregroundStyle(.secondary) }
            Picker("Sex for BMR calculation", selection: $profile.male) { Text("Male").tag(true); Text("Female").tag(false) }
            HStack { Text("Height"); Spacer(); TextField("Height", value: Binding(get: { metric ? profile.heightCM : profile.heightCM/2.54 }, set: { profile.heightCM = metric ? $0 : $0*2.54 }), format: .number.precision(.fractionLength(0...1))).multilineTextAlignment(.trailing).frame(width: 100); Text(metric ? "cm" : "in").font(.caption).foregroundStyle(.secondary) }
            HStack { Text("Weight"); Spacer(); TextField("Weight", value: Binding(get: { metric ? profile.weightKG : profile.weightKG*2.2046226218 }, set: { profile.weightKG = metric ? $0 : $0/2.2046226218 }), format: .number.precision(.fractionLength(0...1))).multilineTextAlignment(.trailing).frame(width: 100); Text(metric ? "kg" : "lb").font(.caption).foregroundStyle(.secondary) }
            Picker("Daily activity", selection: $profile.activityMultiplier) { Text("Mostly seated").tag(1.2); Text("Lightly active").tag(1.375); Text("Moderately active").tag(1.55); Text("Very active").tag(1.725); Text("Physical work + training").tag(1.9) }
            Stepper("Training: \(profile.trainingDays) days / week", value: $profile.trainingDays, in: 0...7)
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
    @State private var saved = false
    private var valid: Bool { targets.nutrients.isValid && targets.nutrients.calories > 0 && targets.nutrients.protein > 0 && (0.5...1).contains(targets.warningFraction) && targets.tolerance >= 0 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlatePageTitle(eyebrow: "MAKE IT YOURS", title: "Built around you.", subtitle: "Your goals, your rhythm, your Plate.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 22, alignment: .top)], alignment: .leading, spacing: 22) {
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
                    Button("Recalculate targets from profile") { targets = NutritionCalculator.targets(for: profile) }.buttonStyle(.bordered).tint(Color.plateMint)
                }.buttonStyle(.bordered)
                TargetFields(title: "Daily targets", targets: $targets)
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Different targets on training days", isOn: $separateTraining).tint(Color.plateMint)
                    if separateTraining { TargetFields(title: "Training day", targets: $trainingTargets) }
                    HStack { Text("Almost-there threshold"); Spacer(); TextField("Fraction", value: $targets.warningFraction, format: .percent).multilineTextAlignment(.trailing).frame(width: 90) }
                    HStack { Text("On-target tolerance"); Spacer(); TextField("kcal", value: $targets.tolerance, format: .number).multilineTextAlignment(.trailing).frame(width: 90); Text("kcal").foregroundStyle(.secondary) }
                }.padding(22).plateCard()
                VStack(alignment: .leading, spacing: 16) {
                    SectionEyebrow(text: "Recognition")
                    Toggle("Allow cloud fallback", isOn: $cloudAllowed).tint(Color.plateMint)
                    Text("When on-device analysis is unavailable or uncertain, send the compressed food photo to your Firebase Gemini service. Label OCR starts on your device.").font(.caption).foregroundStyle(.secondary)
                    TextField("Gemini model", text: $geminiModel).textFieldStyle(.roundedBorder)
                }.padding(22).plateCard()
                VStack(alignment: .leading, spacing: 16) {
                    SectionEyebrow(text: "Evening check-in")
                    Toggle("Daily summary notification", isOn: $settings.summaryEnabled).tint(Color.plateMint).onChange(of: settings.summaryEnabled) { _, enabled in if enabled { Task { do { if !(try await SummaryNotifications.request()) { settings.summaryEnabled = false; model.notice = "Notifications are off. You can enable them in system settings." } } catch { model.notice = error.localizedDescription } } } }
                    Stepper("Summary at \(settings.summaryHour):00", value: $settings.summaryHour, in: 0...23)
                    Text("Plate updates today's scheduled summary when you open the app or log a meal.").font(.caption).foregroundStyle(.secondary)
                }.padding(22).plateCard()
                #if os(iOS)
                VStack(alignment: .leading, spacing: 16) {
                    SectionEyebrow(text: "Apple Health")
                    Toggle("Write food nutrition to Health", isOn: $healthEnabled).tint(Color.plateMint).onChange(of: healthEnabled) { _, enabled in
                        if enabled { Task { do { try await model.health.authorize(); UserDefaults.standard.set(true, forKey: "healthEnabled") } catch { healthEnabled = false; model.notice = error.localizedDescription } } }
                        else { UserDefaults.standard.set(false, forKey: "healthEnabled") }
                    }
                    Button("Import body-weight entries") { Task { do { try await model.health.authorize(); let weights = try await model.health.weights(); for entry in weights where !model.store.account.weights.contains(where: { $0.id == entry.id }) { model.store.account.weights.append(entry) }; model.sync.saveAccount(); model.notice = "Imported \(weights.count) Health weight entries." } catch { model.notice = error.localizedDescription } } }
                    Text("Health data is accessed only with your permission. Active energy does not automatically increase your food target.").font(.caption).foregroundStyle(.secondary)
                }.padding(22).plateCard()
                #endif
                }
                Button {
                    model.store.account.profile = profile; model.store.account.targets = targets
                    settings.trainingDayTargets = separateTraining ? trainingTargets : nil; model.store.account.settings = settings
                    model.sync.saveAccount(); saved = true; Task { await SummaryNotifications.schedule(store: model.store) }
                } label: { Text(saved ? "Saved" : "Save changes").fontWeight(.semibold).frame(maxWidth: .infinity).padding(10) }.buttonStyle(.borderedProminent).tint(Color.plateMint).disabled(!valid)
                Text("Plate 1.0 · Native on iPhone, iPad and Mac").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.navigationTitle("Settings").background(PlateBackground(status: .calm))
        .onAppear { profile = model.store.account.profile; targets = model.store.account.targets; settings = model.store.account.settings; separateTraining = settings.trainingDayTargets != nil; trainingTargets = settings.trainingDayTargets ?? targets }
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
