import SwiftUI

struct DayTimelineView: View {
    let model: CalendarConnectionModel
    let date: Date
    let now: Date
    let onSelect: (Occurrence) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var minimumHeight = 88.0
    @ScaledMetric(relativeTo: .subheadline) private var minimumLaneWidth = 136.0

    private var day: String { Dates.key(date) }
    private var items: [Occurrence] { model.items(on: date) }
    private var minute: Int? { DaySchedule.availability(items, day: day, now: now).minute }

    var body: some View {
        let layout = DayTimelineLayout(items: items, day: day, minimumHeight: minimumHeight)
        VStack(alignment: .leading, spacing: 10) {
            let markers = items.filter { DaySchedule.timedInterval($0, day: day) == nil }
            if !markers.isEmpty {
                Text("Due & notes").font(.caption).foregroundStyle(Whale.muted)
                ForEach(markers) { item in
                    Button { onSelect(item) } label: { EventRow(item: item, calendar: model.calendar(item.event.calendarId), now: now) }.buttonStyle(.plain)
                }
                if markers.contains(where: { !$0.isComplete && !$0.event.isDeadline && $0.event.startTime != nil && $0.event.endTime == nil }) {
                    Text("Events without end times don’t block availability.").font(.caption).foregroundStyle(Whale.muted)
                }
            }
            if layout.maxLanes > 2 {
                Text("Swipe across the timeline for more parallel events").font(.caption).foregroundStyle(Whale.muted)
            }
            GeometryReader { geometry in
                let axis = 46.0
                let available = max(1, geometry.size.width - axis)
                HStack(alignment: .top, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        ForEach(layout.spans, id: \.start) { span in
                            Text(Dates.clock(span.start)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Whale.muted)
                                .offset(y: layout.y(span.start))
                        }
                        Text("24:00").font(.system(size: 10, design: .monospaced)).foregroundStyle(Whale.muted).offset(y: layout.height)
                    }.frame(width: axis, height: layout.height + 20, alignment: .topLeading)
                    ScrollView(.horizontal) {
                        timeline(layout, width: max(available, Double(layout.maxLanes) * minimumLaneWidth))
                    }.scrollIndicators(.visible)
                }
            }.frame(height: layout.height + 20)
            if !model.connected {
                Text("Based on the saved schedule").font(.caption).foregroundStyle(Whale.warning)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("Day timeline")
    }

    private func timeline(_ layout: DayTimelineLayout, width: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.spans, id: \.start) { span in
                Rectangle().fill(Whale.muted.opacity(0.12)).frame(height: 1).offset(y: span.top)
            }
            ForEach(layout.gaps) { gap in
                freeTime(gap).frame(width: width, alignment: .leading).offset(y: layout.y(gap.start) + 18)
            }
            ForEach(layout.cards) { card in
                let laneWidth = width / Double(card.lanes)
                let height = layout.y(card.interval.end) - layout.y(card.interval.start) - 6
                Group {
                    if let item = card.item {
                        eventCard(item, interval: card.interval)
                            .frame(width: laneWidth - 6, height: height, alignment: .topLeading)
                    } else {
                        freeTime(card.interval).frame(width: laneWidth - 6, height: height, alignment: .topLeading).padding(.top, 18)
                    }
                }.offset(x: Double(card.lane) * laneWidth, y: layout.y(card.interval.start))
            }
            if let minute {
                HStack(spacing: 4) {
                    Text("Now \(Dates.clock(minute))").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4).background(Whale.background)
                    Rectangle().frame(height: 1)
                }.foregroundStyle(Whale.accent).frame(width: width).offset(y: layout.y(minute))
                    .allowsHitTesting(false).accessibilityIdentifier("Current time")
            }
        }.frame(width: width, height: layout.height + 20, alignment: .topLeading)
    }

    private func eventCard(_ item: Occurrence, interval: FreeGap) -> some View {
        let color = item.isComplete ? Whale.muted : Color(hex: model.calendar(item.event.calendarId)?.color ?? "#1d9bf0")
        let active = !item.isComplete && (minute.map { interval.contains($0) } ?? false)
        return Button { onSelect(item) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text((item.isComplete ? "✓ " : "") + item.event.title).font(.subheadline.weight(.medium))
                    .strikethrough(item.isComplete).foregroundStyle(item.isComplete ? Whale.muted : .white)
                    .lineLimit(2)
                Text("\(Dates.clock(interval.start))–\(Dates.clock(interval.end))")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(color)
                if active { Text("Now").font(.caption.weight(.semibold)).foregroundStyle(Whale.accent) }
                Spacer(minLength: 0)
            }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(color.opacity(item.isComplete ? 0.035 : 0.10), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.7), lineWidth: 1))
                .contentShape(Rectangle()).clipped()
        }.buttonStyle(.plain)
            .accessibilityLabel("\(item.event.title), \(Dates.clock(interval.start)) to \(Dates.clock(interval.end)), \(model.calendar(item.event.calendarId)?.name ?? "Calendar")\(item.isComplete ? ", completed history; does not reserve time" : "")")
            .accessibilityIdentifier("Timeline event \(item.id)")
    }

    private func freeTime(_ gap: FreeGap) -> some View {
        let current = minute.map { gap.contains($0) } ?? false
        return VStack(alignment: .leading, spacing: 4) {
            Text("Free \(Dates.clock(gap.start))–\(Dates.clock(gap.end))").font(.system(.caption, design: .monospaced))
            Text(current ? "\(Dates.duration(gap.end - (minute ?? gap.start))) left" : Dates.duration(gap.duration)).font(.caption)
        }.foregroundStyle(Whale.green).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine).accessibilityIdentifier(current ? "Current free time" : "Free time block")
    }
}
