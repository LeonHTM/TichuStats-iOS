//
//  SocketService.swift
//  TichuStats
//
//  Created by Leon on 15.05.2026.
//

import Foundation
import SocketIO
import Combine
import SwiftUI

final class SocketService: ObservableObject {
    
    //MARK: Vars
    @AppStorage("userId") private var userId = -69420
    @AppStorage("userImageData") var userImageData: Data?
    @AppStorage("userName") var userName: String = "Unknown"
    @AppStorage("userElo") var userElo: Double = 1000
    static let shared = SocketService()
    private var manager: SocketManager!
    private var socket: SocketIOClient!
    @Published var connected = false
    var apiURL: String = getURL()
    var reconnectAttempts: Int = 0
    

    private init() {
        setupSocket()
    }

    // MARK: - Setup Socket Section
    private func setupSocket() {
        guard let url = URL(string: apiURL) else { return }

        manager = SocketManager(
            socketURL: url,
            config: [
                //.log(true),
                .compress,
                .reconnectAttempts(-1),
                .reconnectWait(1)
            ]
        )

        socket = manager.defaultSocket
        setupHandlers()
        connectWithAuth()
    }

    // MARK: Reconnect with new URL
    func reconnect() {
        socket.disconnect()
        socket.removeAllHandlers()
        manager.disconnect()
        setupSocket()
        Task {
            await NetworkService.shared.fetchProfiles()
            await NetworkService.shared.fetchFriends(profileId: userId)
            await NetworkService.shared.fetchFriendRequests(profileId: userId)
        }
    }
    
    // MARK: - Lifecycle Handlers
    @discardableResult
    func reconnectIfNeeded() -> Bool {
        switch socket.status {
        case .connected, .connecting:
            return false
        default:
            connectWithAuth()
            return true
        }
    }
    private func connectWithAuth() {
            let token = NetworkService.shared.authToken
            socket.connect(withPayload: token.isEmpty ? nil : ["token": token])
        }
    func refreshAuth() {
            socket.disconnect()
            socket.removeAllHandlers()
            manager.disconnect()
            setupSocket()
        }
    
    private func setupHandlers() {
        socket.on(clientEvent: .connect) { [weak self] data, ack in
            print("Socket connected")
            DispatchQueue.main.async {
                self?.connected = true
                self?.reconnectAttempts = 0
                NetworkService.shared.isOnline = true
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("Socket disconnected")
            DispatchQueue.main.async { self?.connected = false }
        }

        socket.on(clientEvent: .error) { [weak self] data, ack in
            print("Socket error: \(data)")
            DispatchQueue.main.async { self?.connected = false }
        }
        
        socket.on(clientEvent: .reconnectAttempt) { [weak self] data, ack in
            guard let self else { return }
            self.reconnectAttempts += 1
            if self.reconnectAttempts >= 5 {
                DispatchQueue.main.async {
                    NetworkService.shared.isOnline = false
                }
                self.reconnectAttempts = 0
            }
        }

        socket.on(clientEvent: .reconnect) { [weak self] data, ack in
            guard let self else { return }
            self.reconnectAttempts += 1
            if self.reconnectAttempts >= 5 {
                DispatchQueue.main.async {
                    NetworkService.shared.isOnline = false
                }
                self.reconnectAttempts = 0
            }
        }

        
        
        //MARK: - Profiles Section
        
        //MARK: Profile Created
        socket.on("profile_created") { data, ack in
            Task {
                await NetworkService.shared.fetchProfiles()
            }
        }
        
        //MARK: Profile Deleted
        socket.on("profile_deleted") { data, ack in
            guard let dict = data[0] as? [String: Any],
                  let id = dict["id"] as? Int else {
                print("profile_deleted: failed to parse \(data)")
                return
            }
            Task{
                await NetworkService.shared.fetch(load:false)
                if id == self.userId {
                    self.userId = -69420
                }
            }
        }
        
        //MARK: Username updated
        socket.on("username_updated") { data, ack in
            guard let dict = data[0] as? [String: Any],
                  let profileId = dict["profile_id"] as? Int,
                  let name = dict["name"] as? String else { return }
            DispatchQueue.main.async {
                if let index = NetworkService.shared.profiles.firstIndex(where: { $0.id == profileId }) {
                    withAnimation(.easeInOut) {
                        NetworkService.shared.profiles[index].name = name
                        if profileId == self.userId {
                            self.userName = name
                        }
                    }
                }
            }
        }
        
        //MARK: Admin State updated
        socket.on("admin_updated"){data, ack in
            guard let dict = data[0] as? [String: Any],
                  let profileId = dict["profile_id"] as? Int,
                  let isAdmin = dict["admin"] as? Bool else {
                      print("failed")
                      return }
            
            DispatchQueue.main.async {
                if let index = NetworkService.shared.profiles.firstIndex(where: { $0.id == profileId }) {
                    withAnimation(.easeInOut) {
                        NetworkService.shared.profiles[index].isAdmin = isAdmin
                       
                    }
                }
            }
        }
        
        //Profile Settinsg updated
        socket.on("settings_updated") { data, ack in
            guard
                let dict = data.first as? [String: Any],
                let profileId = dict["id"] as? Int
            else {
                print("Settings: Updated Failed to parse \(data)")
                return
            }
            Task {
                await NetworkService.shared.fetchProfileSettings(profileId: profileId)
            }
        }
        
        
        //MARK: Elo State Updated
        socket.on("elo_updated") { data, ack in
            guard let dict = data[0] as? [String: Any],
                  let players = dict["players"] as? [[String: Any]]
            else {
                print("Elo: Updated Failed to parse \(data)")
                return
            }

            Task {
                for player in players {
                    let id  = player["id"]  as? Int ?? 0
                    let elo = player["elo"] as? Double ?? 0.0
                    
                    if id == self.userId{
                        Task{
                            await NetworkService.shared.fetchEloHistory(profileId: id)
                        }
                    }

                    if let index = NetworkService.shared.profiles.firstIndex(where: { $0.id == id }) {
                        NetworkService.shared.profiles[index].elo = elo
                    }
                }
                print("ELO UPDATED")
            }
            
        }
        
        //MARK: Profile Image updated
        socket.on("profile_image_updated") { data, ack in
            print("profile_image_updated: \(data)")
            Task {
                await NetworkService.shared.fetchProfiles()
            }
        }
    
        //MARK: Remove Friend Request Nortification
        socket.on("remove_friend_request_notification") { data, _ in
            guard let dict = data.first as? [String: Any],
                  let userId = dict["user_id"] as? Int,
                  let senderId = dict["sender_id"] as? Int else { return }
            guard userId == (UserDefaults.standard.integer(forKey: "userId")) else {
                print("Wanted to delete Notification but couldn't")
                return
            }
            removeFriendRequestNotification(fromSenderId: senderId)
        }
 
        //MARK: Friend Request sent
        socket.on("friend_request_sent") { data, ack in
            Task {
                await NetworkService.shared.fetchSentRequests(profileId: self.userId)
                await NetworkService.shared.fetchFriendRequests(profileId: self.userId)
            }
        }

        //MARK: Friend Request Updated
        socket.on("friend_request_updated") { data, ack in
            Task {
                await NetworkService.shared.fetchSentRequests(profileId: self.userId)
                await NetworkService.shared.fetchFriendRequests(profileId: self.userId)
                await NetworkService.shared.fetchFriends(profileId: self.userId)
            }
        }

        //MARK: Friendship added
        socket.on("friendship_added") { [weak self] data, ack in
            print("friendship_added: \(data)")
            Task { [weak self] in
                guard let self = self else { return }
                await NetworkService.shared.fetchSentRequests(profileId: self.userId)
                await NetworkService.shared.fetchSentRequests(profileId: self.userId)
                await NetworkService.shared.fetchFriends(profileId: self.userId)
            }
        }

        //MARK: Friendship removed
        socket.on("friendship_removed") { [weak self] data, ack in
            print("friendship_removed: \(data)")
            Task { [weak self] in
                guard let self = self else { return }
                await NetworkService.shared.fetchFriends(profileId: self.userId)
            }
        }

        

        //MARK: Auth Failed
        socket.on("auth_failed") { data, ack in
            
            Task {
                    await NetworkService.shared.logout(profileId: self.userId)
                
            }
        }

        // MARK: - Game and Rounds Section

        //MARK: Game created
        socket.on("game_created") { data, ack in
            guard let dict = data[0] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
                print("game_created: failed to parse \(data)")
                return
            }
            let decoder = NetworkService.shared.flexibleDateDecoder
            guard let game = try? decoder.decode(Game.self, from: jsonData) else {
                print("game_created: failed to decode Game")
                return
            }
            Task { @MainActor in
                if !NetworkService.shared.games.contains(where: { $0.id == game.id }) {
                    withAnimation(.easeInOut) {
                        print("game created: appening now \(game.id)")
                        NetworkService.shared.games.append(game)
                    }
                }
            }
        }

        //MARK: Game deleted
        socket.on("game_deleted") { data, ack in
            guard let dict = data[0] as? [String: Any],
                  let gameId = dict["game_id"] as? Int else {
                print("game_deleted: failed to parse \(data)")
                return
            }
            Task {
                print("Game Deleted: \(gameId)")
                NetworkService.shared.games.removeAll { $0.id == gameId }
                NetworkService.shared.roundsByGame.removeValue(forKey: gameId)

                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await NetworkService.shared.fetchSelectedProfilesStats()
                    }
                    group.addTask {
                        await NetworkService.shared.fetchProfileStatsHistory(profileId: self.userId)
                    }
                    group.addTask{
                        await  NetworkService.shared.fetchEloHistory(profileId: self.userId)
                    }
                    group.addTask{
                        await NetworkService.shared.fetchProfiles()
                    }
                }
            }
            
        }
        
        //MARK: Game recalculated
        socket.on("game_recalculated") { data, ack in
            guard let dict = data.first as? [String: Any],
                  let gameId = dict["game_id"] as? Int else {
                print("game_recalculated: failed to parse \(data)")
                return
            }

            print("game_recalculated for game \(gameId)")
                Task {
                    await withTaskGroup(of:Void.self){group in
                        group.addTask{
                            await NetworkService.shared.fetchGame(gameId: gameId)
                        }
                        group.addTask{
                            await NetworkService.shared.fetchGameRounds(gameId: gameId)
                        }
                        group.addTask{
                            await NetworkService.shared.fetchProfileStatsHistory(profileId: self.userId)
                        }
                    }
                }
            
        }
        
        //MARK: GAME finished
        socket.on("game_finished") { data, _ in
            //guard let gameId = (data.first as? [String: Any])?["game_id"] as? Int else { return }
            Task {
                /*if gameId == NetworkService.shared.currentGameId{
                    NetworkService.shared.finishGameEditing = false
                    Task{
                        await NetworkService.shared.fetchSelectedProfilesStats()
                    }
                    print("RECIEVED GAME FINISHED CALL ")
                }*/
                Task{
                    //THis should fetch anyway, stats of other people could have changed
                    await NetworkService.shared.fetchSelectedProfilesStats()
                }
            }
        }
        
        socket.on("game_updated"){data,ack in
            guard let dict = data[0] as? [String: Any],
                  let gameId = dict["game_id"] as? Int else {
                print("game_updeated: failed to parse \(data)")
                return
            }
            Task{
                await NetworkService.shared.fetchGame(gameId: gameId)
            }
        }

        //MARK: Round updated
        socket.on("round_updated") { data, ack in
            guard let dict = data[0] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let updated = try? decoder.decode(Round.self, from: jsonData) else { return }
            DispatchQueue.main.async {
                let gameId = updated.gameId
                if var rounds = NetworkService.shared.roundsByGame[gameId],
                   let index = rounds.firstIndex(where: { $0.id == updated.id }) {
                    rounds[index] = updated
                    NetworkService.shared.roundsByGame[gameId] = rounds
                }
            }
            
                Task { await NetworkService.shared.fetchProfileGames(profileId: self.userId) }
            
        }

        //MARK: Round deleted
        socket.on("round_deleted") { data, ack in
            guard let dict = data[0] as? [String: Any],
                  let gameId = dict["game_id"] as? Int else { return }
                Task{
                    await NetworkService.shared.reCalculate(gameId: gameId)
                }
        }

        //MARK: Round created
        socket.on("round_created") { data, ack in
            guard let dict = data[0] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let round = try? decoder.decode(Round.self, from: jsonData) else { return }
            let gameId = round.gameId
            DispatchQueue.main.async {
                var list = NetworkService.shared.roundsByGame[gameId] ?? []
                if !list.contains(where: { $0.id == round.id }) {
                    list.append(round)
                    list.sort { $0.roundOrder < $1.roundOrder }
                    NetworkService.shared.roundsByGame[gameId] = list
                }
            }
                Task {
                    await NetworkService.shared.reCalculate(gameId: gameId)
                }
        }
 
    }

    // MARK: - Disconnect
    func disconnect() {
        socket.disconnect()
    }
}

