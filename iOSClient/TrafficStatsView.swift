import SwiftUI
import Charts

/// 流量统计界面（本 fork）：累计、近 7 天、今天的收发量，按小时（近 24 小时）或按天（近 7 天）的柱状图和明细。
/// 数据在 `StreamClient.traffic`（TrafficStats），只在本机。从设置面板的本机分组和连接界面的标题旁打开。
struct TrafficStatsView: View {
    @ObservedObject var client: StreamClient
    let close: () -> Void

    enum Range: Hashable { case hours, days }
    @State private var range: Range = .hours
    @State private var confirmReset = false

    private var now: Date { Date() }
    private var calendar: Calendar { .current }

    private var buckets: [TrafficStats.Bucket] {
        switch range {
        case .hours: return client.traffic.lastHours(24, now: now, calendar: calendar)
        case .days: return client.traffic.lastDays(7, now: now, calendar: calendar)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryRow(String(localized: "Total", comment: "流量统计：累计"), client.traffic.total,
                               detail: client.traffic.since.map {
                                   String(localized: "Since \($0.formatted(date: .abbreviated, time: .shortened))", comment: "流量统计：累计从何时开始，插值为日期时间")
                               })
                    summaryRow(String(localized: "Last 7 Days", comment: "流量统计：近 7 天"), client.traffic.lastSevenDays(now: now, calendar: calendar), detail: nil)
                    summaryRow(String(localized: "Today", comment: "流量统计：今天"), client.traffic.today(now: now, calendar: calendar), detail: nil)
                }

                Section {
                    Picker(String(localized: "Range", comment: "流量统计：按小时或按天的选择器"), selection: $range) {
                        Text(String(localized: "By Hour", comment: "流量统计：按小时（近 24 小时）")).tag(Range.hours)
                        Text(String(localized: "By Day", comment: "流量统计：按天（近 7 天）")).tag(Range.days)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    chart
                        .frame(height: 200)
                        .padding(.vertical, 8)
                } header: {
                    Text(range == .hours ? String(localized: "Last 24 Hours", comment: "流量统计：图表标题，近 24 小时")
                                         : String(localized: "Last 7 Days", comment: "流量统计：近 7 天"))
                }

                Section {
                    ForEach(buckets.reversed(), id: \.start) { bucket in
                        HStack {
                            Text(label(bucket.start))
                                .foregroundStyle(.secondary)
                            Spacer()
                            usageText(bucket.usage)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text(String(localized: "Counts the data Sill exchanges with your Macs on this device: what it receives (the picture, sound, window lists) and what it sends (input, pings). Network overhead isn’t included, so your carrier may count a few percent more. Kept on this device only.", comment: "流量统计：说明统计口径"))
                }

                Section {
                    Button(String(localized: "Reset Statistics", comment: "流量统计：清零按钮"), role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle(String(localized: "Data Usage", comment: "流量统计界面标题"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "流量统计：关闭"), action: close)
                }
            }
            .confirmationDialog(String(localized: "Reset all data usage statistics?", comment: "流量统计：清零确认"),
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button(String(localized: "Reset Statistics", comment: "流量统计：清零按钮"), role: .destructive) { client.resetTraffic() }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { client.flushTraffic() }
    }

    private var chart: some View {
        Chart(buckets, id: \.start) { bucket in
            BarMark(x: .value(String(localized: "Time", comment: "流量统计：图表横轴"), bucket.start, unit: range == .hours ? .hour : .day),
                    y: .value(String(localized: "Data", comment: "流量统计：图表纵轴"), Double(bucket.usage.total) / 1_000_000))
                .foregroundStyle(Palette.accent)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let mb = value.as(Double.self) { Text(Self.bytes(Int64(mb * 1_000_000))) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: range == .hours ? .hour : .day, count: range == .hours ? 6 : 1)) { value in
                AxisGridLine()
                AxisValueLabel(format: range == .hours ? .dateTime.hour() : .dateTime.weekday(.abbreviated))
            }
        }
        .accessibilityLabel(range == .hours ? String(localized: "Last 24 Hours", comment: "流量统计：图表标题，近 24 小时")
                                            : String(localized: "Last 7 Days", comment: "流量统计：近 7 天"))
    }

    private func summaryRow(_ title: String, _ usage: TrafficStats.Usage, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.bytes(usage.total)).font(.headline.monospacedDigit())
                Text("↓ \(Self.bytes(usage.received))  ↑ \(Self.bytes(usage.sent))", comment: "流量统计：收到与发出的数据量，插值为数据量")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func usageText(_ usage: TrafficStats.Usage) -> some View {
        Text(Self.bytes(usage.total)).monospacedDigit()
    }

    private func label(_ start: Date) -> String {
        switch range {
        case .hours:
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
            let day = calendar.isDateInToday(start) ? "" : start.formatted(.dateTime.month().day()) + " "
            return day + start.formatted(date: .omitted, time: .shortened) + "–" + end.formatted(date: .omitted, time: .shortened)
        case .days:
            return start.formatted(.dateTime.month().day().weekday(.abbreviated))
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
