//
//  StatsContainer.swift
//  TichuStats
//
//  Created by Leon on 24.04.2026.
//

import SwiftUI
import Charts
import Observation

//MARK: - Helpers


func formatStat(_ v: Double, percentage: Bool, digits: Int) -> String {
    if percentage { return "\(Int(v * 100))%" }
    if digits == 0 { return "\(Int(v))" }
    return v.formatted(.number.precision(.fractionLength(digits)))
}

extension Timeframe {
    // Key used by the server for this timeframe.
    var serverTimeframeKey: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        case .allTime: return "all_time"
        }
    }

    // Localized label shown on the stats cards.
    var cardLabel: String {
        switch self {
        case .day: return String(localized: "statistics.timeframe.day")
        case .week: return String(localized: "statistics.timeframe.week")
        case .month: return String(localized: "statistics.timeframe.month")
        case .year: return String(localized: "statistics.timeframes.year")
        case .allTime: return String(localized: "statistics.timeframes.alltime")
        }
    }
}

//MARK: - Comparison list (shared by StatsContainer and StatsDetailView)
struct ComparisonList: View {
    @Environment(\.colorScheme) private var colorScheme

    let items: [Profile]
    let stat: Profile.playerStat
    let timeframe: Timeframe
    let value: Double
    let percentage: Bool
    let reverse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let itemValue = item.getStat(for: stat, timeframe: timeframe)
                let icon = icon(for: itemValue)

                VStack(spacing: 0) {
                    HStack {
                        HStack {
                            Image(systemName: icon.name)
                                .foregroundStyle(icon.color)
                                .opacity(colorScheme == .dark ? 0.6 : 0.75)
                                .font(.system(size: 14))
                                .redactedShimmer()
                            Text(item.name ?? "")
                                .font(.system(size: 13))
                                .redactedShimmer()
                        }
                        .lineLimit(1)

                        Spacer()

                        Text(formatStat(itemValue, percentage: percentage, digits: 0))
                            .font(.system(size: 14))
                            .redactedShimmer()
                    }
                    .padding(.bottom, 3)
                    .padding(.top, -5)

                    if index != items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .animation(.easeInOut, value: items)
    }

    private func icon(for other: Double) -> (name: String, color: Color) {
        if other == value { return ("equal.circle.fill", .yellow) }
        let isUp = (other > value) != reverse
        return isUp ? ("chevron.up.circle.fill", .green)
                    : ("chevron.down.circle.fill", .red)
    }
}

//MARK: - StatsContainer used in StatsView
struct StatsContainer: View {
    @AppStorage("isLoading") private var isLoading = false
    @Environment(\.colorScheme) var colorScheme

    //MARK: Vars
    var title: String
    var description: String
    var image: String
    var counterLeft: Int
    var counterRight: Int
    var value: Double
    var percentage: Bool
    var inTop: Double
    var stat: Profile.playerStat
    @Binding var timeframe: Timeframe
    //MARK: Computed Vars
    var items: [Profile]
    var digits: Int = 0
    var reverse: Bool = false
    var renderedImage: Image?

    @State private var containerWidth: CGFloat = 0

    //MARK: Body
    var body: some View {
        NavigationLink {
            StatsDetailView(
                value: value,
                percentage: percentage,
                inTop: inTop,
                stat: stat,
                timeframe: $timeframe,
                items: items,
                digits: digits,
                reverse: reverse,
                renderedImage: renderedImage
                
            )
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Text(title)
                        .font(.system(size: 20))
                        .lineLimit(1)
                        .minimumScaleFactor(0.50)
                        .fontWeight(.bold)
                        .redactedShimmer()
                    Spacer()

                    Image(systemName: "chevron.right.circle.fill").foregroundStyle(Color.secondary)
                        .redactedShimmer()
                        .font(.system(size: 16))
                }.padding(.bottom, 6)

                VStack(alignment: .leading) {
                    ZStack {
                        // Elo is always all-time
                        Text(stat == .elo ? Timeframe.allTime.cardLabel : timeframe.cardLabel)
                    }
                    .animation(.easeInOut, value: timeframe)
                    .font(.system(size: 14))
                    .redactedShimmer()

                    HStack {
                        Text(formatStat(value, percentage: percentage, digits: digits))
                            .redactedShimmer()
                    }
                    .foregroundColor(.accentColor)
                    .font(.system(size: 29))
                    .fontWeight(.bold)
                }

                Spacer()

                if !items.isEmpty && !isLoading {
                    Text(String(localized: "statistics.statscontainer.comparison"))
                        .font(.system(size: 14))
                        .padding(.bottom, -5)
                        .padding(.top, 1)
                        .redactedShimmer()
                    Divider()
                    ComparisonList(
                        items: items,
                        stat: stat,
                        timeframe: timeframe,
                        value: value,
                        percentage: percentage,
                        reverse: reverse
                    )
                } else {
                    Text(String(localized: "statistics.statscontainer.explanation"))
                        .font(.system(size: 14))
                        .padding(.bottom, -5)
                        .padding(.top, 1)
                        .padding(.bottom, 5)
                        .redactedShimmer()
                    Text(description)
                        .font(.system(size: 16))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                        .redactedShimmer()
                }

                
            }
            .padding(10)
            .frame(maxHeight: .infinity)
            .frame(minHeight: max(containerWidth, 164), alignment: .topLeading)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) {
                            containerWidth = geo.size.width
                        }
                }
            )
            .background(colorScheme == .dark ? Color(uiColor: .tertiarySystemFill) : .white, in: .rect(cornerRadius: 24))
        }
        .disabled(isLoading)
        .foregroundStyle(Color.primary)
    }
}

//MARK: - Sortby enum

enum sortBy: String, CaseIterable {
    case valueUp
    case valueDown
    case nameUp
    case nameDown
}
