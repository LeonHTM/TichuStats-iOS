//
//  GameSummaryShareView.swift
//  TichuStats
//
//  Created by Leon on 02.05.2026.
//

import SwiftUI

struct GameSummaryShareView: View {
    @Environment(\.colorScheme) var colorScheme
    let currentGameId: Int?
    let rounds: [Round]
    let profiles: [Profile]
    let accentCo: Color

    // MARK: - Helpers

    private var currentGame: Game? {
        NetworkService.shared.games.first(where: { $0.id == currentGameId })
    }

    private var allRounds: [Round] {
        rounds.filter { $0.gameId == currentGameId }
              .sorted { $0.roundOrder < $1.roundOrder }
    }

    private func profile(for id: Int?) -> Profile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }


    private var team1Ids: [Int?] {
        [currentGame?.team1Player1Id, currentGame?.team1Player2Id]
    }

    private var team2Ids: [Int?] {
        [currentGame?.team2Player1Id, currentGame?.team2Player2Id]
    }

    // Resolves a display name for any player id, including guests.
    private func playerName(_ id: Int?) -> String {
        let unknown = String(localized: "general.unknown")
        guard let id, let game = currentGame else { return unknown }
        switch id {
        case -2: return game.guest2Name ?? String(localized: "play.guest")
        case -3: return game.guest3Name ?? String(localized: "play.guest")
        case -4: return game.guest4Name ?? String(localized: "play.guest")
        default: return profile(for: id)?.name ?? unknown
        }
    }

    private func shortName(_ id: Int?) -> String {
        guard id != nil else { return "Uk" }
        return String(playerName(id).prefix(2))
    }

    func gameWinner() -> String {
        guard let currentGame else { return String(localized: "general.unknown") }
        switch currentGame.winner {
        case 1: return String(format: String(localized: "general.team"), "1")
        case 2: return String(format: String(localized: "general.team"), "2")
        case 3: return String(localized: "general.tie")
        default: return String(localized: "general.unknown")
        }
    }

    // Returns finishing place (1–4) of a player in a round, based on firstProfileId etc.
    private func place(of id: Int, in round: Round) -> String {
        if round.firstProfileId == id  { return "1" }
        if round.secondProfileId == id { return "2" }
        if round.thirdProfileId == id  { return "3" }
        return "4"
    }

    private func bombs(of id: Int, in round: Round) -> Int {
        if round.firstProfileId  == id { return round.firstBombs }
        if round.secondProfileId == id { return round.secondBombs }
        if round.thirdProfileId  == id { return round.thirdBombs }
        return round.fourthBombs
    }

    private func teamPlacement(ids: [Int?], currentRound: Round) -> some View {
        let p0Place = ids[0].map { place(of: $0, in: currentRound) } ?? "?"
        let p1Place = ids[1].map { place(of: $0, in: currentRound) } ?? "?"
        return Text("(\(p0Place)/\(p1Place))").monospaced()
    }

    private func announcementInfo(for id: Int, in round: Round) -> (text: String, color: Color) {
        let won = round.firstProfileId == id
        let resultColor: Color = won ? .green : .red

        if round.announcedBigTichu.contains(id) {
            return ("T", resultColor)
        } else if round.announcedTichu.contains(id) {
            return ("t", resultColor)
        } else if round.announcedPingu.contains(id) {
            return ("P", resultColor)
        }
        return ("C", .clear)
    }

    private func playerAnnounced(id: Int?, round: Round, lead: String) -> some View {
        let info = id.map { announcementInfo(for: $0, in: round) }
        let bomb = id.map { bombs(of: $0, in: round) } ?? 0
        let name = shortName(id)
        let alignment: Alignment = lead == "trailing" ? .trailing : .leading

        return Group {
            if let info, info.text != "C" {
                HStack {
                    if lead == "leading" {
                        Text(name).foregroundStyle(info.color).lineLimit(1)
                        Text("\(bomb)")
                        Text(info.text).foregroundStyle(info.color).lineLimit(1)
                    } else {
                        Text(info.text).foregroundStyle(info.color).lineLimit(1)
                        Text(name).foregroundStyle(info.color).lineLimit(1)
                        Text("\(bomb)")
                    }
                }
            } else {
                HStack {
                    Text(name).lineLimit(1)
                    Text("\(bomb)")
                }
            }
        }
        .font(.system(size: 17))
        .monospaced()
        .frame(width: 60, alignment: alignment)
    }

    private func teamAnnounced(ids: [Int?], round: Round, lead: String) -> some View {
        HStack {
            playerAnnounced(id: ids[0], round: round, lead: lead)
            playerAnnounced(id: ids[1], round: round, lead: lead)
        }
        .opacity(colorScheme == .dark ? 0.66 : 1)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            Text(String(localized: "gamesummaryshare.title"))
                .font(.largeTitle)
                .fontWeight(.bold)

            // Team names
            HStack {
                VStack {
                    Text(String(format: String(localized: "general.team.double"), String(1))).fontWeight(.bold)
                    Text(playerName(team1Ids[0])).font(.title).fontWeight(.bold)
                    Text(playerName(team1Ids[1])).font(.title).fontWeight(.bold)
                }.foregroundStyle(accentCo)
                Spacer()
                VStack {
                    Text(String(format: String(localized: "general.team.double"), String(2))).fontWeight(.bold)
                    Text(playerName(team2Ids[0])).font(.title).fontWeight(.bold)
                    Text(playerName(team2Ids[1])).font(.title).fontWeight(.bold)
                }
            }.padding(.horizontal, 30)

            GameSummaryChartView(
                currentGameId: currentGameId
            )
            .frame(height: 250)

            // Score
            HStack {
                VStack {
                    Text(String(format: String(localized: "general.team"), String(1)))
                        .font(.headline)
                        .foregroundStyle(accentCo)
                    Text("\(currentGame?.currentPointsTeam1 ?? 0)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(accentCo)
                }
                Spacer()
                VStack {
                    Text(String(format: String(localized: "gamesummaryshare.target"), String(currentGame?.target ?? 1000))).fontWeight(.bold)
                    Text(String(format: String(localized: "gamesummaryshare.winner"), gameWinner())).fontWeight(.bold)
                        .foregroundStyle(currentGame?.winner == 1 ? accentCo : Color.primary)
                }
                Spacer()
                VStack {
                    Text(String(format: String(localized: "general.team"), String(2))).font(.headline)
                    Text("\(currentGame?.currentPointsTeam2 ?? 0)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
            }.padding(.horizontal, 30)

            // Round details
            Text(String(localized: "gamesummaryshare.details")).fontWeight(.bold).font(.title)
            HStack {
                Text(String(format: String(localized: "general.team"), String(1))).padding(.trailing, 23).foregroundStyle(accentCo)
                Text(String(localized: "gamesummaryshare.rounds")).fontWeight(.bold)
                Text(String(format: String(localized: "general.team"), String(2))).padding(.leading, 20)
            }

            HStack(alignment: .top) {
                VStack {
                    ForEach(allRounds) { currentRound in
                        HStack {
                            teamPlacement(ids: team1Ids, currentRound: currentRound)
                                .frame(width: 60, alignment: .trailing)
                                .padding(.trailing, 60)

                            teamAnnounced(ids: team1Ids, round: currentRound, lead: "trailing")
                                .frame(width: 65, alignment: .trailing)

                            Text("\(currentRound.tichuPointsTeam1)")
                                .fontWeight(.bold)
                                .frame(width: 50, alignment: .trailing)
                                .monospaced()
                        }
                    }
                }

                VStack {
                    ForEach(allRounds) { currentRound in
                        HStack {
                            Text("\(currentRound.tichuPointsTeam2)")
                                .fontWeight(.bold)
                                .frame(width: 50, alignment: .leading)
                                .monospaced()

                            teamAnnounced(ids: team2Ids, round: currentRound, lead: "leading")
                                .frame(width: 65, alignment: .leading)

                            teamPlacement(ids: team2Ids, currentRound: currentRound)
                                .frame(width: 60, alignment: .leading)
                                .padding(.leading, 60)
                        }
                    }
                }
            }

            HStack {
                Text(String(localized: "general.madeWith")).fontWeight(.bold)
                Image("AppLogo").resizable().frame(width: 45, height: 45)
            }

        }
        .frame(width: 500)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

#Preview {
    GameSummaryShareView(currentGameId: 20, rounds: [], profiles: [], accentCo: .accentColor)
}
