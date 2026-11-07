//
//  HistoryView.swift
//  TichuStats
//
//  Created by Leon on 08.05.2026
//
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct RowSnappingBehavior: ScrollTargetBehavior {
    let rowHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let y = target.rect.minY
        let snapped = (y / rowHeight).rounded() * rowHeight
        target.rect.origin.y = snapped
    }
}

// MARK: - Lazy share image

//Renders the share image only when the user actually shares
struct GameShareImage: Transferable {
    let makePNG: @MainActor () async -> Data?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let data = await item.makePNG() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    @Namespace private var historySpace

    private static let rowHeight: CGFloat = 75

    // MARK: - Storage
    @AppStorage("userId") var userId: Int = -69420
    @AppStorage("selectedTab") private var selectedTab = 1
    @AppStorage("isLoading") private var isLoading = false
    @Environment(\.colorScheme) var colorScheme

    @StateObject private var socket = SocketService.shared
    @ObservedObject private var network = NetworkService.shared

    // MARK: - Bindings
    @Binding var sheetGame: Game?
    @Binding var selectedGameId: Int?
    @Binding var scrolledGameId: Int?

    // MARK: - UI state
    @State private var showDebugSheetView = false
    @State private var sheetSelectedTab: Int = 1
    @State private var selectedCounter: Int = 0
    @State private var showOnlyFavorites = false
    @State private var dateUp = false
    @State private var isLoadingRound: Bool = false

    // MARK: - Cached derived state (rebuilt only when inputs change)
    @State private var gameHistory: [Game] = []
    @State private var hasFavorites = false
    @State private var profileLookup: [Int: Profile] = [:]
    @State private var gameDateById: [Int: Date] = [:]
    @State private var eloDateByGame: [Int: Date] = [:]

    init(sheetGame: Binding<Game?>,
         selectedGameId: Binding<Int?>,
         scrolledGameId: Binding<Int?>) {
        _sheetGame = sheetGame
        _selectedGameId = selectedGameId
        _scrolledGameId = scrolledGameId

        // Seed the caches so the first frame never flashes the empty state
        // or "Unknown" player names.
        let network = NetworkService.shared
        _gameHistory = State(initialValue: Self.makeHistory(from: network.games, favoritesOnly: false, dateUp: false))
        _hasFavorites = State(initialValue: network.games.contains { $0.winner != nil && $0.favorite })
        _profileLookup = State(initialValue: Self.makeLookup(network.profiles))
    }

    // MARK: - Pure helpers

    private static func makeHistory(from games: [Game], favoritesOnly: Bool, dateUp: Bool) -> [Game] {
        // Filter first (shrinks the array), then sort.
        var result = games.filter { $0.winner != nil && (!favoritesOnly || $0.favorite) }
        result.sort { dateUp ? $0.date < $1.date : $0.date > $1.date }
        return result
    }

    private static func makeLookup(_ profiles: [Profile]) -> [Int: Profile] {
        Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func placeholderGame(id: Int) -> Game {
        Game(favorite: false, id: id, date: Date(), target: 1000, allowPingus: true,
             currentPointsTeam1: 0, currentPointsTeam2: 0)
    }

    //Built once instead of on every body evaluation while loading.
    private static let skeletonGames: [Game] = (1...10).map { placeholderGame(id: $0) }

    // MARK: - Derived

    private var isAdmin: Bool { profileLookup[userId]?.isAdmin == true }

    private var markedDate: Date? {
        guard let id = selectedGameId else { return nil }
        return eloDateByGame[id] ?? gameDateById[id]
    }

    private var debugIndicatorColor: Color {
        if socket.connected && network.apiURL == getURL() { return .green }
        if socket.connected && network.apiURL == getURL(dev: true) { return .orange }
        return .red
    }

    // MARK: - Cache maintenance

    private func rebuildHistory(from games: [Game]? = nil) {
        // `$games` publishes in willSet, so callers from onReceive pass the new value in.
        let source = games ?? network.games

        let history = Self.makeHistory(from: source, favoritesOnly: showOnlyFavorites, dateUp: dateUp)
        gameHistory = history
        hasFavorites = source.contains { $0.winner != nil && $0.favorite }
        gameDateById = Dictionary(source.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first })

        if selectedGameId == nil || !history.contains(where: { $0.id == selectedGameId }) {
            select(history.first?.id)
        }
    }

    //Rounds are fetched only when a game is actually opened
    private func ensureRounds(for gameId: Int) {
        guard network.roundsByGame[gameId] == nil else { return }
        Task { await network.fetchGameRounds(gameId: gameId, isLoading: $isLoadingRound) }
    }

    private func openGame(_ game: Game) {
        sheetGame = game
        ensureRounds(for: game.id)
    }

    // MARK: - Body
    var body: some View {
        Group {
            if !gameHistory.isEmpty || isLoading {
                historyView
            } else {
                emptyStateView
            }
        }
        .sheet(isPresented: $showDebugSheetView) {
            DebugSheetView(
                currentGame: .constant(network.games.first ?? Self.placeholderGame(id: 0)),
                showDebugSheetView: $showDebugSheetView
            )
        }
        .onReceive(network.$games) { rebuildHistory(from: $0) }
        .onReceive(network.$profiles) { profileLookup = Self.makeLookup($0) }
        .onReceive(network.$eloHistory) { history in
            var dict: [Int: Date] = [:]
            for entry in history {
                let id: Int? = entry.gameId
                let date: Date? = entry.changedAt
                if let id, let date, dict[id] == nil { dict[id] = date }
            }
            eloDateByGame = dict
        }
    }

    // MARK: - History View
    private var historyView: some View {
        NavigationStack {
            GeometryReader { outerGeo in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        if isLoading {
                            ForEach(Self.skeletonGames, id: \.id) { game in
                                row(for: game)
                            }
                        } else {
                            ForEach(gameHistory, id: \.id) { game in
                                row(for: game)
                            }

                            Color.clear.containerRelativeFrame(.vertical) { length, _ in
                                max(0, length - Self.rowHeight)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollDisabled(isLoading)
                .animation(.easeInOut, value: isLoading)
                .scrollEdgeEffectStyle(.soft, for: .all)
                .scrollPosition(id: $scrolledGameId, anchor: .top)
                .scrollTargetBehavior(RowSnappingBehavior(rowHeight: Self.rowHeight))
                .background(Color(uiColor: .systemGroupedBackground))
                .refreshable {
                    // Awaited directly so the spinner reflects the real work.
                    await network.fetchGamesHistory(load: false)
                }
                .onChange(of: scrolledGameId) { _, newId in
                    guard let newId, selectedGameId != newId else { return }
                    selectedGameId = newId
                    selectedCounter += 1
                }
                // Haptics live in the parent, so rows don't need `selectedCounter`.
                .sensoryFeedback(.selection, trigger: selectedCounter)
                .safeAreaInset(edge: .top, spacing: 16) {
                    EloHistoryChartView(profileId: userId, markedDateId: isLoading ? nil : markedDate)
                        // Reads the geometry directly; no extra @State/onChange churn.
                        .frame(height: outerGeo.size.height / 2 - 125)
                        .padding(.vertical)
                        .glassEffect(
                            .regular.tint(
                                colorScheme == .dark
                                ? Color(uiColor: .tertiarySystemFill)
                                : .white
                            ).interactive(),
                            in: .rect(cornerRadius: 20)
                        )
                        .padding(.horizontal, 10)
                }
            }
            .sheet(item: $sheetGame, onDismiss: {
                sheetSelectedTab = 1
                isLoadingRound = false
            }) { game in
                GameSummarySheetView(
                    showGameOverViewSheetView: Binding(
                        get: { sheetGame != nil },
                        set: { if !$0 { sheetGame = nil } }
                    ),
                    currentGameId: game.id,
                    revanche: .constant(false),
                    isLoading: $isLoadingRound,
                    tie: false,
                    profiles: network.profiles,
                    network: network,
                    selectedTab: $sheetSelectedTab,
                    showRevancheButton: false,
                    allowEditing: .constant(false)
                )
                .navigationTransition(.zoom(sourceID: "\(game.id)", in: historySpace))
            }
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationTitle(String(localized: "general.title.history"))
            .toolbar { commonToolbar }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    // MARK: - Row factory

    private func row(for game: Game) -> some View {
        GameRow(
            game: game,
            isSelected: !isLoading && selectedGameId == game.id,
            userId: userId,
            profileLookup: profileLookup,
            profiles: network.profiles,
            network: network,
            historySpace: historySpace,
            colorScheme: colorScheme,
            isLoadingRound: $isLoadingRound,
            onOpen: openGame,
            onToggleFavorite: toggleFavorite
        )
        .equatable()
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .disabled(isLoading)
    }

    private func toggleFavorite(_ game: Game) {
        let newValue = !game.favorite
        Task { await network.updateGameFavorite(gameId: game.id, favorite: newValue) }
    }

    // MARK: - Toolbar (shared by both states)

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        if isAdmin {
            ToolbarItem {
                Button { showDebugSheetView = true } label: {
                    Image(systemName: "ant").foregroundStyle(debugIndicatorColor)
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

    // MARK: - Empty State View
    private var emptyStateView: some View {
        NavigationStack {
            VStack {
                Text(String(localized: "history.willAppear.title")).font(.title2).fontWeight(.bold)
                Text(String(localized: "history.willAppear.description"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    selectedTab = 0
                } label: {
                    Text(String(localized: "tichu.play"))
                }
                .padding(13)
                .glassEffect(.regular.tint(.accentColor).interactive())
                .foregroundStyle(.primary)
            }
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationTitle(String(localized: "general.title.history"))
            .toolbar { commonToolbar }
        }
    }

    private var bottomBar: some View {
        GlassEffectContainer {
            HStack {
                if (gameHistory.count > 1 || showOnlyFavorites) && !isLoading {
                    sortMenu
                }
                Spacer()
            }
        }
    }

    // MARK: - Selection / Sorting helpers

    private func select(_ id: Int?) {
        selectedGameId = id
        scrolledGameId = id
    }

    private func switchToFav() {
        guard !showOnlyFavorites else { return }
        withAnimation(.easeInOut) {
            showOnlyFavorites = true
            rebuildHistory()
            select(gameHistory.first?.id)
        }
    }

    private func switchToAll() {
        guard showOnlyFavorites else { return }
        withAnimation(.easeInOut) {
            showOnlyFavorites = false
            rebuildHistory()
            select(gameHistory.first?.id)
        }
    }

    /// Changes the date sort direction and selects the new first row.
    private func setSort(up: Bool) {
        guard dateUp != up else { return }
        dateUp = up
        rebuildHistory()

        // Deferred so the reordered list is laid out before the scroll position moves.
        Task { @MainActor in
            withAnimation(.easeInOut) {
                select(gameHistory.first?.id)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            if hasFavorites {
                Button {
                    switchToAll()
                } label: {
                    if !showOnlyFavorites { Image(systemName: "checkmark") } else { Image(systemName: "list.bullet") }
                    Text(String(localized: "history.sortBy.allRounds"))
                }
                Button {
                    switchToFav()
                } label: {
                    if showOnlyFavorites { Image(systemName: "checkmark") } else { Image(systemName: "star.fill") }
                    Text(String(localized: "history.sortBy.favorites"))
                }

                Divider()
            }
            Button {
                setSort(up: false)
            } label: {
                if !dateUp { Image(systemName: "checkmark") } else { Image("clock.down") }
                Text(String(localized: "history.sortBy.byDateDown"))
            }
            Button {
                setSort(up: true)
            } label: {
                if dateUp { Image(systemName: "checkmark") } else { Image("clock.up") }
                Text(String(localized: "history.sortBy.byDateUp"))
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 22))
                .foregroundColor(showOnlyFavorites || dateUp ? Color.accent : Color.primary)
        }
        .labelStyle(.titleAndIcon)
        .menuOrder(.fixed)
        .padding(10)
        .glassEffect(.regular.interactive(), in: Circle())
        .padding(.leading, 20)
        .padding(.bottom, 10)
    }
}

// MARK: - GameRow

/// Pure-ish row: no @ObservedObject, all display strings precomputed in `init`,
/// and `Equatable` so SwiftUI can skip re-rendering unchanged rows.
struct GameRow: View, Equatable {
    let game: Game
    let isSelected: Bool
    let colorScheme: ColorScheme
    let isLoadingRound: Binding<Bool>   // not part of equality

    // Precomputed display values
    private let dayText: String
    private let monthText: String
    private let scoreText: String
    private let team1Text: String
    private let team2Text: String
    private let isUserWinner: Bool

    // Dependencies that are *not* part of equality
    private let profiles: [Profile]
    private let network: NetworkService   // plain reference: no observation, no invalidation
    private let historySpace: Namespace.ID
    private let onOpen: (Game) -> Void
    private let onToggleFavorite: (Game) -> Void

    private static let isGerman = Locale.current.language.languageCode?.identifier == "de"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d")
        f.locale = Locale.current
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        f.locale = Locale.current
        return f
    }()

    init(game: Game,
         isSelected: Bool,
         userId: Int,
         profileLookup: [Int: Profile],
         profiles: [Profile],
         network: NetworkService,
         historySpace: Namespace.ID,
         colorScheme: ColorScheme,
         isLoadingRound: Binding<Bool>,
         onOpen: @escaping (Game) -> Void,
         onToggleFavorite: @escaping (Game) -> Void) {
        self.game = game
        self.isSelected = isSelected
        self.colorScheme = colorScheme
        self.isLoadingRound = isLoadingRound
        self.profiles = profiles
        self.network = network
        self.historySpace = historySpace
        self.onOpen = onOpen
        self.onToggleFavorite = onToggleFavorite

        // Date
        let day = Self.dayFormatter.string(from: game.date)
        let month = Self.monthFormatter.string(from: game.date)
        self.dayText = Self.isGerman ? "\(day)." : day
        self.monthText = Self.isGerman ? "\(month)." : month

        // Score
        self.scoreText = "\(game.currentPointsTeam1) : \(game.currentPointsTeam2)"

        // Names (dictionary lookup instead of 4× linear scans)
        let unknown = String(localized: "general.unknown")
        let guest = String(localized: "play.guest")
        func name(_ id: Int?) -> String {
            guard let id, let profile = profileLookup[id] else { return unknown }
            return profile.name ?? unknown
        }
        let p1 = name(game.team1Player1Id)
        let p2 = game.team1Player2Id == -2 ? (game.guest2Name ?? guest) : name(game.team1Player2Id)
        let p3 = game.team2Player1Id == -3 ? (game.guest3Name ?? guest) : name(game.team2Player1Id)
        let p4 = game.team2Player2Id == -4 ? (game.guest4Name ?? guest) : name(game.team2Player2Id)
        self.team1Text = "\(p1) & \(p2)"
        self.team2Text = "\(p3) & \(p4)"

        // Winner
        var team = 0
        if userId == game.team1Player1Id || userId == game.team1Player2Id {
            team = 1
        } else if userId == game.team2Player1Id || userId == game.team2Player2Id {
            team = 2
        }
        self.isUserWinner = team == game.winner
    }

    // Binding, closures and network are intentionally excluded.
    static func == (lhs: GameRow, rhs: GameRow) -> Bool {
        lhs.game.id == rhs.game.id
        && lhs.game.favorite == rhs.game.favorite
        && lhs.game.winner == rhs.game.winner
        && lhs.isSelected == rhs.isSelected
        && lhs.colorScheme == rhs.colorScheme
        && lhs.isUserWinner == rhs.isUserWinner
        && lhs.dayText == rhs.dayText
        && lhs.monthText == rhs.monthText
        && lhs.scoreText == rhs.scoreText
        && lhs.team1Text == rhs.team1Text
        && lhs.team2Text == rhs.team2Text
    }

    var body: some View {
        Button {
            onOpen(game)
        } label: {
            HStack(alignment: .center) {
                ZStack {
                    VStack {
                        Text(dayText)
                        Text(monthText)
                    }
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .padding(.trailing, 15)
                    .padding(.leading, 10)

                    if game.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .offset(x: -25)
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        if game.winner == 3 {
                            Image("trophy.slash.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                        } else if isUserWinner {
                            Image(systemName: "trophy.fill").font(.system(size: 15))
                        } else {
                            Image("trophy.slash.fill").font(.system(size: 15)).offset(x: -3)
                        }
                        Text(scoreText)
                            .font(.system(size: 20))
                            .fontWeight(.bold)
                    }
                    HStack(spacing: 3) {
                        Text(team1Text).foregroundStyle(Color.accent)
                        Text(":")
                        Text(team2Text)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 10)
            }
            .redactedShimmer()
            .padding(8)
            .padding(.vertical, 5)
            .background(
                colorScheme == .dark ? Color(uiColor: .tertiarySystemFill) : .white,
                in: .rect(cornerRadius: 24)
            )
            .foregroundColor(.primary)
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .matchedTransitionSource(id: "\(game.id)", in: historySpace)
        .contextMenu {
            Button {
                onOpen(game)
            } label: {
                Image(systemName: "arrow.up.right.square")
                Text(String(localized: "history.context.openGame"))
                Text(scoreText)
            }
            Button {
                onToggleFavorite(game)
            } label: {
                Text(game.favorite ? String(localized: "history.context.unfavorite") : String(localized: "history.context.favorite"))
                Image(systemName: game.favorite ? "star.slash.fill" : "star.fill")
            }
            .sensoryFeedback(.success, trigger: game.favorite)

            // Rendered lazily, only when the user actually taps Share.
            ShareLink(
                item: shareItem,
                message: Text(String(localized: "history.share.check")),
                preview: SharePreview("Tichu game")
            )
            .foregroundColor(.primary)
        } preview: {
            // No ImageRenderer work here any more; the preview just shows the summary.
            Group{
                if isLoadingRound.wrappedValue == true {
                    ProgressView()
                }else{
                    GameSummaryListView(
                        showGameSummarySheetView: .constant(true),
                        currentGameId: game.id,
                        profiles: profiles,
                        network: network,
                        allowEditing: .constant(false),
                        winnerName: "Unknown")
                }
            }
            .task {
                if network.roundsByGame[game.id] == nil {
                    await network.fetchGameRounds(gameId: game.id, isLoading: isLoadingRound)
                }
            }
        }
    }

    // MARK: - Share

    private var shareItem: GameShareImage {
        let gameId = game.id
        let profiles = profiles
        let network = network
        let scheme = colorScheme
        let loading = isLoadingRound
        return GameShareImage {
            await Self.renderShareImage(gameId: gameId,
                                        profiles: profiles,
                                        network: network,
                                        colorScheme: scheme,
                                        isLoadingRound: loading)
        }
    }

    @MainActor
    private static func renderShareImage(gameId: Int,
                                         profiles: [Profile],
                                         network: NetworkService,
                                         colorScheme: ColorScheme,
                                         isLoadingRound: Binding<Bool>) async -> Data? {
        // Rounds are only fetched on demand, so make sure they exist before rendering.
        if network.roundsByGame[gameId] == nil {
            await network.fetchGameRounds(gameId: gameId, isLoading: isLoadingRound)
        }

        let renderer = ImageRenderer(
            content: GameSummaryShareView(
                currentGameId: gameId,
                rounds: network.roundsByGame[gameId] ?? [],
                profiles: profiles,
                accentCo: .accent
            )
            .environment(\.colorScheme, colorScheme)
            .background(colorScheme == .dark ? Color.black : Color.white)
        )
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}

#Preview {
    HistoryView(sheetGame: .constant(nil), selectedGameId: .constant(nil), scrolledGameId: .constant(nil))
}
