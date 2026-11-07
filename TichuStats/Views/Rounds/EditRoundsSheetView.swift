//
//  EditRoundsSheetView.swift
//  TichuStats
//
//  Created by Leon on 27.04.2026.
//

import SwiftUI
import Combine

struct EditRoundsSheetView: View {
    @Binding var showEditRoundsSheet: Bool
    @State private var selectedTab: Int = 1
    @State private var showDeleteGameAlert: Bool = false
    @ObservedObject var network: NetworkService
    @State private var target: Int = 1000
    @State private var showFinishGameAlert: Bool = false
    var currentGameId: Int
    @Binding var tie: Bool
    
    
    private var currentGame: Game? {
        network.games.first(where: { $0.id == currentGameId })
    }
    
    private var allRounds: [Round] {
        (network.roundsByGame[currentGameId] ?? [])
            .sorted { $0.roundOrder < $1.roundOrder }
    }
    
    private var currentPointsTeam1: Int { currentGame?.currentPointsTeam1 ?? -69420 }
    private var currentPointsTeam2: Int { currentGame?.currentPointsTeam2 ?? -69420 }

    var body: some View{
        NavigationStack{
            Group {
                switch selectedTab {
                case 0:
                    VStack {
                        GameSummaryChartView(currentGameId: currentGameId)
                            .frame(width: 350)
                            .padding(.top,25)
                        Spacer()
                    }
                case 1:
                    EditRoundsListView(network:network,currentGameId: currentGameId, allRounds: allRounds)
                        .padding(.bottom, -50)
                        .padding(.top,-25)
                default:
                    EditRoundsListView(network:network,currentGameId: currentGameId, allRounds: allRounds)
                        .padding(.bottom, -50)
                        .padding(.top,-25)
                }
            }.onAppear{
                target = currentGame?.target ?? 1000
            }
            .toolbar { topToolbar }
            .toolbar{bottomToolbar}
            .safeAreaInset(edge: .top)    { scoreHeader }
            .navigationTitle(String(localized:"general.editGame"))
            .toolbarTitleDisplayMode(.inline)
            .alert(String(localized:"gameSummary.alert.delete.title"), isPresented: $showDeleteGameAlert) {
                Button(String(localized:"general.alert.cancel"), role: .cancel) {
                    showDeleteGameAlert = false
                }
                Button(String(localized:"general.delete"), role: .destructive) {
                   
                    Task {
                        showEditRoundsSheet = false
                            await network.deleteGame(gameId: currentGameId)
                            
                        
                        }
                    }
                
            } message: {
                Text(String(localized:"gameSummary.alert.delete.description"))
            }
            .alert(String(localized:"editRound.alert.finishGame.title"), isPresented: $showFinishGameAlert) {
                Button(String(localized:"general.alert.cancel"), role: .cancel) {
                    showDeleteGameAlert = false
                }
                Button(String(localized:"editRound.alert.finishGame.confirm"), role: .confirm) {
                    Task{
                        tie = true
                        showEditRoundsSheet = false
                        await network.reCalculate(gameId: currentGameId, tie: tie)
                    }
                    
                }
               
                
                    
            } message: {
                Text(String(localized:"editRound.alert.finishGame.message"))
            }
                
        }
        
    
    }

    // MARK: - Score Header
    private var scoreHeader: some View {
        
        VStack{
            Picker(String(localized: "gamesummary.picker.view"), selection: $selectedTab) {
                Text(String(localized: "gamesummary.tab.graph")).tag(0)
                Text(String(localized: "gamesummary.tab.list")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            HStack {
                
                Text(String(format:String(localized:"general.team.result"),String(1), String(currentPointsTeam1))).foregroundStyle(Color.accentColor)
                Spacer()
                Text(String(format:String(localized:"general.team.result"),String(2), String(currentPointsTeam2)))
            }
            .fontWeight(.bold)
            .font(.title2)
            .padding(.horizontal, 30)
            .padding(.top,5)
        }
    }

    // MARK: - Delete Game Button
    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        
        ToolbarItem(placement: .bottomBar){
            Button {
                showFinishGameAlert = true
                
            } label: {
                Image(systemName: "flag.pattern.checkered")
            }
            .foregroundColor(.primary)
        }
        ToolbarSpacer(placement:.bottomBar)
        ToolbarItem(placement: .bottomBar){
            Menu {
                    Picker(String(localized: "play.target"), selection: $target) {
                        Text("250").tag(250)
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                        Text("2000").tag(2000)
                        Text("10000").tag(10000)
                    }.onChange(of:target){
                        Task{
                            await network.updateGameTarget(gameId: currentGameId, target: target)
                        }
                    }
                
                
            } label: {
                Text(String(localized:"editRound.changeTarget"))
            }
            .foregroundColor(.primary)
        }
        ToolbarSpacer(placement:.bottomBar)
        ToolbarItem(placement: .bottomBar) {
                Button {
                    showDeleteGameAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundColor(.primary)
                
            }
       
    }

    // MARK: - Toolbars
    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark") {
                showEditRoundsSheet = false
            }
        }
    }
}


struct EditRoundsGraphView: View {
    var body: some View{
        
    }
}


struct EditRoundsListView: View {
    @ObservedObject var network: NetworkService
    var currentGameId: Int
    var allRounds: [Round]
    
   
    
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
                if allRounds.count > 0 {
                    GameSummaryListView(
                        showGameSummarySheetView: .constant(true),
                                                    currentGameId: currentGameId,
                                                    profiles: network.profiles,
                                                    network: network,
                                                    allowEditing: .constant(true),
                        winnerName: "Unknown"
                    )
                } else {
                    ContentUnavailableView(
                        String(localized: "rounds.noPlayedYet"),
                        systemImage: "list.bullet"
                    )
                       
                }
            
        }
    }
}

