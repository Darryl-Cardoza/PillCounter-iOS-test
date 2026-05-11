//
//  PillCountingCalendar.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

//
//  PillCountingCalendar.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

struct PillCountingCalendar: View {

    @EnvironmentObject private var appColors: AppColors
    @Environment(\.isLandscape) private var isLandscape

    let selectedColor: Color
    let textColor: Color
    let backgroundColor: Color

    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Binding var monthsToShow: [Date]
    
    private let calendar = Calendar.current
    private let days = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(monthsToShow.enumerated()), id: \.offset) { index, month in
                        VStack(alignment: .leading, spacing: 10) {

                            // Month Header
                            HStack {
                                Spacer()
                                Text(monthYearString(for: month))
                                    .fontWeight(.regular)
                                    .foregroundColor(appColors.primary)
                                Spacer()
                            }
                            .id(index)

                            // Weekday Row
                            HStack {
                                ForEach(days.indices, id: \.self) { index in
                                    Text(days[index])
                                        .font(.caption)
                                        .foregroundColor(appColors.text)
                                        .frame(maxWidth: .infinity)
                                }
                            }

                            // Days Grid
                            let daysInMonth = getDaysInMonth(for: month)

                            LazyVGrid(
                                columns: Array(repeating: .init(.flexible(), spacing: 0), count: 7),
                                spacing: 6
                            ) {
                                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { index, date in
                                    if let date = date {
                                        dayCell(for: date, columnIndex: index % 7)
                                    } else {
                                        Color.clear.frame(height: 40)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .onAppear {
                if monthsToShow.isEmpty {
                    initializeMonths()
                }

                DispatchQueue.main.async {
                    if let index = monthIndex(for: Date()) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCell(for date: Date, columnIndex: Int) -> some View {
        let isStart   = startDate.map { isSameDay(date, $0) } ?? false
        let isEnd     = endDate.map   { isSameDay(date, $0) } ?? false
        let inRange   = isInRange(date)
        let future    = isFuture(date)

        // The range background should stretch full-width but be clipped on the
        // left for the start and on the right for the end (creating pill caps).
        ZStack {
            // ── Range background strip ──────────────────────────────────────
            if startDate != nil && endDate != nil {
                if inRange || isStart || isEnd {
                    GeometryReader { geo in
                        let h = geo.size.height
                        let inset: CGFloat = 5
                        // Determine which horizontal edges get rounded caps
                        let roundLeft  = isStart || columnIndex == 0
                        let roundRight = isEnd   || columnIndex == 6
                        
                        RoundedCornerShape(
                            topLeft:     roundLeft  ? h / 2 : 0,
                            bottomLeft:  roundLeft  ? h / 2 : 0,
                            topRight:    roundRight ? h / 2 : 0,
                            bottomRight: roundRight ? h / 2 : 0
                        )
                        .fill(selectedColor.opacity(0.25))
                        .padding(.leading, isStart ? inset : 0)
                        .padding(.trailing, isEnd ? inset : 0)
                        // and left half on end so the strip doesn't bleed outside.
                        .frame(
                            width: geo.size.width + (isStart && !isEnd ? geo.size.width * 0.0 : 0),
                            height: h
                        )
                    }
                }
            }

            // ── Circle for start / end endpoints ───────────────────────────
            if isStart || isEnd {
                Circle()
                    .fill(selectedColor)
                    .frame(width: 36, height: 36)
            }

            // ── Day number ─────────────────────────────────────────────────
            Button {
                guard !future else { return }
                handleTap(on: date)
            } label: {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body)
                    .foregroundColor(
                        (isStart || isEnd) ? .white :
                        inRange            ? textColor :
                                             textColor
                    )
                    .frame(width: 36, height: 36)
            }
            .disabled(future)
            .opacity(future ? 0.3 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
    }

    // MARK: - Selection Logic

    private func handleTap(on date: Date) {
        if startDate == nil {
            startDate = date
            endDate   = nil
        } else if startDate != nil && endDate == nil {
            if date < startDate! {
                endDate   = startDate
                startDate = date
            } else if isSameDay(date, startDate!) {
                // Tapping the same day again — deselect
                startDate = nil
            } else {
                endDate = date
            }
        } else {
            // Both set — restart selection
            startDate = date
            endDate   = nil
        }
    }

    // MARK: - Range Helpers
    private func monthIndex(for date: Date) -> Int? {
        monthsToShow.firstIndex {
            calendar.isDate($0, equalTo: date, toGranularity: .month)
        }
    }
    /// Returns true when `date` is strictly between startDate and endDate.
    private func isInRange(_ date: Date) -> Bool {
        guard let s = startDate, let e = endDate else { return false }
        return date > s && date < e
    }

    // MARK: - General Helpers

    private func initializeMonths() {
        let currentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: Date()))!
        monthsToShow = (0...12).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonth)
        }.reversed()
    }

    private func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func getDaysInMonth(for date: Date) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let firstDay = calendar.date(
                from: calendar.dateComponents([.year, .month], from: date))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        for day in range {
            if let dayDate = calendar.date(
                byAdding: .day, value: day - 1, to: firstDay) {
                days.append(dayDate)
            }
        }
        return days
    }

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    private func isFuture(_ date: Date) -> Bool {
        date > Date()
    }
}

// MARK: - Custom rounded-corner shape

/// Rectangle where each corner radius can be set independently.
private struct RoundedCornerShape: Shape {
    var topLeft: CGFloat     = 0
    var bottomLeft: CGFloat  = 0
    var topRight: CGFloat    = 0
    var bottomRight: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = min(topLeft,     rect.height / 2)
        let tr = min(topRight,    rect.height / 2)
        let bl = min(bottomLeft,  rect.height / 2)
        let br = min(bottomRight, rect.height / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
