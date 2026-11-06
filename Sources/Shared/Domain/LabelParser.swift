import Foundation

public enum LabelParser {
    // Nutrient names. Plurals are accepted ("Proteins", "Fats", "Carbs") and "Cal" counts as calories.
    static let caloriesName = #"(?:total[ \t]+)?(?:calories|calorie|kalori|energi(?:[ \t]+total)?|energy|kcal|kkal|cal)"#
    static let proteinName = #"proteins?"#
    static let carbsName = #"(?:total[ \t]+)?(?:carbohydrates?|carbs?|karbohidrat(?:[ \t]+total)?)"#
    static let fatName = #"(?<!from )(?:total[ \t]+fats?|fats?|lemak(?:[ \t]+total)?)"#
    static let fiberName = #"(?:dietary[ \t]+)?(?:fiber|fibre|serat(?:[ \t]+pangan)?)"#
    static let sugarName = #"(?:total[ \t]+)?(?:sugars?|gula)"#
    static let unit = #"(?:kcal|kkal|cal|kj|mg|grams?|gram|gr|g|ml)"#

    public static func looksLikeNutrition(_ text: String) -> Bool {
        let t = text.lowercased()
        let hasEnergyValue = t.range(of: #"\d[\d.,]*[ \t]*(?:kcal|kkal|kj|cal)\b"#, options: .regularExpression) != nil
        return hasEnergyValue || ["calories", "kcal", "kkal", "kj", "energy", "energi", "protein", "carbs", "fat", "karbohidrat", "nutrition facts"].filter { t.contains($0) }.count >= 2
    }
    public static func parse(_ text: String) -> MealAnalysis? {
        guard looksLikeNutrition(text) else { return nil }
        let t = text.lowercased().replacingOccurrences(of: "\u{00a0}", with: " ")
        let lines = t.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let per100 = t.range(of: #"(?:per|tiap|setiap)\s*100\s*(?:g|ml|gram)"#, options: .regularExpression) != nil
        let perPackage = t.range(of: #"(?:per|tiap|setiap)\s*(?:package|pack|kemasan)"#, options: .regularExpression) != nil
        let servingGrams = number(t, #"(?:serving size|takaran saji)[ \t]*[:：]?[ \t]*(?:\d+[ \t]*[^\d\n(]+\()?[ \t]*([\d.,]+)[ \t]*(?:g\b|gram|ml)"#)
        let servings = number(t, #"(?:servings per (?:container|package)|(?:jumlah )?sajian per kemasan)[ \t]*[:：]?[ \t]*(?:about|sekitar)?[ \t]*([\d.,]+)"#)
        var kcal = nutrient(lines, caloriesName)
        if let kj = number(t, #"([\d.,]+)[ \t]*kj\b"#), t.range(of: #"\d[ \t]*(?:kcal|kkal|cal)\b"#, options: .regularExpression) == nil { kcal = kj/4.184 }
        else if let explicit = number(t, #"([\d.,]+)[ \t]*(?:kcal|kkal)\b"#) { kcal = explicit }
        let p = nutrient(lines, proteinName)
        let c = nutrient(lines, carbsName)
        let f = nutrient(lines, fatName)
        let fiber = nutrient(lines, fiberName)
        let sugar = nutrient(lines, sugarName)
        let values = ["calories": kcal, "protein": p, "carbs": c, "fat": f]
        guard values.values.contains(where: { $0 != nil }) else { return nil }
        let basis: ServingBasis = per100 ? .per100Grams : perPackage ? .package : .serving
        let label = LabelDetails(basis: basis, servingGrams: servingGrams, servingsPerPackage: servings, rawText: text)
        var item = FoodItem(name: productName(text) ?? "Scanned food", category: .snacks, servingDescription: per100 ? "100 g / ml" : perPackage ? "1 package" : "1 serving", nutrients: .init(calories: kcal ?? 0, protein: p ?? 0, carbs: c ?? 0, fat: f ?? 0, fiber: fiber ?? 0, sugar: sugar ?? 0), quantity: label.quantity(servings: 1), confidence: 0.98, source: .label)
        item.needsReviewFields = values.filter { $0.value == nil }.map(\.key).sorted()
        return MealAnalysis(kind: .label, items: [item], label: label, explanation: "Read directly from the nutrition label. Confirm the serving basis and fill any highlighted values.")
    }

    /// Finds a nutrient's amount on the line where its name is printed. Handles both
    /// "Protein 25 g" and "25 g Proteins". A value never comes from another row, except when
    /// the name sits alone on its line and the next line holds only the amount (split OCR columns).
    static func nutrient(_ lines: [String], _ name: String) -> Double? {
        let named = #"(?<![a-z])(?:"# + name + #")(?![a-z])"#
        let after = named + #"[ \t]*(?:\([^)\n]*\))?[ \t]*[:：]?[ \t]*([\d.,]+)"#
        let before = #"(?<![\d.,])([\d.,]+)[ \t]*(?:"# + unit + #")?[ \t]*(?:of[ \t]+)?"# + named
        let alone = #"^"# + named + #"[ \t]*(?:\([^)]*\))?[ \t]*[:：]?$"#
        let valueOnly = #"^([\d.,]+)[ \t]*(?:"# + unit + #")?$"#
        for (index, line) in lines.enumerated() {
            // A row that starts with a number ("25 g Proteins") reads value-first; otherwise name-first.
            let valueFirst = line.first?.isNumber == true
            if let value = valueFirst ? (number(line, before) ?? number(line, after)) : (number(line, after) ?? number(line, before)) { return value }
            if index + 1 < lines.count, line.range(of: alone, options: .regularExpression) != nil, let value = number(lines[index + 1], valueOnly) { return value }
        }
        return nil
    }

    /// Best-effort product name: the text printed just above the first nutrient row,
    /// e.g. "CLASSIC CAESAR / CHICKEN SALAD" above "328 Cal". Returns nil when unclear.
    public static func productName(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lower = lines.map { $0.lowercased() }
        let anyName = [caloriesName, proteinName, carbsName, fatName].map { #"(?<![a-z])(?:"# + $0 + #")(?![a-z])"# }
        guard let first = lower.firstIndex(where: { line in line.range(of: #"\d"#, options: .regularExpression) != nil && anyName.contains { line.range(of: $0, options: .regularExpression) != nil } }) else { return nil }
        let blocked = #"\b(?:nutrition|gizi|serving|servings|takaran|sajian|per|tiap|ingredients|komposisi|informasi|amount)\b"#
        func usable(_ i: Int) -> Bool {
            let l = lower[i]
            return l.range(of: #"\d"#, options: .regularExpression) == nil && l.range(of: #"[a-z]{2}"#, options: .regularExpression) != nil && l.count <= 40 && l.range(of: blocked, options: .regularExpression) == nil
        }
        guard first > 0, usable(first - 1) else { return nil }
        var parts = [lines[first - 1]]
        // Join a second line only when it reads like part of the same title (two-plus words, short overall).
        if first > 1, usable(first - 2), lines[first - 2].split(separator: " ").count >= 2, (lines[first - 2] + " " + parts[0]).count <= 32 { parts.insert(lines[first - 2], at: 0) }
        let name = parts.joined(separator: " ")
        return name == name.uppercased() ? name.capitalized : name
    }

    static func number(_ text: String, _ pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        var value = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        // Nutrition labels generally use a single decimal separator. Handle grouped thousands too.
        if value.contains(",") && value.contains(".") {
            if value.lastIndex(of: ",")! > value.lastIndex(of: ".")! { value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { value = value.replacingOccurrences(of: ",", with: "") }
        } else { value = value.replacingOccurrences(of: ",", with: ".") }
        guard let result = Double(value), result.isFinite, result >= 0 else { return nil }
        return result
    }
}
