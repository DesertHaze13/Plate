import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import PlateCore
#if os(iOS)
import UIKit
#endif

struct CaptureView: View {
    var startWithDescription = false
    @Environment(PlateModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cloudRecognitionAllowed") private var cloudAllowed = true
    @Namespace private var reviewGlass
    @State private var picker: PhotosPickerItem?
    @State private var importing = false
    @State private var camera = false
    @State private var photo: EncodedPhoto?
    @State private var markingPhoto = false
    @State private var excludedRegions: [FoodBounds] = []
    @State private var analysis: MealAnalysis?
    @State private var items: [FoodItem] = []
    @State private var excluded: Set<String> = []
    @State private var analyzing = false
    @State private var saving = false
    @State private var error: String?
    @State private var saveFood = false
    @State private var editingItem: String?
    @State private var describing: DescribeTarget?
    @State private var task: Task<Void, Never>?
    @State private var servings = 1.0
    @State private var grams = 100.0
    @State private var mealDate = Date.now
    @State private var mealType = MealType.guess(at: .now)
    private var selected: [FoodItem] { items.filter { !excluded.contains($0.id) } }
    private var totals: Nutrients { selected.reduce(.zero) { $0 + $1.total } }
    private var canSave: Bool { !selected.isEmpty && selected.allSatisfy { ($0.needsReviewFields ?? []).isEmpty } && Meal(items: selected).isValid }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let photo {
                        imageReview(photo.full)
                        Button { markingPhoto = true } label: { Label(excludedRegions.isEmpty ? "Mark food I won’t eat" : "Edit crossed-out areas", systemImage: "pencil.tip.crop.circle") }.buttonStyle(.bordered).disabled(analyzing || saving)
                        Text("Tap a food on the photo to cross it out. For a small part of a mixed plate, mark that area and recheck. Tap a food’s name below to adjust the amount eaten.").font(.caption).foregroundStyle(.secondary)
                    }
                    else if items.isEmpty && !startWithDescription { inputOptions }
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
                        Button { describing = DescribeTarget(item: nil) } label: {
                            Label(photo == nil && items.isEmpty ? "Describe what you ate" : "Something missing? Describe it", systemImage: "text.bubble.fill").fontWeight(.semibold).frame(maxWidth: .infinity).padding(6)
                        }.buttonStyle(.borderedProminent).tint(Color.plateAccent)
                        Button { var item = FoodItem(name: "New food", category: .protein, servingDescription: "1 serving", nutrients: .zero); item.needsReviewFields = ["calories", "protein", "carbs", "fat"]; items.append(item); editingItem = item.id } label: { Label("Add an item manually", systemImage: "plus.circle") }.buttonStyle(.bordered)
                    }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            DatePicker("When", selection: $mealDate, in: ...Date.now)
                            Picker("Meal", selection: $mealType) { ForEach(MealType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            Toggle("Save foods to My Foods", isOn: $saveFood)
                        }.padding(20).plateCard()
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
            .sheet(isPresented: $markingPhoto) {
                if let photo {
                    PhotoExclusionEditor(data: photo.full, initial: excludedRegions) { regions in
                        excludedRegions = regions
                        reanalyze(photo, excluding: regions)
                    }
                }
            }
            .sheet(isPresented: $camera) {
                #if os(iOS)
                CameraPicker { data in if let data { receive(data) } }
                #endif
            }
            .sheet(item: $describing) { target in
                DescribeFoodSheet(original: target.item, photo: photo.flatMap { try? ImageCodec.masking($0.full, regions: excludedRegions) }) { found in applyDescribed(found, replacing: target.item) }.environment(model)
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
                if startWithDescription { describing = DescribeTarget(item: nil) }
                if let data = model.importedPhoto { model.importedPhoto = nil; receive(data) }
                #if os(iOS)
                if photo == nil, !startWithDescription, UserDefaults(suiteName: SharedSnapshot.appGroup)?.bool(forKey: "directCamera") == true {
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
                Button { camera = true } label: { Label("Take a photo", systemImage: "camera.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).tint(Color.plateAccent)
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
                            ExclusionMarks(regions: excludedRegions).allowsHitTesting(false)
                            if !analyzing, analysis?.kind != .label {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    if let b = item.bounds {
                                        RoundedRectangle(cornerRadius: 12).stroke(excluded.contains(item.id) ? Color.red : .white, lineWidth: 2)
                                            .background(excluded.contains(item.id) ? Color.red.opacity(0.25) : Color.plateAccent.opacity(0.08))
                                            .overlay { if excluded.contains(item.id) { Image(systemName: "xmark").font(.title.bold()).foregroundStyle(.red) } }
                                            .overlay(alignment: .topLeading) { Text(item.name).font(.caption2.bold()).padding(5).background(.ultraThinMaterial, in: Capsule()).offset(y: -22) }
                                            .frame(width: geometry.size.width*b.width, height: geometry.size.height*b.height)
                                            .contentShape(Rectangle())
                                            .onTapGesture { toggleItem(item.id) }
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel("\(excluded.contains(item.id) ? "Include" : "Exclude") \(item.name)")
                                            .accessibilityAddTraits(.isButton)
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
                GlassEffectContainer(spacing: 12) { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(items) { item in Button(excluded.contains(item.id) ? "✕ " + item.name : item.name) { toggleItem(item.id) }.font(.caption.bold()).padding(9).glassEffect(.regular, in: .capsule).glassEffectID(item.id, in: reviewGlass) } }.padding(12) } }
            }
        }.frame(maxHeight: 380).clipShape(RoundedRectangle(cornerRadius: 24))
    }
    private func itemRow(_ item: FoodItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { toggleItem(item.id) } label: { Image(systemName: excluded.contains(item.id) ? "xmark.circle.fill" : "checkmark.circle.fill").font(.title3).foregroundStyle(Color.plateAccent) }.buttonStyle(.plain).accessibilityLabel("\(excluded.contains(item.id) ? "Include" : "Exclude") \(item.name)")
            VStack(alignment: .leading, spacing: 10) {
            Button { editingItem = item.id } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.name).font(.headline).strikethrough(excluded.contains(item.id))
                    Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) × \(item.servingDescription)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if item.source == .label { Label("Read from label", systemImage: "text.viewfinder").foregroundStyle(Color.plateAccent) }
                        else if let confidence = item.confidence { Text("\(Int(confidence*100))% confidence").foregroundStyle(.secondary) }
                        if (item.confidence ?? 1) < 0.75 || !(item.needsReviewFields ?? []).isEmpty { Text("Check this one").foregroundStyle(.orange) }
                    }.font(.caption2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
                Button { describing = DescribeTarget(item: item) } label: {
                    Label((item.confidence ?? 1) < 0.75 ? "Not right? Tell AI what it is" : "Tell AI what it really is", systemImage: "text.bubble")
                }.font(.caption.weight(.semibold)).foregroundStyle(Color.plateAccent).buttonStyle(.plain)
                    .accessibilityHint("Type what this food is and how much, and Plate re-estimates its nutrition")
            }
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
        task?.cancel(); photo = nil; excludedRegions = []; analyzing = true; analysis = nil; items = []; excluded = []; error = nil
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
    /// Puts AI results from the user's description in place of the food they corrected, or adds them.
    private func applyDescribed(_ found: [FoodItem], replacing original: FoodItem?) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)) {
            let wasExcluded = original.map { excluded.contains($0.id) } ?? false
            items = FoodReview.applying(found, replacing: original?.id, to: items)
            if let original { excluded.remove(original.id) }
            if wasExcluded { excluded.formUnion(found.map(\.id)) }
            if var revised = analysis {
                revised.items = items
                if !items.contains(where: { $0.source == .label }) {
                    revised.label = nil; revised.kind = .food
                    if original != nil { revised.barcode = nil }
                }
                revised.explanation = "Includes AI estimates from your descriptions. Review portions and nutrition before logging."
                analysis = revised
            }
            error = nil
        }
    }
    private func toggleItem(_ id: String) {
        if excluded.contains(id) { excluded.remove(id) } else { excluded.insert(id) }
    }
    private func reanalyze(_ photo: EncodedPhoto, excluding regions: [FoodBounds]) {
        task?.cancel(); analyzing = true; error = nil; analysis = nil; items = []; excluded = []
        task = Task {
            do {
                let result = try await model.recognition.analyze(data: photo.full, cloudAllowed: cloudAllowed, excluding: regions)
                try Task.checkCancellation()
                analysis = result; items = result.items; analyzing = false
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
private struct DescribeTarget: Identifiable {
    let item: FoodItem?
    var id: String { item?.id ?? "new" }
}
/// Type what a food really is, in your own words, and AI works out its nutrition.
struct DescribeFoodSheet: View {
    let original: FoodItem?
    let photo: Data?
    let onResult: ([FoodItem]) -> Void
    @Environment(PlateModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cloudRecognitionAllowed") private var cloudAllowed = true
    @State private var text = ""
    @State private var working = false
    @State private var problem: String?
    @State private var proposed: [FoodItem] = []
    @State private var editingID: String?
    @State private var includePhoto = false
    @State private var attachedPhoto: Data?
    @State private var photoPicker: PhotosPickerItem?
    @State private var importingPhoto = false
    @State private var loadingPhoto = false
    @State private var attachmentTask: Task<Void, Never>?
    @State private var requestTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var referencePhoto: Data? { includePhoto ? (attachedPhoto ?? photo) : nil }
    private var canEstimate: Bool { !working && !loadingPhoto && (!trimmed.isEmpty || referencePhoto != nil) }
    private var canApply: Bool { !working && !loadingPhoto && !proposed.isEmpty && Meal(items: proposed).isValid && proposed.allSatisfy { ($0.needsReviewFields ?? []).isEmpty } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let original { Text("Correcting: \(original.name) · \(original.servingDescription)").font(.subheadline).foregroundStyle(.secondary) }
                    Text(original == nil ? "What did the scan miss?" : "Tell us what it really is.").font(.system(.title2, design: .rounded, weight: .bold))
                    TextField("e.g. grilled chicken, about 120 g, no sauce", text: $text, axis: .vertical)
                        .lineLimit(3...6).textFieldStyle(.roundedBorder).focused($focused).disabled(working)
                        .onChange(of: text) { _, value in
                            if value.count > 600 { text = String(value.prefix(600)) }
                            proposed = []
                        }
                    Text("Describe this food and the amount eaten. For missed foods, list each one; you can review them separately.").font(.caption).foregroundStyle(.secondary)
                    photoAttachment

                    Text(cloudAllowed ? "Uses your enabled AI accounts, with Apple Intelligence as a fallback." : "Cloud recognition is off. Uses on-device AI only.").font(.caption2).foregroundStyle(.secondary)
                    if let problem { Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout) }
                    Button { run() } label: {
                        HStack { if working { ProgressView() }; Label(working ? "Estimating…" : "Estimate nutrition", systemImage: "sparkles") }.frame(maxWidth: .infinity).padding(8)
                    }.buttonStyle(.borderedProminent).tint(Color.plateAccent).disabled(!canEstimate)
                    if !proposed.isEmpty {
                        Divider()
                        Text("Review the AI estimate").font(.headline)
                        Text("Nothing has changed yet. Check portions and nutrition, then apply. Other foods stay as they are.").font(.caption).foregroundStyle(.secondary)
                        ForEach(proposed) { food in
                            Button { editingID = food.id } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack { Text(food.name).font(.headline); Spacer(); Image(systemName: "pencil") }
                                    Text(food.servingDescription).font(.subheadline)
                                    Text("\(Int(food.total.calories)) kcal · \(Int(food.total.protein)) g protein · \(Int(food.total.carbs)) g carbs · \(Int(food.total.fat)) g fat").font(.caption)
                                    if !(food.needsReviewFields ?? []).isEmpty { Text("Missing values: tap to enter and confirm them.").font(.caption).foregroundStyle(.orange) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).plateCard()
                            }.buttonStyle(.plain)
                        }
                        Button(original == nil ? "Add reviewed foods" : "Apply correction") { onResult(proposed); dismiss() }
                            .buttonStyle(.borderedProminent).tint(Color.plateAccent).disabled(!canApply)
                    }
                }.padding(24)
            }.navigationTitle(original == nil ? "Add missing food" : "Correct one food")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { requestTask?.cancel(); dismiss() } } }
                .sheet(item: Binding(get: { editingID.map(ItemID.init) }, set: { editingID = $0?.id })) { id in
                    if let index = proposed.firstIndex(where: { $0.id == id.id }) { FoodItemEditor(item: $proposed[index]) }
                }
                .fileImporter(isPresented: $importingPhoto, allowedContentTypes: [.image]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        receiveAttachment(try Data(contentsOf: url))
                    } catch let error as CocoaError where error.code == .userCancelled { }
                    catch { problem = error.localizedDescription }
                }
                .onChange(of: photoPicker) { _, selected in
                    attachmentTask?.cancel()
                    proposed = []
                    loadingPhoto = selected != nil
                    attachmentTask = Task {
                        defer { if photoPicker == selected { loadingPhoto = false } }
                        do {
                            if let bytes = try await selected?.loadTransferable(type: Data.self) {
                                try Task.checkCancellation()
                                receiveAttachment(bytes)
                            }
                        } catch is CancellationError { }
                        catch { problem = error.localizedDescription }
                    }
                }
                .onAppear { focused = true }
                .onDisappear { requestTask?.cancel(); attachmentTask?.cancel() }
        }
        .presentationDetents([.large])
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
    private var photoAttachment: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PhotosPicker(selection: $photoPicker, matching: .images) { Label("Attach photo", systemImage: "photo.badge.plus") }.disabled(working)
                Spacer()
                Button("From Files", systemImage: "folder") { importingPhoto = true }.disabled(working)
            }.buttonStyle(.bordered)
            if loadingPhoto { ProgressView("Preparing photo…").font(.caption) }
            if attachedPhoto != nil || photo != nil {
                Toggle("Use reference photo for this estimate", isOn: $includePhoto).disabled(working)
                    .onChange(of: includePhoto) { _, _ in proposed = [] }
                if includePhoto, let bytes = attachedPhoto ?? photo, let image = platformImage(bytes) {
                    image.resizable().scaledToFit().frame(maxHeight: 170).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Reference food photo")
                }
                if attachedPhoto != nil {
                    Button("Remove attached photo", systemImage: "xmark.circle") {
                        attachedPhoto = nil; includePhoto = false; photoPicker = nil; proposed = []
                    }.font(.caption).disabled(working)
                }
            }
            Text("Attach a clear food photo, then describe the food or portion if needed. Photos are reference only and do not replace the meal’s saved photo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func receiveAttachment(_ bytes: Data) {
        do {
            attachedPhoto = try ImageCodec.prepare(bytes).full
            includePhoto = true; proposed = []; problem = nil; focused = false
        } catch { problem = "This photo could not be read. Choose a different image." }
    }
    private func run() {
        guard canEstimate else { return }
        working = true; problem = nil; proposed = []; focused = false
        let request = trimmed.isEmpty ? (original == nil ? "Identify the foods in the attached photo and estimate their portions and nutrition." : "Re-estimate this food and its portion from the attached photo. Do not add unrelated foods.") : trimmed
        let image = referencePhoto
        let matchesOriginal = attachedPhoto == nil
        requestTask = Task {
            do {
                let found = try await model.recognition.describe(request, photo: image, correcting: original, cloudAllowed: cloudAllowed, photoMatchesOriginal: matchesOriginal)
                try Task.checkCancellation()
                if found.isEmpty { problem = "No food estimate was returned. Try a specific food name and portion, or enter it manually." }
                else { proposed = found }
                working = false
            } catch is CancellationError { working = false }
            catch { problem = error.localizedDescription; working = false }
        }
    }
}
struct FoodItemEditor: View {
    @Binding var item: FoodItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Food") { TextField("Name", text: $item.name); TextField("Base serving", text: $item.servingDescription); Picker("Category", selection: $item.category) { ForEach(FoodCategory.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } } }
                Section("Amount eaten") {
                    Stepper(value: $item.quantity, in: 0.01...20, step: 0.01) { Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) servings") }
                    HStack { ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { amount in
                        Button(amount.formatted(.percent) + " serving") { item.quantity = amount }.buttonStyle(.bordered)
                    } }
                    Text("Nutrition scales with the amount you eat. Crossing out a whole item removes it from the meal.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Nutrition per base serving") {
                    field("Calories", "calories", \.calories, "kcal"); field("Protein", "protein", \.protein, "g"); field("Carbs", "carbs", \.carbs, "g"); field("Fat", "fat", \.fat, "g"); field("Fiber", "fiber", \.fiber, "g"); field("Sugar", "sugar", \.sugar, "g"); field("Caffeine", "caffeine", \.caffeine, "mg")
                    if item.nutrients.caffeine == 0, let estimate = CaffeineEstimate.perServing(name: item.name) {
                        Button("Use estimated caffeine: \(Int(estimate)) mg per serving") { item.nutrients.caffeine = estimate }.font(.caption)
                        Text("Optional estimate. Confirm the serving or enter the label amount; unconfirmed caffeine is not written to Health.").font(.caption).foregroundStyle(.secondary)
                    }
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
            Rectangle().fill(LinearGradient(colors: [.clear,Color.plateAccent.opacity(0.4),.white.opacity(0.8),.clear], startPoint: .top, endPoint: .bottom)).frame(height: 70).offset(y: reduceMotion ? geometry.size.height/2 : scan ? geometry.size.height : -70).animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: false), value: scan).onAppear { scan = true }
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

private struct ExclusionMarks: View {
    var regions: [FoodBounds]
    var body: some View {
        Canvas { context, size in
            for region in regions {
                let rect = CGRect(x: region.x * size.width, y: region.y * size.height, width: region.width * size.width, height: region.height * size.height)
                context.fill(Path(rect), with: .color(.black.opacity(0.6)))
                context.stroke(Path(rect), with: .color(.red), lineWidth: 2)
                var cross = Path(); cross.move(to: rect.origin); cross.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                cross.move(to: CGPoint(x: rect.maxX, y: rect.minY)); cross.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                context.stroke(cross, with: .color(.red), lineWidth: 2)
            }
        }
    }
}
private struct PhotoExclusionEditor: View {
    let data: Data
    let apply: ([FoodBounds]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var regions: [FoodBounds]
    @State private var draft: FoodBounds?
    @State private var zoom = 1.0
    @State private var marking = true
    init(data: Data, initial: [FoodBounds], apply: @escaping ([FoodBounds]) -> Void) {
        self.data = data; self.apply = apply; _regions = State(initialValue: initial)
    }
    private var ratio: CGFloat {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return 1 }
        return CGFloat(image.width) / CGFloat(image.height)
    }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Drag a box over anything you won’t eat, even a small part of one plate. Zoom in for precision. Switch off marking to move around the zoomed photo.").font(.callout)
                HStack { Toggle("Mark areas", isOn: $marking); Spacer(); Text("Zoom"); Slider(value: $zoom, in: 1...4).frame(maxWidth: 180) }
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        if let image = platformImage(data) {
                            image.resizable().frame(width: geometry.size.width * zoom, height: geometry.size.width * zoom / ratio)
                                .overlay { ExclusionMarks(regions: regions + (draft.map { [$0] } ?? [])).allowsHitTesting(false) }
                                .overlay {
                                    if marking {
                                        Color.clear.contentShape(Rectangle()).highPriorityGesture(DragGesture(minimumDistance: 2)
                                            .onChanged { value in draft = bounds(value, size: CGSize(width: geometry.size.width * zoom, height: geometry.size.width * zoom / ratio)) }
                                            .onEnded { value in
                                                if let region = bounds(value, size: CGSize(width: geometry.size.width * zoom, height: geometry.size.width * zoom / ratio)) { regions.append(region) }
                                                draft = nil
                                            })
                                    }
                                }
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 16))
                HStack {
                    Text("\(regions.count) areas excluded").font(.caption)
                    Spacer()
                    Button("Undo") { if !regions.isEmpty { regions.removeLast() } }.disabled(regions.isEmpty)
                    Button("Clear all") { regions = [] }.disabled(regions.isEmpty)
                }
                Text("Rechecking replaces the food estimates. Review the remaining portions before logging. You can also exclude items from the food list without drawing.").font(.caption).foregroundStyle(.secondary)
            }.padding().navigationTitle("Leave these out")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Recheck food") { apply(regions); dismiss() } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 580, minHeight: 650)
        #endif
    }
    private func bounds(_ value: DragGesture.Value, size: CGSize) -> FoodBounds? {
        guard size.width > 0, size.height > 0 else { return nil }
        let x1 = min(1, max(0, value.startLocation.x / size.width)), x2 = min(1, max(0, value.location.x / size.width))
        let y1 = min(1, max(0, value.startLocation.y / size.height)), y2 = min(1, max(0, value.location.y / size.height))
        guard abs(x2 - x1) * size.width >= 2, abs(y2 - y1) * size.height >= 2 else { return nil }
        return FoodBounds(x: min(x1, x2), y: min(y1, y2), width: abs(x2-x1), height: abs(y2-y1))
    }
}
