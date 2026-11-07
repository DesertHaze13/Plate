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
    @State private var foodDescription = ""
    @State private var requestID = UUID()
    @State private var started = Date.now
    @State private var analyzedDescription: String?
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
    @State private var aiEditingItem: String?
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
    private var canSave: Bool { (analysis == nil || analyzedDescription == foodDescription) && !selected.isEmpty && selected.allSatisfy { ($0.needsReviewFields ?? []).isEmpty } && Meal(items: selected).isValid }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let photo { imageReview(photo.full) }
                    else { inputOptions }
                    descriptionComposer
                    if analyzing {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            HStack { ProgressView(); Text("Membaca foto + ceritamu… \(max(0,Int(context.date.timeIntervalSince(started)))) dtk").font(.subheadline) }
                        }
                        Button("Batalkan analisis") { requestID = UUID(); task?.cancel(); analyzing = false }
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
                            TargetWarningsCard(eaten: projectedTotals, targets: reviewTargets, projected: true, dayLabel: Calendar.current.isDateInToday(mealDate) ? "Hari ini" : mealDate.formatted(.dateTime.month(.abbreviated).day()))
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
                if let index = items.firstIndex(where: { $0.id == id.id }) { FoodItemEditor(item: $items[index], draftPhoto: photo?.full) }
            }
            .sheet(item: Binding(get: { aiEditingItem.map(ItemID.init) }, set: { aiEditingItem = $0?.id })) { id in
                if let index = items.firstIndex(where: { $0.id == id.id }) { FoodAIRevisionView(item: $items[index], draftPhoto: photo?.full).environment(model) }
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
                        if item.aiModel == RecognitionModel.fallback { Text("Flash Lite · cadangan").foregroundStyle(.orange) }
                        if item.source == .label { Label("Read from label", systemImage: "text.viewfinder").foregroundStyle(Color.plateMint) }
                        else if let confidence = item.confidence { Text("\(Int(confidence*100))% confidence").foregroundStyle(.secondary) }
                        if (item.confidence ?? 1) < 0.75 || !(item.needsReviewFields ?? []).isEmpty { Text("Perlu diperiksa").foregroundStyle(.orange) }
                    }.font(.caption2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            VStack(alignment: .trailing, spacing: 8) {
                Text("\(Int(item.total.calories)) kcal").font(.subheadline.bold().monospacedDigit())
                Button("Edit dengan AI", systemImage: "sparkles") { aiEditingItem = item.id }.font(.caption).buttonStyle(.bordered)
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
    private func scaleLabel(_ quantity: Double) { for index in items.indices where items[index].source == .label { items[index].quantity = quantity; items[index].needsReviewFields?.removeAll { $0 == "quantity" } } }
    private func receive(_ data: Data) {
        requestID = UUID(); task?.cancel(); analyzing = false; analysis = nil; items = []; excluded = []; error = nil
        do { photo = try ImageCodec.prepare(data) } catch { self.error = error.localizedDescription }
    }
    private var descriptionComposer: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Foto + ceritamu", systemImage: "sparkles").font(.system(.headline, design: .rounded, weight: .bold))
            TextField("Contoh: nasi kuning, ayam goreng, sambal; nasinya setengah porsi", text: $foodDescription, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder).disabled(analyzing)
            Text(photo == nil ? "Boleh pakai deskripsi saja, atau tambahkan foto supaya lebih jelas." : "Tambahkan nama makanan, porsi, cara masak atau bahan yang tidak terlihat.").font(.caption).foregroundStyle(.secondary)
            if analysis != nil && analyzedDescription != foodDescription { Text("Deskripsi berubah. Analisis ulang sebelum menyimpan.").font(.caption.bold()).foregroundStyle(.orange) }
            if !analyzing { Button(items.isEmpty ? "Analisis makanan" : "Analisis ulang foto + deskripsi", systemImage: "sparkles") { analyzeDraft() }.buttonStyle(.borderedProminent).disabled(photo == nil && foodDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            if photo != nil && !analyzing { Button("Ganti foto", systemImage: "photo") { photo = nil; analysis = nil; items = []; excluded = [] } }
            Text(cloudAllowed ? "Foto/deskripsi baru dikirim ke AI cloud saat kamu menekan Analisis. Periksa hasil sebelum menyimpan." : "Cloud dimatikan. AI di perangkat digunakan bila tersedia.").font(.caption2).foregroundStyle(.secondary)
        }.padding(20).plateCard()
    }
    private func analyzeDraft() {
        task?.cancel(); analyzing = true; error = nil; started = .now
        let id = UUID(); requestID = id
        let image = photo?.full; let description = foodDescription
        task = Task {
            do {
                let result = try await model.recognition.analyze(data: image, description: description, cloudAllowed: cloudAllowed)
                try Task.checkCancellation(); guard requestID == id else { return }
                withAnimation(reduceMotion ? nil : .spring) { analysis = result; analyzedDescription = description; items = result.items; excluded = []; analyzing = false; saveFood = result.items.contains { $0.source == .label } }
            } catch is CancellationError { }
            catch { guard requestID == id else { return }; self.error = error.localizedDescription; analyzing = false }
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
    var existingPhotoPath: String?
    var draftPhoto: Data?
    @State private var showAI = false
    @Environment(PlateModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { Button("Edit dengan AI", systemImage: "sparkles") { showAI = true }; Text("Koreksi nama, porsi atau cara masak dengan foto dan deskripsi.").font(.caption).foregroundStyle(.secondary) }
                Section("Food") { TextField("Name", text: $item.name).onChange(of: item.name) { _, _ in item.needsReviewFields?.removeAll { $0 == "name" } };
                    if item.needsReviewFields?.contains("name") == true { Text("Identitas makanan belum pasti. Koreksi nama atau konfirmasikan sebelum menyimpan.").font(.caption).foregroundStyle(.orange); Button("Konfirmasi nama makanan") { item.needsReviewFields?.removeAll { $0 == "name" } } }; TextField("Base serving", text: $item.servingDescription); Picker("Category", selection: $item.category) { ForEach(FoodCategory.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } } }
                Section("Amount eaten") {
                    Stepper(value: $item.quantity, in: 0.125...20, step: 0.125) { Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...3)))) servings") }.onChange(of: item.quantity) { _, _ in item.needsReviewFields?.removeAll { $0 == "quantity" } }
                    if item.needsReviewFields?.contains("quantity") == true { Button("Konfirmasi jumlah porsi") { item.needsReviewFields?.removeAll { $0 == "quantity" } } }
                }
                Section("Nutrition per base serving") {
                    field("Calories", "calories", \.calories, "kcal"); field("Protein", "protein", \.protein, "g"); field("Carbs", "carbs", \.carbs, "g"); field("Fat", "fat", \.fat, "g"); field("Fiber", "fiber", \.fiber, "g"); field("Sugar", "sugar", \.sugar, "g")
                }
                if !(item.needsReviewFields ?? []).isEmpty { Text("Periksa kolom yang ditandai. Lengkapi atau konfirmasikan sebelum menyimpan; nilai nol tetap boleh bila benar.").foregroundStyle(.orange).font(.caption) }
            }.formStyle(.grouped).sheet(isPresented: $showAI) { FoodAIRevisionView(item: $item, existingPhotoPath: existingPhotoPath, draftPhoto: draftPhoto).environment(model) }.navigationTitle("Check your food").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 600, height: 650)
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

struct FoodAIRevisionView: View {
    @Binding var item: FoodItem
    var existingPhotoPath: String?
    var draftPhoto: Data?
    @Environment(PlateModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cloudRecognitionAllowed") private var cloudAllowed = true
    @State private var instruction = ""
    @State private var picker: PhotosPickerItem?
    @State private var importing = false
    @State private var camera = false
    @State private var attachedPhoto: Data?
    @State private var proposal: FoodItem?
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var started = Date.now
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Edit dengan AI", systemImage: "sparkles").font(.system(.title2, design: .rounded, weight: .black))
                    Text(item.name).font(.headline)
                    Text("Jelaskan koreksinya. AI hanya mengubah makanan ini; makanan lain dan tanggal catatan tetap sama.").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Contoh: ini kroket daging, bukan perkedel; 2 buah kecil, digoreng", text: $instruction, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder).disabled(busy)
                    if let data = attachedPhoto, let image = platformImage(data) { image.resizable().scaledToFit().frame(maxHeight: 210).clipShape(.rect(cornerRadius: 20)) }
                    HStack {
                        PhotosPicker(selection: $picker, matching: .images) { Label("Foto", systemImage: "photo") }
                        Button("File", systemImage: "square.and.arrow.down") { importing = true }
                        #if os(iOS)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Kamera", systemImage: "camera") { camera = true } }
                        #endif
                        if attachedPhoto != nil { Button("Lepas foto") { attachedPhoto = nil; proposal = nil } }
                    }.buttonStyle(.bordered).disabled(busy)
                    if attachedPhoto == nil && (draftPhoto != nil || existingPhotoPath != nil) { Text("Foto catatan akan disertakan bila tersedia. Foto baru menggantikannya untuk analisis ini.").font(.caption).foregroundStyle(.secondary) }
                    Text(cloudAllowed ? "Foto dan koreksi dikirim ke AI cloud saat kamu menekan Analisis. Nilai gizi tetap perkiraan." : "Cloud dimatikan. Analisis memakai AI di perangkat jika tersedia.").font(.caption).foregroundStyle(.secondary)
                    if busy {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            HStack { ProgressView(); Text("Memeriksa koreksi… \(max(0,Int(context.date.timeIntervalSince(started)))) dtk").font(.subheadline) }
                        }
                        Button("Batalkan analisis") { cancel() }
                    } else {
                        Button("Analisis koreksi", systemImage: "sparkles") { analyze() }.buttonStyle(.borderedProminent).disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedPhoto == nil)
                    }
                    if let proposal {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HASIL UNTUK DIPERIKSA").font(.caption.monospaced().bold())
                            if let engine = proposal.aiModel { Text(engine == RecognitionModel.fallback ? "MODEL CADANGAN · FLASH LITE" : "GEMINI FLASH PENUH").font(.caption.bold()).foregroundStyle(engine == RecognitionModel.fallback ? Color.orange : .secondary) }
                            Text(proposal.name).font(.title3.bold())
                            Text("\(proposal.quantity.formatted()) × \(proposal.servingDescription)").font(.subheadline)
                            Text("\(Int(item.total.calories)) → \(Int(proposal.total.calories)) kcal").font(.title2.bold().monospacedDigit())
                            Text("Protein \(proposal.total.protein.formatted(.number.precision(.fractionLength(0...1)))) g · Karbo \(proposal.total.carbs.formatted(.number.precision(.fractionLength(0...1)))) g · Lemak \(proposal.total.fat.formatted(.number.precision(.fractionLength(0...1)))) g").font(.subheadline)
                            if !(proposal.needsReviewFields ?? []).isEmpty { Text("Ada nilai atau identitas yang masih perlu dikonfirmasi di editor.").font(.caption).foregroundStyle(.orange) }
                            Button("Terapkan ke makanan ini") { item = proposal; dismiss() }.buttonStyle(.borderedProminent)
                            Text("Kamu masih bisa mengoreksi hasilnya di editor, lalu menyimpan catatan.").font(.caption).foregroundStyle(.secondary)
                        }.padding(20).plateCard()
                    }
                    if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout) }
                }.padding(24)
            }.background(PlateBackground(status: .calm)).navigationTitle("Koreksi makanan")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { cancel(); dismiss() } } }
                .onChange(of: instruction) { _, _ in proposal = nil }
                .onChange(of: picker) { _, value in Task { do { if let data = try await value?.loadTransferable(type: Data.self) { attachedPhoto = try ImageCodec.prepare(data).full; proposal = nil } } catch { self.error = error.localizedDescription } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                    do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; attachedPhoto = try ImageCodec.prepare(Data(contentsOf: url)).full; proposal = nil } catch { self.error = error.localizedDescription }
                }
                .sheet(isPresented: $camera) {
                    #if os(iOS)
                    CameraPicker { data in do { if let data { attachedPhoto = try ImageCodec.prepare(data).full; proposal = nil } } catch { self.error = error.localizedDescription } }
                    #endif
                }
                .onDisappear { cancel() }
        }
        #if os(macOS)
        .frame(width: 620, height: 700)
        #endif
    }
    private func cancel() { requestID = UUID(); task?.cancel(); busy = false }
    private func analyze() {
        cancel(); busy = true; error = nil; proposal = nil; started = .now
        let id = UUID(); requestID = id
        let original = item; let correction = instruction; let picked = attachedPhoto ?? draftPhoto
        task = Task {
            do {
                var image = picked
                if image == nil, let existingPhotoPath { image = await PhotoStore.shared.load(path: existingPhotoPath, sync: model.sync) }
                try Task.checkCancellation()
                let result = try await model.recognition.refine(item: original, instruction: correction, imageData: image, cloudAllowed: cloudAllowed)
                try Task.checkCancellation(); guard id == requestID else { return }
                proposal = result; busy = false
            } catch is CancellationError { }
            catch { guard id == requestID else { return }; self.error = error.localizedDescription; busy = false }
        }
    }
}
