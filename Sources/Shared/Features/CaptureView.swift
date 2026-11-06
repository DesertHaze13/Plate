import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PlateCore
#if os(iOS)
import UIKit
#endif

struct CaptureView: View {
    @Environment(PlateModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cloudRecognitionAllowed") private var cloudAllowed = true
    @Namespace private var reviewGlass
    @State private var picker: PhotosPickerItem?
    @State private var importing = false
    @State private var camera = false
    @State private var photo: EncodedPhoto?
    @State private var analysis: MealAnalysis?
    @State private var items: [FoodItem] = []
    @State private var excluded: Set<String> = []
    @State private var analyzing = false
    @State private var saving = false
    @State private var error: String?
    @State private var saveFood = false
    @State private var editingItem: String?
    @State private var task: Task<Void, Never>?
    @State private var servings = 1.0
    @State private var grams = 100.0
    @State private var mealDate = Date.now
    @State private var mealType = MealType.guess(at: .now)
    private var selected: [FoodItem] { items.filter { !excluded.contains($0.id) } }
    private var totals: Nutrients { selected.reduce(.zero) { $0 + $1.total } }
    private var reviewTargets: Targets {
        let training = (model.store.account.settings.trainingDayKeys ?? []).contains(DayKey.make(mealDate))
        return training ? model.store.account.settings.trainingDayTargets ?? model.store.targets : model.store.targets
    }
    private var projectedTotals: Nutrients { HistoryMath.totals(model.store.meals, on: mealDate) + totals }
    private var canSave: Bool { !selected.isEmpty && selected.allSatisfy { ($0.needsReviewFields ?? []).isEmpty } && Meal(items: selected).isValid }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let photo { imageReview(photo.full) }
                    else { inputOptions }
                    if analyzing {
                        HStack { ProgressView(); VStack(alignment: .leading) { Text("Reading your plate…").font(.headline); Text("Looking for food, labels and serving sizes.").font(.caption).foregroundStyle(.secondary) } }.padding()
                    }
                    if let analysis {
                        Label(analysis.kind == .label ? "Read from label" : analysis.kind == .mixed ? "Food + label" : "Review your meal", systemImage: analysis.kind == .label ? "text.viewfinder" : "sparkles").font(.headline)
                        Text(analysis.explanation).font(.subheadline).foregroundStyle(.secondary)
                        if let code = analysis.barcode {
                            Label(code, systemImage: "barcode").font(.caption.monospaced())
                            if let saved = model.store.account.foods.first(where: { $0.barcode == code }) {
                                Button("Use saved \(saved.item.name)") { items = [saved.item] }
                            } else if items.isEmpty { Text("This barcode is new. Add its nutrition below or scan the label to save it in My Foods.").font(.callout) }
                        }
                        if let label = analysis.label { servingPicker(label) }
                    }
                    if !items.isEmpty {
                        HStack { SectionEyebrow(text: "On your plate"); Spacer(); Text("\(Int(totals.calories)) kcal · \(Int(totals.protein)) g protein").font(.caption.monospacedDigit()) }
                        ForEach(items) { item in itemRow(item) }
                    }
                    if !analyzing {
                        Button { var item = FoodItem(name: "New food", category: .protein, servingDescription: "1 serving", nutrients: .zero); item.needsReviewFields = ["calories", "protein", "carbs", "fat"]; items.append(item); editingItem = item.id } label: { Label("Add an item manually", systemImage: "plus.circle") }.buttonStyle(.bordered)
                    }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            DatePicker("When", selection: $mealDate, in: ...Date.now)
                            Picker("Meal", selection: $mealType) { ForEach(MealType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            Toggle("Save foods to My Foods", isOn: $saveFood)
                        }.padding(20).plateCard()
                        if canSave {
                            TargetWarningsCard(eaten: projectedTotals, targets: reviewTargets, projected: true, dayLabel: Calendar.current.isDateInToday(mealDate) ? "Today" : mealDate.formatted(.dateTime.month(.abbreviated).day()))
                        }
                    }
                    if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout).textSelection(.enabled) }
                }.padding(24).frame(maxWidth: 720)
            }.frame(maxWidth: .infinity).background(PlateBackground(status: .calm))
            .navigationTitle(photo == nil ? "Your next plate" : "Make it yours")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Log meal") { save() }.fontWeight(.semibold).disabled(!canSave || analyzing || saving)
                }
            }
            .sheet(isPresented: $camera) {
                #if os(iOS)
                CameraPicker { data in if let data { receive(data) } }
                #endif
            }
            .sheet(item: Binding(get: { editingItem.map(ItemID.init) }, set: { editingItem = $0?.id })) { id in
                if let index = items.firstIndex(where: { $0.id == id.id }) { FoodItemEditor(item: $items[index]) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; receive(try Data(contentsOf: url)) }
                catch { self.error = error.localizedDescription }
            }
            .onChange(of: picker) { _, picker in
                Task { do { if let data = try await picker?.loadTransferable(type: Data.self) { receive(data) } } catch { self.error = error.localizedDescription } }
            }
            .dropDestination(for: Data.self) { values, _ in guard let data = values.first else { return false }; receive(data); return true }
            .task {
                if let data = model.importedPhoto { model.importedPhoto = nil; receive(data) }
                #if os(iOS)
                if photo == nil, UserDefaults(suiteName: SharedSnapshot.appGroup)?.bool(forKey: "directCamera") == true {
                    UserDefaults(suiteName: SharedSnapshot.appGroup)?.set(false, forKey: "directCamera"); camera = UIImagePickerController.isSourceTypeAvailable(.camera)
                }
                #endif
            }
            .onDisappear { task?.cancel() }
            .sensoryFeedback(.success, trigger: saving)
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 760, minHeight: 600)
        #endif
    }
    private var inputOptions: some View {
        VStack(spacing: 24) {
            PlateSculpture().padding(.top, 8)
            Text("Something delicious awaits.").font(.system(.title, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
            Text("Snap your food, a nutrition label, or a menu. You’ll check every item before it’s logged.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { camera = true } label: { Label("Take a photo", systemImage: "camera.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).tint(Color.plateMint)
            }
            #endif
            PhotosPicker(selection: $picker, matching: .images) { Label("Choose from Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.bordered)
            Button { importing = true } label: { Label("Import image", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.bordered)
            #if os(macOS)
            Text("You can also drop an image here.").font(.caption).foregroundStyle(.secondary)
            #endif
        }.padding(24).frame(maxWidth: .infinity).plateCard()
    }
    private func imageReview(_ data: Data) -> some View {
        ZStack {
            if let image = platformImage(data) {
                image.resizable().scaledToFit()
                    .overlay {
                        GeometryReader { geometry in
                            if !analyzing, analysis?.kind != .label {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    if let b = item.bounds {
                                        RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 2)
                                            .background(Color.plateMint.opacity(0.08))
                                            .overlay(alignment: .topLeading) { Text(item.name).font(.caption2.bold()).padding(5).background(.ultraThinMaterial, in: Capsule()).offset(y: -22) }
                                            .frame(width: geometry.size.width*b.width, height: geometry.size.height*b.height)
                                            .offset(x: geometry.size.width*b.x, y: geometry.size.height*b.y)
                                            .transition(.scale.combined(with: .opacity)).animation(reduceMotion ? nil : .spring.delay(Double(index)*0.08), value: items.count)
                                    }
                                }
                            }
                        }
                    }
            }
            if analyzing { ScanSweep(label: analysis?.kind == .label) }
        }.overlay(alignment: .bottomLeading) {
            if !analyzing, !items.isEmpty, items.allSatisfy({ $0.bounds == nil }) {
                GlassEffectContainer(spacing: 12) { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(items) { item in Button(item.name) { editingItem = item.id }.font(.caption.bold()).padding(9).glassEffect(.regular, in: .capsule).glassEffectID(item.id, in: reviewGlass) } }.padding(12) } }
            }
        }.frame(maxHeight: 380).clipShape(RoundedRectangle(cornerRadius: 24))
    }
    private func itemRow(_ item: FoodItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { if excluded.contains(item.id) { excluded.remove(item.id) } else { excluded.insert(item.id) } } label: { Image(systemName: excluded.contains(item.id) ? "circle" : "checkmark.circle.fill").font(.title3).foregroundStyle(Color.plateMint) }.buttonStyle(.plain).accessibilityLabel("Include \(item.name)")
            Button { editingItem = item.id } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.name).font(.headline)
                    Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) × \(item.servingDescription)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if item.source == .label { Label("Read from label", systemImage: "text.viewfinder").foregroundStyle(Color.plateMint) }
                        else if let confidence = item.confidence { Text("\(Int(confidence*100))% confidence").foregroundStyle(.secondary) }
                        if (item.confidence ?? 1) < 0.75 || !(item.needsReviewFields ?? []).isEmpty { Text("Check this one").foregroundStyle(.orange) }
                    }.font(.caption2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            VStack(alignment: .trailing, spacing: 8) {
                Text("\(Int(item.total.calories)) kcal").font(.subheadline.bold().monospacedDigit())
                Button("Remove", systemImage: "xmark") { items.removeAll { $0.id == item.id } }.labelStyle(.iconOnly).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).plateCard().opacity(excluded.contains(item.id) ? 0.45 : 1)
    }
    private func servingPicker(_ label: LabelDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How much are you eating?").font(.headline)
            Text(label.basis == .per100Grams ? "Label values are per 100 g / ml." : label.basis == .package ? "Label values are per package." : "Label values are per serving.").font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach([0.5, 1, 2], id: \.self) { amount in
                    Button(amount == 0.5 ? "½ serving" : "\(Int(amount)) serving\(amount == 1 ? "" : "s")") { servings = amount; scaleLabel(label.quantity(servings: amount)) }.buttonStyle(.bordered)
                }
            }
            if let whole = label.wholePackageQuantity { Button("Whole package") { scaleLabel(whole) }.buttonStyle(.bordered) }
            if label.basis == .per100Grams || label.servingGrams != nil {
                HStack { TextField("Grams / ml", value: $grams, format: .number).textFieldStyle(.roundedBorder); Button("Apply amount") { if grams > 0 { scaleLabel(label.basis == .per100Grams ? grams/100 : grams/(label.servingGrams ?? 100)) } } }
            }
            DisclosureGroup("Recognized text") { Text(label.rawText).font(.caption.monospaced()).textSelection(.enabled) }
        }.padding(18).plateCard()
    }
    private func scaleLabel(_ quantity: Double) { for index in items.indices where items[index].source == .label { items[index].quantity = quantity } }
    private func receive(_ data: Data) {
        task?.cancel(); analyzing = true; analysis = nil; items = []; excluded = []; error = nil
        task = Task {
            do {
                let encoded = try ImageCodec.prepare(data); photo = encoded
                let result = try await model.recognition.analyze(data: encoded.full, cloudAllowed: cloudAllowed)
                try Task.checkCancellation()
                withAnimation(reduceMotion ? nil : .spring) { analysis = result; items = result.items; analyzing = false; saveFood = result.items.contains { $0.source == .label } }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription; analyzing = false }
        }
    }
    private func save() {
        guard canSave else { return }; saving = true
        Task {
            var meal = Meal(timestamp: mealDate, items: selected, source: analysis?.kind == .barcode ? .barcode : selected.allSatisfy { $0.source == .label } ? .label : selected.first?.source ?? .manual); meal.type = mealType
            await model.saveMeal(meal, photo: photo, saveToLibrary: saveFood, barcode: analysis?.barcode)
            saving = false; dismiss()
        }
    }
}
private struct ItemID: Identifiable { let id: String }
struct FoodItemEditor: View {
    @Binding var item: FoodItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Food") { TextField("Name", text: $item.name); TextField("Base serving", text: $item.servingDescription); Picker("Category", selection: $item.category) { ForEach(FoodCategory.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } } }
                Section("Amount eaten") { Stepper(value: $item.quantity, in: 0.125...20, step: 0.125) { Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...3)))) servings") } }
                Section("Nutrition per base serving") {
                    field("Calories", "calories", \.calories, "kcal"); field("Protein", "protein", \.protein, "g"); field("Carbs", "carbs", \.carbs, "g"); field("Fat", "fat", \.fat, "g"); field("Fiber", "fiber", \.fiber, "g"); field("Sugar", "sugar", \.sugar, "g")
                }
                if !(item.needsReviewFields ?? []).isEmpty { Text("Highlighted values couldn’t be read. Enter them to confirm. Zero is valid when the label says zero.").foregroundStyle(.orange).font(.caption) }
            }.navigationTitle("Check your food").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 440, height: 570)
        #endif
    }
    private func field(_ title: String, _ key: String, _ path: WritableKeyPath<Nutrients, Double>, _ unit: String) -> some View {
        HStack {
            Text(title).foregroundStyle((item.needsReviewFields ?? []).contains(key) ? .orange : .primary)
            Spacer()
            TextField(unit, value: Binding(get: { item.nutrients[keyPath: path] }, set: { item.nutrients[keyPath: path] = $0; item.needsReviewFields?.removeAll { $0 == key } }), format: .number).multilineTextAlignment(.trailing).frame(maxWidth: 110)
            Text(unit).foregroundStyle(.secondary).frame(width: 32)
            if (item.needsReviewFields ?? []).contains(key) { Button("Confirm value") { item.needsReviewFields?.removeAll { $0 == key } }.font(.caption) }
        }
    }
}
struct ScanSweep: View {
    var label = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scan = false
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(LinearGradient(colors: [.clear,Color.plateMint.opacity(0.4),.white.opacity(0.8),.clear], startPoint: .top, endPoint: .bottom)).frame(height: 70).offset(y: reduceMotion ? geometry.size.height/2 : scan ? geometry.size.height : -70).animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: false), value: scan).onAppear { scan = true }
        }.allowsHitTesting(false).accessibilityLabel(label ? "Reading nutrition text" : "Analyzing food")
    }
}
#if os(iOS)
struct CameraPicker: UIViewControllerRepresentable {
    var completion: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .camera; picker.cameraCaptureMode = .photo; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { parent.completion((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.95)); parent.dismiss() }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.completion(nil); parent.dismiss() }
    }
}
#endif
#Preview { CaptureView().environment(PlateModel()) }
