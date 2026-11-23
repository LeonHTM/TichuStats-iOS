//
//  MainView.swift
//  TichuStats
//
//  Created by Leon on 21.04.2026.
//

import SwiftUI
import UserNotifications

struct MainView: View {
    @AppStorage("selectedTab") private var selectedTab = 0
    @AppStorage("userId") private var userId = -69420
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isFirstLogin-1") private var isFirstLogin: Bool = true
    
    @State private var isLoading: Bool = false
    @State private var fetchTrigger: Int = 0
    @State private var selectedGameId: Int? = nil
    @State private var scrolledGameId: Int? = nil
    @State private var sheetGame: Game? = nil
    @State private var showLogoutAlert: Bool = false
    @StateObject private var socket = SocketService.shared
    @ObservedObject private var network = NetworkService.shared
    let notificationCenter = UNUserNotificationCenter.current()

    private var isDisconnected: Binding<Bool> {
        .constant(!network.isOnline)
    }

    private var isReachable: Bool {
        network.isOnline && !network.fetchFailed
    }

    var body: some View {
        Group {
            if userId == -69420 {
                LoginView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                TabView(selection: $selectedTab) {
                    Tab(String(localized: "general.tabs.play"), systemImage: "play", value: 0) {
                        if isReachable {
                            PlayView()
                        }else {
                            OfflineView(showNavBar: .constant(true),title:"general.title.play")
                        }
                        
                    }

                    Tab(String(localized: "general.tabs.history"), systemImage: "clock", value: 1) {
                        if isReachable {
                            HistoryView(sheetGame: $sheetGame, selectedGameId: $selectedGameId, scrolledGameId: $scrolledGameId)
                        } else {
                            OfflineView(showNavBar: .constant(true),title:"general.title.history")
                        }
                    }

                    Tab(String(localized: "general.tabs.stats"), systemImage: "chart.bar", value: 2) {
                        if isReachable {
                            StatsView()
                        } else {
                            OfflineView(showNavBar: .constant(true),title:"general.title.statistics")
                        }
                    }

                    Tab(String(localized: "general.tabs.profile"), systemImage: "person", value: 3) {
                        if isReachable {
                            ProfileView()
                        }else {
                            OfflineView(showNavBar: .constant(true),title:"general.title.profile")
                        }
                    }.badge(network.friendRequestProfiles.count)
                }
                .animation(.easeInOut, value: isReachable)
                .tabViewStyle(.sidebarAdaptable)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .onChange(of: network.isOnline){
                    if network.isOnline {
                        Task{
                            await network.fetch()
                        }
                    }
                }
                .onAppear {
                    Task { await network.fetch() }
                }
                .onAppear {
                    selectedTab = 0
                }
                .task {
                    do {
                        try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
                    } catch {
                        print("Request authorization error")
                    }
                }
            }
        }.onChange(of:userId){
            if userId == -69420{
                selectedGameId = nil
                scrolledGameId = nil
            }
        }.onChange(of:isReachable){
            if isReachable == true{
                selectedGameId = nil
                scrolledGameId = nil
            }
        }
        //Reconnect if not connected when switching tab for better conenctivity
        .onChange(of:selectedTab){
            Task {
                let wasDisconnected = SocketService.shared.reconnectIfNeeded()
                   if wasDisconnected {
                       await NetworkService.shared.fetch(load: false)
                   }
            }
        }
        /*.onAppear{
            if isFirstLogin{
                isFirstLogin = false
                Task{
                    await network.logout(profileId: userId)
                    showLogoutAlert = true
                }
            }
                
        }*/
        .alert(String(localized:"login.logoutAlert.title"), isPresented: $showLogoutAlert) {
            
            Button(String(localized: "general.alert.ok"), role: .cancel) { }
        } message: {
            Text(String(localized:"login.logoutAlert.description"))
        }
        .alert(String(localized: "general.alert.serverUnreachable"), isPresented: $network.fetchFailed) {
            Button(String(localized: "general.alert.retry")) {
                Task { await network.fetch() }
            }
            Button(String(localized: "general.alert.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "general.alert.serverUnreachable.message"))
        }
        .onOpenURL { url in
            if url == URL(string: "tichu://elo") {
                selectedTab = 1
            }
            if url == URL(string: "tichu://stats") {
                selectedTab = 2
            }
            if url.scheme == "tichu", url.host == "game" {
                let gameId = url.lastPathComponent
                selectedTab = 1
                if Int(gameId) != 0 {
                    selectedGameId = Int(gameId)
                    scrolledGameId = Int(gameId)
                    sheetGame = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapPushNotification)) { _ in
            selectedTab = 3
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .openFriendsSheet, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGame)) { _ in
            selectedTab = 0
        }
        .animation(.easeInOut(duration: 0.4), value: userId == -69420)
    }
}

#Preview {
    MainView()
}
