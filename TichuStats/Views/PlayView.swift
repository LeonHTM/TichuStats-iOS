//
//  PlayView.swift
//  TichuStats
//
//  Created by Leon on 21.04.2026.
//

import SwiftUI

struct PlayView: View {
    @Namespace private var playSpace
    // MARK: - Storage
    @AppStorage("userId") var userId: Int = -69420
    @AppStorage("userImageData") var userImageData: Data?
    @AppStorage("userName") var userName: String = "Storage - Unknown"
    @AppStorage("userElo") var userElo: Double = 404
    @AppStorage("isLoading") var isLoading: Bool = false
    @AppStorage("defaultAllowPingus") private var defaultAllowPingus: Bool = true
    @AppStorage("defaultTarget") private var defaultTarget: Int = 1000

    @StateObject private var socket = SocketService.shared
    @ObservedObject private var network = NetworkService.shared

    // MARK: - State
    @State private var showAddPlayersSheet2: Bool = false
    @State private var showAddPlayersSheet3: Bool = false
    @State private var showAddPlayersSheet4: Bool = false
    @State private var showEditRoundsSheet: Bool = false
    @State private var showAddRoundSheet: Bool = false
    @State private var showDebugSheetView: Bool = false
    @State private var showGameOverSheet: Bool = false
    @State private var showOfflineAlert: Bool = false
    @State private var showName2Alert: Bool = false
    @State private var showName3Alert: Bool = false
    @State private var showName4Alert: Bool = false
    @State private var selectedTab: Int = 1
    @State private var showPlayers: Bool = true
    @State private var showFriends: Bool = true
    @State private var revanche: Bool = false
    
    @State private var player1Id: Int?
    @State private var player2Id: Int?
    @State private var player3Id: Int?
    @State private var player4Id: Int?
    
    @State private var guest2Name: String = String(localized:"play.guest")
    @State private var guest3Name: String = String(localized:"play.guest")
    @State private var guest4Name: String = String(localized:"play.guest")

    @State private var target: Int = 1000
    @State private var allowPingusState: Bool = true
    @AppStorage("tie") private var tie: Bool = false

    @FocusState private var targetFieldFocused: Bool

    // MARK: - Computed
    @State private var guestImages = ["dog", "phoenix", "dragon", "mahjong"].shuffled()
    
    private var currentGame: Game? {
        guard let id = network.currentGameId else { return nil }
        return network.games.first { $0.id == id }
    }
    
    private var player1: Profile? {
        network.profiles.first { $0.id == userId }
    }

    private func profile(for id: Int?) -> Profile? {
        guard let id else { return nil }
        return network.profiles.first { $0.id == id }
    }

    private var isGameReady: Bool {
        player1 != nil && player2Id != nil && player3Id != nil && player4Id != nil
    }

    private var gameDone: Bool {
        
        guard let game = currentGame else { return false }
        if tie || game.winner == 3 { return true }
        if game.currentPointsTeam1 >= game.target && game.currentPointsTeam1 > game.currentPointsTeam2 { return true }
        if game.currentPointsTeam2 >= game.target && game.currentPointsTeam2 > game.currentPointsTeam1 { return true }
        return false
    }

    private var isRated: Bool {
        let ids = [userId, player2Id, player3Id, player4Id].compactMap { $0 }
        guard ids.count == 4 else { return false }
        return ids.allSatisfy { id in
            network.profiles.first { $0.id == id }?.elo != nil &&
            id != -4 && id != -3 && id != -2 && id != -1
        }
    }
    
    private var currentPointsTeam1: Int { currentGame?.currentPointsTeam1 ?? -69420 }
    private var currentPointsTeam2: Int { currentGame?.currentPointsTeam2 ?? -69420 }

    // MARK: - Methods

    private func startGame() {
        if network.currentGameId == nil {
            Task {
                let game = await network.addGame(
                    target: target,
                    allowPingus: allowPingusState,
                    team1Player1Id: userId,
                    team1Player2Id: player2Id,
                    team2Player1Id: player3Id,
                    team2Player2Id: player4Id,
                    guest2Name: guest2Name,
                    guest3Name: guest3Name,
                    guest4Name: guest4Name
                )
                print("Curent Game setting ID: \(game?.id ?? -1)")
                network.currentGameId = game?.id
            }
        }
    }

    private func resetGame() {
        withAnimation(.easeInOut) {
            tie = false
            network.currentGameId = nil
            player2Id = nil
            player3Id = nil
            player4Id = nil
            target = 1000
            guest2Name = String(localized:"play.guest")
            guest3Name = String(localized:"play.guest")
            guest4Name = String(localized:"play.guest")
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            NavigationStack {
                GeometryReader{ geo in
                List {
                    team1Header
                    team1Players.disabled(isLoading)
                    centerSpacer(availableHeight: geo.size.height)
                    team2Header
                    team2Players.disabled(isLoading)
                }
                .animation(.easeInOut, value: isLoading)
                .scrollEdgeEffectStyle(.soft, for: .all)
                .onAppear {
                    allowPingusState = defaultAllowPingus
                    target = defaultTarget
                }
                .refreshable {
                    await network.fetch(load:false)
                }
                .onChange(of:gameDone){
                                    // Editable only while nobody has finished the game yet
                                    network.finishGameEditing = !(currentGame?.calculated ?? false)
                                }
                .onChange(of: network.games) {
                    let openGames = network.games.filter { $0.winner == nil }
                    if openGames.count == 1 {
                        withAnimation(.easeInOut) {
                            showAddPlayersSheet2 = false
                            showAddPlayersSheet3 = false
                            showAddPlayersSheet4 = false
                            network.currentGameId = openGames.first?.id
                            player1Id = openGames.first?.team1Player1Id
                            player2Id = openGames.first?.team1Player2Id
                            player3Id = openGames.first?.team2Player1Id
                            player4Id = openGames.first?.team2Player2Id
                            guest2Name = openGames.first?.guest2Name ?? String(localized:"play.guest")
                            guest3Name = openGames.first?.guest3Name ?? String(localized:"play.guest")
                            guest4Name = openGames.first?.guest4Name ?? String(localized:"play.guest")
                            Task {
                                if let id = network.currentGameId {
                                    await network.fetchGameRounds(gameId: id)
                                }
                            }
                        }
                    }
                }
                
                .onChange(of: isLoading) {
                    let openGames = network.games.filter { $0.winner == nil }
                    if openGames.count == 1 {
                        withAnimation(.easeInOut) {
                            network.currentGameId = openGames.first?.id
                            player1Id = openGames.first?.team1Player1Id
                            player2Id = openGames.first?.team1Player2Id
                            player3Id = openGames.first?.team2Player1Id
                            player4Id = openGames.first?.team2Player2Id
                            guest2Name = openGames.first?.guest2Name ?? String(localized:"play.guest")
                            guest3Name = openGames.first?.guest3Name ?? String(localized:"play.guest")
                            guest4Name = openGames.first?.guest4Name ?? String(localized:"play.guest")
                            Task {
                                if let id = network.currentGameId {
                                    await network.fetchGameRounds(gameId: id)
                                }
                            }
                        }
                    }
                }
                .onChange(of: isGameReady) {
                    if isGameReady {
                        startGame()
                    }
                }
                .onChange(of: network.isOnline) {
                    if !network.isOnline {
                        //Sheet should not show Friend and Player
                        showFriends = false
                        showPlayers = false
                        
                        showAddRoundSheet = false
                        showEditRoundsSheet = false
                        
                        showAddPlayersSheet2 = false
                        showAddPlayersSheet3 = false
                        showAddPlayersSheet4 = false
                        
                    } else {
                        showFriends = true
                        showPlayers = true
                    }
                }
                .onChange(of: network.games.map(\.id)) {
                    guard let id = network.currentGameId else { return }
                    
                    if network.games.first(where: { $0.id == id }) == nil {
                        showEditRoundsSheet = false
                        resetGame()
                    }
                }
                .onChange(of: gameDone) {
                    if gameDone {

                        showAddRoundSheet = false
                        showEditRoundsSheet = false
                        
                            if gameDone {
                                showGameOverSheet = true
                            }
                        
                    } else {
                        showGameOverSheet = false
                    }
                }
                .sheet(isPresented: $showGameOverSheet, onDismiss: {
                    print("sheet wird geschlossen")
                    print("gamedone: \(gameDone)")
                    print("tie_ \(tie)")
                    
                    guard gameDone else { return }
                    showEditRoundsSheet = false
                    
                    let gameId = currentGame?.id ?? 0
                    let game = currentGame
                    
                    Task {
                        // finish first, wait for it, then create revanche
                        await network.finishGame(gameId: gameId,tie:tie)
                        
                        if revanche, let game = game {
                            let p1 = game.team1Player1Id
                            let p2 = game.team1Player2Id
                            let p3 = game.team2Player1Id
                            let p4 = game.team2Player2Id
                            let g2 = game.guest2Name ?? String(localized:"play.guest")
                            let g3 = game.guest3Name ?? String(localized:"play.guest")
                            let g4 = game.guest4Name ?? String(localized:"play.guest")
                            let newGame = await network.addGame(
                                target: game.target,
                                allowPingus: game.allowPingus,
                                team1Player1Id: p1,
                                team1Player2Id: p2,
                                team2Player1Id: p3,
                                team2Player2Id: p4,
                                guest2Name: g2,
                                guest3Name: g3,
                                guest4Name: g4
                            )
                            await MainActor.run {
                                network.currentGameId = newGame?.id
                                player1Id = p1
                                player2Id = p2
                                player3Id = p3
                                player4Id = p4
                                guest2Name = g2
                                guest3Name = g3
                                guest4Name = g4
                                revanche = false
                            }
                            tie = false
                        } else if !revanche {
                            await MainActor.run { resetGame() }
                        }
                    }
                }) {
                    GameSummarySheetView(
                        showGameOverViewSheetView: $showGameOverSheet,
                        currentGameId: network.currentGameId,
                        revanche: $revanche,
                        isLoading:.constant(false),
                        tie: tie,
                        profiles: network.profiles,
                        network: network,
                        selectedTab:$selectedTab,
                        showRevancheButton: true,
                        allowEditing: $network.finishGameEditing
                    )
                    .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
                    
                }
                .scrollContentBackground(.hidden)
                .background(alignment: .center) {
                    vsBackground
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .listSectionSpacing(0)
                .navigationTitle(String(localized: "general.title.play"))
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {
                    if network.profiles.first(where: { $0.id == userId })?.isAdmin == true{
                        ToolbarItem {
                            Button { showDebugSheetView = true } label: {
                                Image(systemName: "ant").foregroundStyle(socket.connected && network.apiURL == getURL() ? Color.green : network.apiURL == getURL(dev:true) && socket.connected ? Color.orange : Color.red)
                            }
                        }
                    }
                    if #available(anyAppleOS 27.1, *) {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationProfileImage()
                        }
                        .axisBehavior(.horizontalOnly)
                        .sharedBackgroundVisibility(.hidden)
                            
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationProfileImage()
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { targetFieldFocused = false }
                    }
                }
            }
            }
        }
        .sheet(isPresented: $showDebugSheetView) {
            DebugSheetView(
                currentGame: Binding(
                    get: { currentGame ?? Game(favorite: false,id: 0, date: Date(), target: 1000, allowPingus: true, currentPointsTeam1: 0, currentPointsTeam2: 0) },
                    set: { network.currentGameId = $0.id }
                ),
                showDebugSheetView: $showDebugSheetView
            )
        }
        .safeAreaInset(edge: .bottom) {
            if !isLoading{
                if isGameReady {
                    gameReadyBottomBar
                } else {
                    if network.isOnline{
                        gameSettingsBottomBar
                    }
                }
            }
        }
    }

    // MARK: - Team 1 Header
    private var team1Header: some View {
        Section {
            HStack {
                Text(String(format: String(localized: "general.team"), String(1)))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
                    .redactedShimmer()
                Spacer()
                if isGameReady || isLoading {
                    Text(isLoading ? "394" : "\(currentPointsTeam1)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .redactedShimmer()
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Team 1 Players
    private var team1Players: some View {
        Section {
            HStack {
                if let p1Id = player1Id,
                   network.currentGameId != nil,
                   let p1 = profile(for: p1Id) {
                    
                    HStack {
                        if p1.id == -3 || p1.id == -2 || p1.id == -1 || p1.id == -4{
                            Image(guestImages[0])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        }else{
                            ProfileImage(data: network.profileImages[p1Id], size: 44)
                        }
                        
                        if p1.id == -3 || p1.id == -2 || p1.id == -1 || p1.id == -4{
                            Text(String(format: String(localized: "play.guest"),String(1))).fontWeight(.bold).foregroundStyle(Color.accentColor)
                        }else{
                            Text(p1.name ?? String(localized: "general.unknown")).fontWeight(.bold).foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        if let elo = p1.elo {
                            Text("\(String(localized: "general.rating")): \(Int(elo))").foregroundStyle(.secondary).font(.system(size: 16))
                        } else {
                            Text(String(localized:"play.download")).foregroundStyle(.secondary).font(.system(size: 16))
                        }
                    }.contextMenu{
                        if network.isOnline && p1.id != userId && p1.id > 0{
                            if isFriend(profileId: p1.id) == true{
                                Button(role:.destructive){
                                  
                                        Task{
                                        
                                            await network.removeFriend(profileId: userId, friendId: p1.id)
                                        }
                                    
                                }label:{
                                    Image(systemName:"person.badge.minus")
                                    Text(String(localized: "friends.remove.friend"))
                                }
                            }else{
                                Button{
                                    Task{
                                        await network.sendFriendRequest(senderId: userId, receiverId: p1.id)
                                    }
                                }label:{
                                    Image(systemName:"person.badge.plus")
                                    Text(String(localized: "play.sendFriend"))
                                }.disabled(p1.id == userId)
                            }
                        }else if network.isOnline && p1.id != userId && p1.id < 0{
                            Button{
                                
                            }label:{
                                Image(systemName:"pencil")
                                Text(String(localized:"play.editGuestName"))
                                Text(String(format: String(localized: "play.guest"),String(1)))
                                    
                                
                            }
                        }
                        
                    }.swipeActions(edge: .trailing) {
                        if isGameReady == false{
                            Button() {
                                 
                                     Task{
                                       
                                         //await network.editGamePlayer(gameId: currentGame?.id ?? 0, playerSlot: 1)
                                         player1Id = nil
                                         
                                     
                                     
                                 }
                             } label: {
                                 Label(String(localized: "play.removePlayer"), systemImage: "person.badge.minus").tint(.red)
                             }
                        }
                    }
                } else if isLoading{
                    withAnimation(.easeInOut){
                        HStack {
                            ProfileImage(data: nil, size: 44)
                            Text(String(localized: "general.unknown")).fontWeight(.bold).foregroundStyle(Color.accentColor).redactedShimmer()
                            Spacer()
                            Text("\(String(localized: "general.rating")): 1000").foregroundStyle(.secondary).font(.system(size: 16)).redactedShimmer()
                        }
                    }
                    
                    
                } else {
                    ProfileImage(data: userImageData, size: 44)
                    VStack(alignment: .leading) {
                        Text(player1?.name ?? userName)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    if let ranking = player1?.elo {
                        Text("\(String(localized: "general.rating")): \(Int(ranking))")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                    } else {
                        Text("\(String(localized: "general.rating")): 1000")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                    }
                }
            }

            if let p2Id = player2Id, let p2 = profile(for: p2Id) {
                withAnimation(.easeInOut){
                    HStack {
                        if p2.id == -3 || p2.id == -2 || p2.id == -1 || p2.id == -4{
                            Image(guestImages[1])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        }else{
                            ProfileImage(data: network.profileImages[p2Id], size: 44)
                        }
                        
                        if p2.id == -3 || p2.id == -2 || p2.id == -1 || p2.id == -4{
                            Text(guest2Name).fontWeight(.bold).foregroundStyle(Color.accentColor)
                        }else{
                            Text(p2.name ?? String(localized: "general.unknown")).fontWeight(.bold).foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        if let elo = p2.elo {
                            Text("\(String(localized: "general.rating")): \(Int(elo))").foregroundStyle(.secondary).font(.system(size: 16))
                        } else {
                            Text(String(localized:"play.download")).foregroundStyle(.secondary).font(.system(size: 16))
                        }
                    }.contextMenu{
                        if network.isOnline && p2.id != userId && p2.id > 0{
                            if isFriend(profileId: p2.id) == true{
                                Button(role:.destructive){
                                  
                                        Task{
                                        
                                            await network.removeFriend(profileId: userId, friendId: p2.id)
                                        }
                                    
                                }label:{
                                    Image(systemName:"person.badge.minus")
                                    Text(String(localized: "friends.remove.friend"))
                                }
                            }else{
                                Button{
                                    Task{
                                        await network.sendFriendRequest(senderId: userId, receiverId: p2.id)
                                    }
                                }label:{
                                    Image(systemName:"person.badge.plus")
                                    Text(String(localized: "play.sendFriend"))
                                }.disabled(p2.id == userId)
                            }
                        }else if network.isOnline && p2.id != userId && p2.id < 0{
                            Button{
                                showName2Alert = true
                            }label:{
                                Image(systemName:"pencil")
                                Text(String(localized:"play.editGuestName"))
                                Text(guest2Name)
                                    
                                
                            }
                        }
                        
                    }
                    .swipeActions(edge: .trailing) {
                        if isGameReady == false{
                            Button() {
                                 
                                     Task{
                                       
                                         //await network.editGamePlayer(gameId: currentGame?.id ?? 0, playerSlot: 2)
                                         player2Id = nil
                                         
                                     
                                     
                                 }
                             } label: {
                                 Label(String(localized:"play.removePlayer"), systemImage: "person.badge.minus").tint(.red)
                             }
                        }
                    }
                    .alert(String(format:String(localized:"play.alert.enterName")), isPresented: $showName2Alert) {
                        TextField(String(localized:"play.guestName"), text: $guest2Name)
                        Button(String(localized: "general.alert.save"),role:.confirm) {
                            Task{
                                
                                if let id = currentGame?.id{
                                    await network.updateGameGuestName(gameId: id, guestId: -2, guestName: guest2Name)
                                }
                            }
                        }

                        Button(String(localized:"general.alert.cancel"), role: .cancel) {
                            showName2Alert = false
                        }
                    }

                }
            } else if isLoading{
                withAnimation(.easeInOut){
                    HStack {
                        ProfileImage(data: nil, size: 44)
                        Text(String(localized: "general.unknown")).fontWeight(.bold).foregroundStyle(Color.accentColor).redactedShimmer()
                        Spacer()
                        Text("\(String(localized: "general.rating")): 1000").foregroundStyle(.secondary).font(.system(size: 16)).redactedShimmer()
                    }
                }
                
                
            }else {
                withAnimation(.easeInOut){
                    addPlayerRow(label: String(localized: "play.addPlayer"), action: { showAddPlayersSheet2 = true })
                        .sheet(isPresented: $showAddPlayersSheet2) {
                            AddPlayersSheetView(
                                showAddPlayersSheet: $showAddPlayersSheet2,
                                addPlayerId: $player2Id,
                                alreadyAdded: [player3Id, player4Id].compactMap { $0 },
                                showGuest: .constant(true),
                                showPlayers: $showPlayers,
                                showFriends: $showFriends,
                                guestName: $guest2Name,
                                guestIndex: 2,
                                showMenu: true
                                
                            )
                            .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
                        }
                        .contextMenu{
                            if network.isOnline{
                                Button{
                                    showAddPlayersSheet2 = true
                                }label:{
                                    Image(systemName: "arrow.up.right.square")
                                    Text(String(localized: "play.addPlayer"))
                                }
                            }
                        }preview:{
                            AddPlayersSheetView(
                                showAddPlayersSheet: $showAddPlayersSheet4,
                                addPlayerId: $player4Id,
                                alreadyAdded: [player2Id, player3Id].compactMap { $0 },
                                showGuest: .constant(true),
                                showPlayers: $showPlayers,
                                showFriends: $showFriends,
                                guestName: $guest2Name,
                                guestIndex: 2,
                                showMenu: false
                                
                            
                            )
                        }
                }
            }
        }
    }

    // MARK: - Center Spacer
    private func centerSpacer(availableHeight: CGFloat) -> some View {
        let fixedContentHeight: CGFloat = 65 + 50 + 120 + 50 + 120 + 80
        let dynamicHeight = max(availableHeight - fixedContentHeight, 140)

        return Section {
            Color.clear
                .frame(height: dynamicHeight)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Team 2 Header
    private var team2Header: some View {
        Section {
            HStack {
                Text(String(format: String(localized: "general.team"), String(2)))
                    .redactedShimmer()
                Spacer()
                if isGameReady || isLoading {
                    Text(isLoading ? "394" : "\(currentPointsTeam2)")
                        .redactedShimmer()
                }
            }
        }
        .font(.title2)
        .fontWeight(.bold)
        .listRowBackground(Color.clear)
    }

    // MARK: - Team 2 Players
    private var team2Players: some View {
        Section {
            if let p3Id = player3Id, let p3 = profile(for: p3Id) {
                withAnimation(.easeInOut){
                    HStack {
                        if p3.id == -3 || p3.id == -2 || p3.id == -1 || p3.id == -4{
                            Image(guestImages[2])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        }else{
                            ProfileImage(data: network.profileImages[p3Id], size: 44)
                        }
                        
                        if p3.id == -3 || p3.id == -2 || p3.id == -1 || p3.id == -4{
                            Text(guest3Name).fontWeight(.bold).foregroundStyle(Color.accentColor)
                        }else{
                            Text(p3.name ?? String(localized: "general.unknown")).fontWeight(.bold)
                        }
                        Spacer()
                        if let elo = p3.elo {
                            Text("\(String(localized: "general.rating")): \(Int(elo))").foregroundStyle(.secondary).font(.system(size: 16))
                        } else {
                            Text(String(localized:"play.download")).foregroundStyle(.secondary).font(.system(size: 16))
                        }
                    }.contextMenu{
                        if network.isOnline && p3.id != userId && p3.id > 0{
                            if isFriend(profileId: p3.id) == true{
                                Button(role:.destructive){
                                  
                                        Task{
                                        
                                            await network.removeFriend(profileId: userId, friendId: p3.id)
                                        }
                                    
                                }label:{
                                    Image(systemName:"person.badge.minus")
                                    Text(String(localized: "friends.remove.friend"))
                                }
                            }else{
                                Button{
                                    Task{
                                        await network.sendFriendRequest(senderId: userId, receiverId: p3.id)
                                    }
                                }label:{
                                    Image(systemName:"person.badge.plus")
                                    Text(String(localized:"play.sendFriend"))
                                }.disabled(p3.id == userId)
                            }
                        }else if network.isOnline && p3.id != userId && p3.id < 0{
                            Button{
                                showName3Alert = true
                            }label:{
                                Image(systemName:"pencil")
                                Text(String(localized:"play.editGuestName"))
                                Text(guest3Name)
                                    
                                
                            }
                        }
                        
                    }.swipeActions(edge: .trailing) {
                        if isGameReady == false{
                            Button() {
                                 
                                     Task{
                                       
                                         //await network.editGamePlayer(gameId: currentGame?.id ?? 0, playerSlot: 3)
                                         player3Id = nil
                                         
                                     
                                     
                                 }
                             } label: {
                                 Label(String(localized:"play.removePlayer"), systemImage: "person.badge.minus").tint(.red)
                             }
                        }
                    }
                    .alert(String(format:String(localized:"play.alert.enterName")), isPresented: $showName3Alert) {
                        TextField(String(localized:"play.guestName"), text: $guest3Name)
                        Button(String(localized: "general.alert.save"),role:.confirm) {
                            Task{
                                
                                if let id = currentGame?.id{
                                    await network.updateGameGuestName(gameId: id, guestId: -3, guestName: guest3Name)
                                }
                            }
                        }

                        Button(String(localized:"general.alert.cancel"), role: .cancel) {
                            showName3Alert = false
                        }
                    }

                }
            } else if isLoading{
                withAnimation(.easeInOut){
                    HStack {
                        ProfileImage(data: nil, size: 44)
                        Text(String(localized: "general.unknown")).fontWeight(.bold).redactedShimmer()
                        Spacer()
                        Text("\(String(localized: "general.rating")): 1000").foregroundStyle(.secondary).font(.system(size: 16)).redactedShimmer()
                    }
                    
                }
            }else {
                withAnimation(.easeInOut){
                    addPlayerRow(label: String(localized: "play.addPlayer"), action: { showAddPlayersSheet3 = true })
                        .sheet(isPresented: $showAddPlayersSheet3) {
                            AddPlayersSheetView(
                                showAddPlayersSheet: $showAddPlayersSheet3,
                                addPlayerId: $player3Id,
                                alreadyAdded: [player2Id, player4Id].compactMap { $0 },
                                showGuest: .constant(true),
                                showPlayers: $showPlayers,
                                showFriends: $showFriends,
                                guestName: $guest3Name,
                                guestIndex: 3,
                                showMenu: true,
                                
                            )
                            .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
                        }.contextMenu{
                            if network.isOnline{
                                Button{
                                    showAddPlayersSheet3 = true
                                }label:{
                                    Image(systemName: "arrow.up.right.square")
                                    Text(String(localized: "play.addPlayer"))
                                }
                            }
                        }preview:{
                            AddPlayersSheetView(
                                showAddPlayersSheet: $showAddPlayersSheet4,
                                addPlayerId: $player4Id,
                                alreadyAdded: [player2Id, player3Id].compactMap { $0 },
                                showGuest: .constant(true),
                                showPlayers: $showPlayers,
                                showFriends: $showFriends,
                                guestName: $guest3Name,
                                guestIndex: 3,
                                showMenu: false,
                                
                            )
                        }
                }
            }

            if let p4Id = player4Id, let p4 = profile(for: p4Id) {
                withAnimation(.easeInOut){
                    HStack {
                        if p4.id == -3 || p4.id == -2 || p4.id == -1 || p4.id == -4{
                            Image(guestImages[3])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        }else{
                            ProfileImage(data: network.profileImages[p4Id], size: 44)
                        }
                        
                        if p4.id == -3 || p4.id == -2 || p4.id == -1 || p4.id == -4{
                            Text(guest4Name).fontWeight(.bold).foregroundStyle(Color.accentColor)
                        }else{
                            Text(p4.name ?? String(localized: "general.unknown")).fontWeight(.bold)
                        }
                        Spacer()
                        if let elo = p4.elo {
                            Text("\(String(localized: "general.rating")): \(Int(elo))").foregroundStyle(.secondary).font(.system(size: 16))
                        } else {
                            Text(String(localized:"play.download")).foregroundStyle(.secondary).font(.system(size: 16))
                        }
                    }.contextMenu{
                        if network.isOnline && p4.id != userId && p4.id > 0{
                            if isFriend(profileId: p4.id) == true{
                                Button(role:.destructive){
                                  
                                        Task{
                                        
                                            await network.removeFriend(profileId: userId, friendId: p4.id)
                                        }
                                    
                                }label:{
                                    Image(systemName:"person.badge.minus")
                                    Text(String(localized: "friends.remove.friend"))
                                }
                            }else{
                                Button{
                                    Task{
                                        await network.sendFriendRequest(senderId: userId, receiverId: p4.id)
                                    }
                                }label:{
                                    Image(systemName:"person.badge.plus")
                                    Text(String(localized:"play.sendFriend"))
                                }.disabled(p4.id == userId)
                            }
                        }else if network.isOnline && p4.id != userId && p4.id < 0{
                            Button{
                                showName4Alert = true
                            }label:{
                                Image(systemName:"pencil")
                                Text(String(localized:"play.editGuestName"))
                                Text(guest4Name)
                                    
                                
                            }
                        }
                        
                        
                    }.swipeActions(edge: .trailing) {
                        if isGameReady == false{
                            Button() {
                                 
                                     Task{
                                       
                                         //await network.editGamePlayer(gameId: currentGame?.id ?? 0, playerSlot: 4)
                                         player4Id = nil
                                         
                                     
                                     
                                 }
                             } label: {
                                 Label(String(localized:"play.removePlayer"), systemImage: "person.badge.minus").tint(.red)
                             }
                        }
                    }
                    .alert(String(format:String(localized:"play.alert.enterName")), isPresented: $showName4Alert) {
                        TextField(String(localized:"play.guestName"), text: $guest4Name)
                        Button(String(localized: "general.alert.save"),role:.confirm) {
                            Task{
                                
                                if let id = currentGame?.id{
                                    await network.updateGameGuestName(gameId: id, guestId: -4, guestName: guest4Name)
                                }
                            }
                        }

                        Button(String(localized:"general.alert.cancel"), role: .cancel) {
                            showName4Alert = false
                        }
                    }

                }
                
            } else if isLoading{
                withAnimation(.easeInOut){
                    HStack {
                        ProfileImage(data: nil, size: 44)
                        Text(String(localized: "general.unknown")).fontWeight(.bold).redactedShimmer()
                        Spacer()
                        Text("\(String(localized: "general.rating")): 1000").foregroundStyle(.secondary).font(.system(size: 16)).redactedShimmer()
                    }
                }
                
            }else {
                withAnimation(.easeInOut){
                    addPlayerRow(label: String(localized: "play.addPlayer"), action: { showAddPlayersSheet4 = true })
                        .sheet(isPresented: $showAddPlayersSheet4) {
                            AddPlayersSheetView(
                                showAddPlayersSheet: $showAddPlayersSheet4,
                                addPlayerId: $player4Id,
                                alreadyAdded: [player2Id, player3Id].compactMap { $0 },
                                showGuest: .constant(true),
                                showPlayers: $showPlayers,
                                showFriends: $showFriends,
                                guestName: $guest4Name,
                                guestIndex: 4,
                                showMenu: true,
                                
                            )
                            .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
                        }
                        .contextMenu{
                            if network.isOnline{
                                Button{
                                    showAddPlayersSheet4 = true
                                }label:{
                                    Image(systemName: "arrow.up.right.square")
                                    Text(String(localized: "play.addPlayer"))
                                }
                            }
                        }preview:{
                            AddPlayersSheetView(
                                showAddPlayersSheet: $showAddPlayersSheet4,
                                addPlayerId: $player4Id,
                                alreadyAdded: [player2Id, player3Id].compactMap { $0 },
                                showGuest: .constant(true),
                                showPlayers: $showPlayers,
                                showFriends: $showFriends,
                                guestName: $guest4Name,
                                guestIndex: 4,
                                showMenu: false,
                                
                            )
                        }
                }
            }
        }
    }

    // MARK: - Add Player Row
    private func addPlayerRow(label: String, action: @escaping () -> Void) -> some View {
        ZStack{
            HStack {
                //To make List Lines Consistnt
                ProfileImage(data: nil, size: 44).opacity(0)
                Text("P").opacity(0)
                Spacer()
            }
            HStack{
                Spacer()
                if network.isOnline{
                    Image(systemName: "plus.circle.fill")
                    Button(label, action: action)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.vertical, 10.6)
                }else{
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.secondary)
                    Button{
                        showOfflineAlert = true
                    }label:{
                        Text("\(label)")
                    }
                        .foregroundColor(.secondary)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 10.6)
                        .alert(isPresented: $showOfflineAlert) {
                                            OfflineView.offlineAlert()
                                        }
                    
                    
                }
                Spacer()
            }
        }
    }

    // MARK: - VS Background
    private var vsBackground: some View {
        Group {
            
            if isLoading {
                VStack(spacing: 10) {
                    VStack {
                        Text(String(localized: "play.versus"))
                            .font(.system(size: 120, weight: .bold))
                        HStack {
                            Text(String(format:String(localized:"play.target"),"1000"))
                                .fontWeight(.bold)
                                .font(.title3)
                                .offset(y: -15)
                                .redactedShimmer()
                        }
                    }
                }
            }else if isLoading == false && network.isOnline {
                VStack {
                    Text(String(localized: "play.versus"))
                        .font(.system(size: 120, weight: .bold))
                    HStack {
                        if isGameReady {
                            /*Text(isRated ? "Rated" : "Unrated")
                                .fontWeight(.bold)
                                .font(.title3)
                                .offset(y: -15)*/
                        }
                        Text(isGameReady ? " \(String(localized: "play.target")): \(currentGame?.target ?? target)" : " \(String(localized: "play.target")): \(target)")
                            .fontWeight(.bold)
                            .font(.title3)
                            .offset(y: -15)

                    }
                }
                .transition(.opacity)
            } else if !network.isOnline {
                VStack(alignment: .center, spacing: 10) {
                    Text(String(localized:"offline.title"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text(String(localized:"offline.description"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
               
                
            
        }
        .foregroundStyle(Color.secondary)
        .allowsHitTesting(false)
        .animation(.easeInOut, value: isLoading)
        .animation(.easeInOut, value: network.isOnline)
    }

    // MARK: - Game Ready Bottom Bar
    private var gameReadyBottomBar: some View {
        GlassEffectContainer {
            HStack {
                if network.isOnline{
                    Button {
                    showEditRoundsSheet = true
                } label: {
                    Image(systemName: "list.bullet.clipboard")
                        .offset(y:-2)
                        .font(.system(size: 24))
                        .foregroundColor(.primary)
                        .frame(width: 29, height: 29)
                }.matchedTransitionSource(id: "69420", in: playSpace)
                    .padding(10)
                //.buttonStyle(.glass)
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: Circle())
                    .padding(.leading, 20)
                    .padding(.bottom, 10)
                    .sheet(isPresented: $showEditRoundsSheet) {
                        if let game = currentGame {
                            EditRoundsSheetView(
                                showEditRoundsSheet: $showEditRoundsSheet,
                                network: network,
                                currentGameId: game.id,
                                tie:$tie
                            )
                            .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large]).navigationTransition(.zoom(sourceID:"69420",in:playSpace))
                        }
                    }
                }else{
                    Button {
                    showOfflineAlert = true
                } label: {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .frame(width: 29, height: 29)
                        .clipShape(Circle())
                }
                    .padding(10)
                //.buttonStyle(.glass)
                    .glassEffect(.regular.interactive())
                    .padding(.leading, 20)
                    .padding(.bottom, 10)
                    .alert(isPresented: $showOfflineAlert) {
                                        OfflineView.offlineAlert()
                                    }
                }
                
                Spacer()
                if network.isOnline{
                    Button {
                    showAddRoundSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                    Text(String(localized:"play.addRound")).foregroundColor(.primary)
                }.matchedTransitionSource(id: "69421", in: playSpace)
                    .padding(13)
                    .glassEffect(.regular.interactive())
                    .padding(.trailing, 20)
                    .padding(.bottom, 10)
                
                    .sheet(isPresented: $showAddRoundSheet) {
                        if let game = currentGame {
                            AddRoundSheetView(
                                showAddRoundsSheet: $showAddRoundSheet,
                                currentGameId: game.id,
                                profiles: network.profiles,
                                network: network,
                                editMode: false,
                                roundIndex: nil,
                                editingRound: nil
                            ).navigationTransition(.zoom(sourceID:"69421",in:playSpace))
                        }
                    }
                }else{
                    Button {
                    showOfflineAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                    Text(String(localized:"play.addRound")).foregroundColor(.primary)
                }
                    .padding(13)
                    .glassEffect(.regular.interactive())
                    .padding(.trailing, 20)
                    .padding(.bottom, 10)
                    .alert(isPresented: $showOfflineAlert) {
                        OfflineView.offlineAlert()
                    }
                }
            }
        }
    }

    // MARK: - Game Settings Bottom Bar
    private var gameSettingsBottomBar: some View {
        HStack {
            Spacer()
            Menu {
                    Picker(String(localized: "play.target"), selection: $target) {
                        Text("250").tag(250)
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                        Text("2000").tag(2000)
                        Text("10000").tag(10000)
                    }
                
                if defaultAllowPingus == true{
                    Toggle(isOn: $allowPingusState) {
                        Text(String(localized:"play.allowPingus"))
                    }
                }
            } label: {
                Image(systemName: "gear").font(.system(size: 24))
            }
            .foregroundStyle(.primary)
            .padding(10)
            .glassEffect(.regular.interactive(), in: Circle())
            .padding(.trailing, 20)
            .padding(.bottom, 10)
        }
    }
}
