import Foundation

/// Mirrors the terminal's interval/lane layout. Completed cards are history;
/// maximal available spans can occupy a parallel lane beside them.
struct DayTimelineLayout {
    struct Card: Identifiable {
        let id: String
        let item: Occurrence?
        let interval: FreeGap
        var lane: Int = 0
        var lanes: Int = 1
        var group: Int = 0
    }
    struct Span {
        let start: Int
        let end: Int
        let top: Double
        let height: Double
    }
    let cards: [Card]
    let gaps: [FreeGap]
    let spans: [Span]
    let height: Double
    var maxLanes: Int { cards.map(\.lanes).max() ?? 1 }

    init(items: [Occurrence], day: String, minimumHeight: Double = 88) {
        let timed = items.compactMap { item -> Card? in
            DaySchedule.timedInterval(item, day: day).map { Card(id: item.id, item: item, interval: $0) }
        }
        let free = DaySchedule.gaps(items, day: day)
        let besideHistory = free.filter { gap in
            timed.contains { $0.item?.isComplete == true && $0.interval.start < gap.end && $0.interval.end > gap.start }
        }
        gaps = free.filter { !besideHistory.contains($0) }
        var blocks = timed + besideHistory.map { Card(id: "free-\($0.start)", item: nil, interval: $0) }
        blocks.sort {
            if $0.interval.start != $1.interval.start { return $0.interval.start < $1.interval.start }
            if ($0.item == nil) != ($1.item == nil) { return $0.item == nil }
            if $0.interval.end != $1.interval.end { return $0.interval.end > $1.interval.end }
            return $0.id < $1.id
        }
        var group = -1, groupEnd = -1, laneEnds: [Int] = [], members: [Int] = []
        for index in blocks.indices {
            if blocks[index].interval.start >= groupEnd {
                for member in members { blocks[member].lanes = laneEnds.count }
                group += 1; groupEnd = -1; laneEnds = []; members = []
            }
            let interval = blocks[index].interval
            let lane = laneEnds.firstIndex { $0 <= interval.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(interval.end) } else { laneEnds[lane] = interval.end }
            groupEnd = max(groupEnd, interval.end)
            blocks[index].lane = lane; blocks[index].group = group
            members.append(index)
        }
        for member in members { blocks[member].lanes = laneEnds.count }
        cards = blocks

        let ticks = stride(from: 60, to: 1440, by: 60).filter { minute in
            timed.contains { $0.interval.start < minute && minute < $0.interval.end }
        }
        let boundaries = Set([0, 1440] + ticks + blocks.flatMap { [$0.interval.start, $0.interval.end] }).sorted()
        var top = 0.0, result: [Span] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let busy = timed.contains { $0.interval.start < end && $0.interval.end > start }
            let height = busy ? max(minimumHeight, Double(end - start) * minimumHeight / 60) : minimumHeight
            result.append(Span(start: start, end: end, top: top, height: height))
            top += height
        }
        spans = result; height = top
    }

    func y(_ minute: Int) -> Double {
        if minute >= 1440 { return height }
        guard let span = spans.first(where: { $0.start <= minute && minute < $0.end }) else { return 0 }
        return span.top + Double(minute - span.start) / Double(span.end - span.start) * span.height
    }
}
