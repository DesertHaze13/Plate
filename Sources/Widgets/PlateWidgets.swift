import SwiftUI
import WidgetKit
import AppIntents
import PlateCore

struct PlateEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}
struct PlateProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlateEntry { .init(date: .now, snapshot: .init(dayKey: DayKey.make(.now), eaten: .init(calories: 1750, protein: 120), targets: .init(calories: 2400, protein: 150))) }
    func getSnapshot(in context: Context, completion: @escaping (PlateEntry) -> Void) { completion(context.isPreview ? placeholder(in: context) : .init(date: .now, snapshot: .read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlateEntry>) -> Void) { completion(Timeline(entries: [.init(date: .now, snapshot: .read())], policy: .after(.now.addingTimeInterval(15*60)))) }
}
struct PlateWidgetView: View {
    let entry: PlateEntry
    @Environment(\.widgetFamily) private var family
    private var isCircular: Bool {
        #if os(iOS)
        family == .accessoryCircular
        #else
        false
        #endif
    }
    private var isInline: Bool {
        #if os(iOS)
        family == .accessoryInline
        #else
        false
        #endif
    }
    private var isRectangular: Bool {
        #if os(iOS)
        family == .accessoryRectangular
        #else
        false
        #endif
    }
    private var remaining: Int { Int((entry.snapshot?.targets.calories ?? 0)-(entry.snapshot?.eaten.calories ?? 0)) }
    private var proteinFraction: Double { min(1, (entry.snapshot?.eaten.protein ?? 0)/max(1, entry.snapshot?.targets.protein ?? 1)) }
    var body: some View {
        Group {
            if isCircular {
                Gauge(value: proteinFraction) { Image(systemName: "fork.knife") } currentValueLabel: { Text("\(max(0,remaining))").font(.caption) }.gaugeStyle(.accessoryCircular).accessibilityLabel("\(remaining) calories remaining, \(Int(proteinFraction*100)) percent protein target")
            } else if isInline { Text("Plate · \(remaining) kcal left") }
            else if isRectangular { VStack(alignment: .leading) { Text("\(remaining) kcal left").font(.headline); ProgressView(value: proteinFraction).tint(.mint); Text("\(Int(entry.snapshot?.eaten.protein ?? 0)) g protein").font(.caption2) } }
            else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("PLATE", systemImage: "circle.inset.filled").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        if entry.snapshot == nil { Text("Set your goals").font(.headline); Text("Open Plate to start.").font(.caption).foregroundStyle(.secondary) }
                        else { Text("\(abs(remaining))").font(.system(size: 36, weight: .light, design: .rounded)); Text(remaining >= 0 ? "kcal remaining" : "kcal over target").font(.caption).foregroundStyle(.secondary) }
                    }
                    if family == .systemMedium {
                        Spacer()
                        ZStack { Circle().stroke(.mint.opacity(0.15), lineWidth: 8); Circle().trim(from: 0, to: proteinFraction).stroke(.mint, style: StrokeStyle(lineWidth: 8,lineCap: .round)).rotationEffect(.degrees(-90)); VStack { Text("\(Int(entry.snapshot?.eaten.protein ?? 0)) g").font(.headline); Text("protein").font(.caption2).foregroundStyle(.secondary) } }.frame(width: 80,height: 80).accessibilityLabel("Protein \(Int(entry.snapshot?.eaten.protein ?? 0)) of \(Int(entry.snapshot?.targets.protein ?? 0)) grams")
                    }
                }
            }
        }.containerBackground(for: .widget) { Color.mint.opacity(0.05) }.widgetURL(URL(string: "plate://today"))
    }
}
struct PlateTodayWidget: Widget {
    let kind = "com.dony.plate.today"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlateProvider()) { PlateWidgetView(entry: $0) }
            .configurationDisplayName("Your plate today").description("Calories remaining and your protein progress.")
            #if os(iOS)
            .supportedFamilies([.systemSmall,.systemMedium,.accessoryCircular,.accessoryInline,.accessoryRectangular])
            #else
            .supportedFamilies([.systemSmall,.systemMedium])
            #endif
    }
}
#if os(iOS)
struct PlateCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dony.plate.capture") { ControlWidgetButton(action: LogMealIntent()) { Label("Log a meal", systemImage: "camera") } }.displayName("Log a meal").description("Open Plate's camera from Control Center or the Action button.")
    }
}
#endif
@main struct PlateWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlateTodayWidget()
        #if os(iOS)
        PlateCaptureControl()
        #endif
    }
}
