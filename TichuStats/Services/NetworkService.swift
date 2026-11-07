//
//  NetworkService.swift
//  TichuStats
//
//  Created by Leon on 15.05.2026.
//

import Foundation
import Combine
import SwiftUI
import WidgetKit
import Network

//MARK: - NetworkService handles everything that has to do with Server Endpooints gets accesed by Socket and various Views
class NetworkService: ObservableObject {
    //MARK: Vars
    static let shared = NetworkService()

    //MARK: App Storage
    @AppStorage("userId") private var userId = -69420
    @AppStorage("userImageData") var userImageData: Data?
    @AppStorage("userName") var userName: String = "Unknown"
    @AppStorage("userElo") var userElo: Double = 1000
    @AppStorage("pendingDeviceToken") var pendingDeviceToken: String = ""
    @AppStorage("authToken") var authToken: String = ""
    @AppStorage("isLoading") var isLoading: Bool = false
    @AppStorage("statsList") private var statsList: [Int] = []
    @AppStorage("favDic") var favDic: [Int:Int] = [:]
    
    //MARK: Settings
    @AppStorage("defaultTarget") var defaultTarget: Int = 1000
    @AppStorage("defaultAllowPingus") var defaultAllowPingus: Bool = true
    @AppStorage("dragMode") var dragMode: Bool = false
    @AppStorage("showAllPlayers") private var showAllPlayers: Bool = false
    @AppStorage("sortByProfiles") var sortByProfiles: sortBy = .nameDown
    @AppStorage("sortByStats") var sortByStats: sortBy = .valueDown
    
    //MARK: Published Variables
    //FinishGameEditing locks the editing in GameSummarySheetOverView as soon as someone in the round closes the sheet
    @Published var currentGameId: Int? = nil
    @Published var games: [Game] = []
    @Published var roundsByGame: [Int: [Round]] = [:]
    @Published var finishGameEditing: Bool = true
    @Published var isOnline: Bool = true
    @Published var fetchFailed: Bool = false
    @Published var apiURL: String = getURL()
    private let pathMonitor = NWPathMonitor()
    
    
    //FriendRequests are recieved requests
    @Published var eloHistory: [EloHistoryEntry] = []
    @Published var profiles: [Profile] = []
    @Published var profileImages: [Int: Data] = [:]
    @Published var friends: [Friend] = []
    @Published var friendRequestProfiles: [Profile] = []
    @Published var friendRequestImages: [Int: Data] = [:]
    @Published var friendRequests: [(id: Int, senderId: Int)] = []
    @Published var sentRequests: [(id: Int, receiverId: Int)] = []
    
    //StatsHistory
    @Published var statsHistory: [String:[ProfileStats]] = [:]
    
    //No one else can create instance only ever talks to this instance
    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    // MARK: - Flexible Date Decoder
    var flexibleDateDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.timeZone = TimeZone(identifier: "UTC") // incoming strings are UTC
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: str) { return date }

            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: str) { return date }

            let fallback = DateFormatter()
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.timeZone = TimeZone(identifier: "UTC") // naive strings assumed UTC too
            fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = fallback.date(from: str) { return date }

            fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            if let date = fallback.date(from: str) { return date }

            fallback.dateFormat = "yyyy-MM-dd"
            if let date = fallback.date(from: str) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return decoder
    }
    
    // MARK: - Authentification Section
    
    // Used for endpoints that require a logged-in user
    private func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    //Used for unauthenticated endpoints (login, addProfile, checkEmail)
    private func appAuthorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let appToken = Bundle.main.object(forInfoDictionaryKey: "APP_TOKEN") as? String, !appToken.isEmpty {
            request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        } else {
            print("Missing App Token")
        }
        return request
    }
    
    // MARK: completeAuth centralizes the "I have a valid token+id" setup, called by every
    // auth path (login, addProfile, verifyLoginCode, passkeys) so they stay consistent.
    private func completeAuth(token: String, userId: Int) async {
        await MainActor.run {
            self.authToken = token
            self.userId = userId
            self.isLoading = true
        }

        await registerDevice(profileId: userId, deviceToken: pendingDeviceToken)
        await NetworkService.shared.fetch()

        await MainActor.run {
            self.isLoading = false
        }
    }
    
    // MARK: resetClientData used in Config to forcefully reconnect to other Server
    func resetClientData() {
        self.profiles = []
        self.friendRequestProfiles = []
        self.friends = []
        self.profileImages = [:]
        self.sentRequests = []
        self.friendRequestImages = [:]
        self.friendRequests = []
        self.sentRequests = []
        self.authToken = ""
        self.userId = -69420
    }
    
    //MARK: - Login and Logout Section
    
    //MARK: registerDevice used to register a device for APNs on login
    func registerDevice(profileId: Int, deviceToken: String) async {
        guard let url = URL(string: "\(apiURL)/register_device/\(profileId)") else { return }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["device_token": deviceToken])

        do {
            _ = try await URLSession.shared.data(for: request)
            print("Device token registered successfully")
        } catch {
            print("registerDevice error: \(error)")
        }
    }
    
    
    
    // MARK: sendMail used in LoginView to request a login code be sent to the given email
    func sendMail(mail: String) async -> Bool {
        guard let encoded = mail.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(apiURL)/login/request-code") else { return false }
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        var request = appAuthorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": encoded,
            "language_code":languageCode
        ])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            print("Sent mail: \(mail)")
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("sendMail error: \(error)")
            return false
        }
    }

    // MARK: verifyLoginCode used in LoginView after the user enters the code they received by email
    func verifyLoginCode(mail: String, code: String, name: String) async -> Bool {
        guard
            let encodedMail = mail.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedCode = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "\(apiURL)/login/verify-code/\(encodedMail)/\(encodedCode)")
        else {
            return false
        }

        let request = appAuthorizedRequest(url: url, method: "POST")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            guard httpResponse.statusCode == 200 else {
                print("verifyLoginCode status:", httpResponse.statusCode)
                return false
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let exists = json["exists"] as? Bool else {
                print("Invalid response:", String(data: data, encoding: .utf8) ?? "")
                return false
            }

            if exists {
                guard
                    let token = json["token"] as? String,
                    let userId = json["id"] as? Int
                else {
                    print("Existing user response missing token/id")
                    return false
                }

                await completeAuth(token: token, userId: userId)
                return true

            } else {
                print("User does not exist, creating profile")

                let newId = await self.addProfile(
                    email: mail,
                    name: name
                )

                return newId != nil
            }

        } catch {
            print("verifyLoginCode error:", error)
            return false
        }
    }

    //MARK: logout used in NavigationProfileImage, SocketService and ProfileView
    func logout(profileId: Int, local: Bool = false) async {
        if !local {
            guard let url = URL(string: "\(apiURL)/logout/\(profileId)") else { return }

            var request = authorizedRequest(url: url, method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["device_token": pendingDeviceToken])

            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                print("logout error: \(error)")
            }
        }

        await MainActor.run {
            self.authToken = ""
            self.userId = -69420
            self.userName = "Unknown"
            self.userImageData = nil
            self.userElo = 1000
            self.statsList = []
            self.defaultTarget = 1000
            self.dragMode = false
            self.defaultAllowPingus = true
            self.sortByProfiles = .nameDown
            self.sortByStats = .valueDown
            self.favDic = [:]
            self.statsHistory = [:]

            let defaults = UserDefaults(suiteName: "group.com.drakynem.tichu")
            defaults?.removeObject(forKey: "userName")
            defaults?.removeObject(forKey: "userElo")
            defaults?.removeObject(forKey: "widgetGames")

            func reset(_ base: String) {
                defaults?.removeObject(forKey: "user\(base)")
                defaults?.removeObject(forKey: "user\(base)Year")
                defaults?.removeObject(forKey: "user\(base)Month")
                defaults?.removeObject(forKey: "user\(base)Week")
                defaults?.removeObject(forKey: "user\(base)Day")
            }

            reset("WinnerPercentage")
            reset("TichuMaster")
            reset("Visionary")
            reset("Addict")
            reset("Teamplayer")
            reset("Announcer")
            reset("Saboteur")
            reset("Gambler")
            reset("BigGambler")
            reset("PinguGambler")
            reset("Bomber")
        }

        // Clear all notifications and badge on logout
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }
    
    //MARK: addProfile used in EditNameSheetView on login when creating Profile
    func addProfile(email: String, name: String) async -> Int? {
        guard let url = URL(string: "\(apiURL)/add_profile") else { return nil }

        var request = appAuthorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "name": name
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let token = json?["token"] as? String,
               let id = json?["id"] as? Int {
                await completeAuth(token: token, userId: id)
            }
            return json?["id"] as? Int
        } catch {
            print("createAccount error: \(error)")
            return nil
        }
    }
    
    //MARK: checkUserName used in EditNameSheetView to check if name is available
    func checkUsername(username: String) async -> Bool {
        guard let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(apiURL)/check_username/\(encoded)") else { return false }

        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["available"] as? Bool ?? false
        } catch {
            print("checkUsername error: \(error)")
            return false
        }
    }

    //MARK: updateUserName used in EditNameSheetView
    func updateUsername(profileId: Int, name: String) async {
        guard let url = URL(string: "\(apiURL)/update_username/\(profileId)") else { return }

        var request = authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])

        do {
            _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                if let index = self.profiles.firstIndex(where: { $0.id == profileId }) {
                    self.profiles[index].name = name
                }
            }
        } catch {
            print("updateUsername error: \(error)")
        }
    }

    //MARK: checkMail used in LoginView to check if mail is available
    func checkEmail(email: String) async -> Int? {
        guard let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(apiURL)/check_email/\(encoded)") else { return nil }

        do {
            let request = appAuthorizedRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let id = json?["id"] as? Int
            return id 
        } catch {
            print("checkEmail error: \(error)")
            return nil
        }
    }
    
    // MARK: - Passkey Section

    // MARK: signUpWithPasskey used in LoginSheetView when there's a chosen
    @discardableResult
    func signUpWithPasskey(name: String,mail:String?) async throws -> Int {
        let result = try await PasskeyManager.shared.signUp(name: name, mail: mail)
        await applyPasskeyResult(result)
        return result.userId
    }

    // MARK: signInWithPasskey used in LoginSheetView (Mail is optional)
    @discardableResult
    func signInWithPasskey(email: String?) async throws -> Int {
        let result = try await PasskeyManager.shared.signIn(email: email)
        await applyPasskeyResult(result)
        return result.userId
    }

    // MARK: applyPasskeyResult mirrors the second half of login(userId:).
    private func applyPasskeyResult(_ result: AuthResult) async {
        await MainActor.run {
            self.authToken = result.token
            self.userId = result.userId
        }
        Task {
            isLoading = true
            await registerDevice(profileId: result.userId, deviceToken: pendingDeviceToken)
            await NetworkService.shared.fetch()
            isLoading = false
        }
    }
    
    //MARK: addPasskeyToACcount used in ProfilesView
    func addPasskeyToAccount() async throws {
           try await PasskeyManager.shared.addPasskey(userToken: authToken)
       }
    
    
    //MARK: - Profile Section
    
    //MARK: fetchProfiles used in fetch(), SocketService, Socket reconnect, Socket pfp updated and EditFriendsSheetView
    @discardableResult
    func fetchProfiles() async -> Bool {
        guard let url = URL(string: "\(apiURL)/profilessimple") else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let decoded = try await Task.detached(priority: .userInitiated) { [decoder = self.flexibleDateDecoder] in
                try decoder.decode([Profile].self, from: data)
            }.value
            await MainActor.run {
                withAnimation(.easeInOut) {
                    let fetchedById = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
                    self.profiles.removeAll { fetchedById[$0.id] == nil }
                    for newProfile in decoded {
                        if let index = self.profiles.firstIndex(where: { $0.id == newProfile.id }) {
                            self.profiles[index].createdAt = newProfile.createdAt
                            self.profiles[index].name = newProfile.name
                            self.profiles[index].profileImageUrl = newProfile.profileImageUrl
                            self.profiles[index].elo = newProfile.elo
                            if newProfile.id == userId {
                                self.userName = newProfile.name ?? "Unknown"
                                self.userElo = newProfile.elo ?? 1000
                            }
                        } else {
                            self.profiles.append(newProfile)
                        }
                    }
                }
            }
            await fetchProfileImages()
            return true
        } catch {
            print("fetchProfiles error: \(error)")
            return false
        }
    }
    
    //MARK: fetchProfileImages used in fetchProfiles
    func fetchProfileImages(replace:Bool = false) async {
        print("fetching profile images")
        let snapshot = await MainActor.run { profiles }
        for profile in snapshot {
            guard let urlString = profile.profileImageUrl,
                  let filename = urlString.components(separatedBy: "/").last,
                  let url = URL(string: "\(apiURL)/uploads/profile_images/\(filename)") else { continue }
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                let (data, _) = try await URLSession.shared.data(for: request)
                await MainActor.run {
                    self.profileImages[profile.id] = data
                    if profile.id == self.userId {
                        userImageData = data
                        self.userImageData = data
                    }
                }
            } catch {
                print("loadProfileImages error for profile \(profile.id): \(error)")
            }
        }
    }
    
    //MARK: fechtProfileImage not in use
    func fetchProfileImage(profileId: Int, filename: String) async -> Data? {
        guard let url = URL(string: "\(apiURL)/uploads/profile_images/\(filename)") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            print("fetchProfileImage error: \(error)")
            return nil
        }
    }

    //MARK: fetchProfileStats used in AddPlayerSheetView and fetchSelectedProfilesStats()
    func fetchProfilesStats(profileId: Int) async {
        let timeframes = ["all_time", "year", "month", "week", "day"]
        let apiURL = self.apiURL
        let timezone = TimeZone.current.identifier

        await withTaskGroup(of: (String, ProfileStats?).self) { group in
            for timeframe in timeframes {
                group.addTask {
                    guard var components = URLComponents(string: "\(apiURL)/profilesstats/\(profileId)") else {
                        return (timeframe, nil)
                    }
                    components.queryItems = [
                        URLQueryItem(name: "timeframe", value: timeframe),
                        URLQueryItem(name: "timezone", value: timezone)
                    ]
                    guard let url = components.url else {
                        return (timeframe, nil)
                    }
                    do {
                        let (data, _) = try await URLSession.shared.data(for: self.authorizedRequest(url: url))
                        let decoded = try await Task.detached(priority: .userInitiated) { [decoder = self.flexibleDateDecoder] in
                            try decoder.decode(ProfileStats.self, from: data)
                        }.value
                        return (timeframe, decoded)
                    } catch {
                        print("fetchProfilesStats error (\(timeframe)): \(error)")
                        return (timeframe, nil)
                    }
                }
            }

            var results: [String: ProfileStats] = [:]
            for await (timeframe, stats) in group {
                if let stats { results[timeframe] = stats }
            }

            await MainActor.run {
                if let index = self.profiles.firstIndex(where: { $0.id == profileId }) {
                    withAnimation(.easeInOut) {
                        if let s = results["all_time"] { self.profiles[index].allTime = s }
                        if let s = results["year"]     { self.profiles[index].year    = s }
                        if let s = results["month"]    { self.profiles[index].month   = s }
                        if let s = results["week"]     { self.profiles[index].week    = s }
                        if let s = results["day"]      { self.profiles[index].day     = s }
                        print("Fetched stats for: \(self.profiles[index].name ?? "Unknown")")
                    }
                }
            }
        }
    }
    
    func fetchProfileStatsHistory(profileId: Int, stat: String = "all_time") async {
        guard let url = URL(string: "\(apiURL)/profilestats/history") else { return }
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "profile_id": profileId,
            "stat": stat
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            let history = try await Task.detached(priority: .userInitiated) { [flexibleDateDecoder] in
                let decoder = flexibleDateDecoder
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode([String: [ProfileStats]].self, from: data)
            }.value

            await MainActor.run {
                self.statsHistory = history
            }
        } catch {
            print("fetchProfileStatsHistory Error: \(error)")
        }
    }
    
        
        
    // MARK: fetchProfileSettings used in fetch
    func fetchProfileSettings(profileId: Int) async {
        guard let url = URL(string: "\(apiURL)/profile/\(profileId)/settings") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            await MainActor.run {
                if let target = json?["default_target"] as? Int {
                    self.defaultTarget = target
                }
                if let showPingu = json?["show_pingu"] as? Bool {
                    self.defaultAllowPingus = showPingu
                }
                if let drag = json?["drag_mode"] as? Bool {
                    self.dragMode = drag
                }
                if let showAllPlayers = json?["show_all_players"] as? Bool {
                    self.showAllPlayers = showAllPlayers
                }
                if let sortByProfiles = json?["sort_by_profiles"] as? Int{
                    self.sortByProfiles = PickerSettingsEncoder(x:sortByProfiles)
                }
                if let sortByStats = json?["sort_by_stats"] as? Int{
                    self.sortByStats = PickerSettingsEncoder(x: sortByStats)
                }
            }
        } catch {
            print("fetchProfileSettings error: \(error)")
        }
    }

    //MARK: updateProfileSettings used in ProfileView
    func updateProfileSettings(profileId: Int, target: Int, showPingu: Bool, dragMode: Bool, showAllPlayers: Bool, sortByProfiles: sortBy, sortByStats: sortBy) async {
        guard let url = URL(string: "\(apiURL)/profile/\(profileId)/settings") else { return }

        let body: [String: Any] = [
            "default_target": target,
            "show_pingu": showPingu,
            "drag_mode": dragMode,
            "show_all_players": showAllPlayers,
            "sort_by_profiles": PickerSettingsEncoder(x:sortByProfiles),
            "sort_by_stats": PickerSettingsEncoder(x:sortByStats)
        ]

        var request = authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            print("updateProfileSettings error: \(error)")
        }
    }
    
    //MARK: isAdmin used in PlayView, StatsView, HistoryView and SocketService admin_update
    func isAdmin(profileId: Int) async -> Bool {
        guard let url = URL(string: "\(apiURL)/profile/\(profileId)/is_admin") else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["is_admin"] as? Bool ?? false
        } catch {
            print("isAdmin error: \(error)")
            return false
        }
    }
    
    //MARK: deleteProfile used in ProfileView
    func deleteProfile(profileId: Int) async {
        guard let url = URL(string: "\(apiURL)/delete_profile/\(profileId)") else { return }

        let request = authorizedRequest(url: url, method: "DELETE")

        do {
            _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                self.profiles.removeAll { $0.id == profileId }
            }
            await self.logout(profileId: profileId,local: true)
        } catch {
            print("deleteProfile error: \(error)")
        }
    }
    
    //MARK: uploadProfileImage used in ProfileView
    func uploadProfileImage(
        profileId: Int,
        imageData: Data,
        maxSize: CGFloat = 256,
        quality: CGFloat = 0.4
    ) async {
        guard let uiImage = UIImage(data: imageData) else {
            print("uploadProfileImage: invalid image data")
            return
        }

        let resized = uiImage.resized(to: maxSize)

        guard let compressedData = resized.jpegData(compressionQuality: quality) else {
            print("uploadProfileImage: compression failed")
            return
        }

        guard let url = URL(string: "\(apiURL)/add_image/\(profileId)/") else { return }

        var request = authorizedRequest(url: url, method: "POST")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"profile_\(profileId).jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(compressedData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                self.profileImages[profileId] = compressedData
                if profileId == self.userId {
                    self.userImageData = compressedData
                }
            }
        } catch {
            print("uploadProfileImage error: \(error)")
        }
    }
    
    //MARK: fetchSelectedProfilesStats used in SocketService and Statsview fetches the Stats for selectedProfiles in StatsList which is configured in StatsView
    func fetchSelectedProfilesStats() async{
        await withTaskGroup(of: Void.self) { group in
            var statsCopy = statsList
            statsCopy.append(userId)
            for profileId in statsCopy {
                group.addTask {
                    await self.fetchProfilesStats(profileId: profileId)

                    if await profileId == self.userId {
                        await MainActor.run {
                            let defaults = UserDefaults(suiteName: "group.com.drakynem.tichu")
                            guard let profile = self.profiles.first(where: { $0.id == self.userId }) else { return }

                            if let name = profile.name {
                                defaults?.set(name, forKey: "userName")
                            }
                            if let elo = profile.elo {
                                defaults?.set(elo, forKey: "userElo")
                            }

                            func save(_ base: String, _ keyPath: KeyPath<ProfileStats, Double>) {
                                defaults?.set(profile.allTime[keyPath: keyPath], forKey: "user\(base)")
                                defaults?.set(profile.year[keyPath: keyPath], forKey: "user\(base)Year")
                                defaults?.set(profile.month[keyPath: keyPath], forKey: "user\(base)Month")
                                defaults?.set(profile.week[keyPath: keyPath], forKey: "user\(base)Week")
                                defaults?.set(profile.day[keyPath: keyPath], forKey: "user\(base)Day")
                            }

                            save("WinnerPercentage", \.winnerPercentage)
                            save("averagePlacement", \.averagePlacement)
                            save("TichuMaster",      \.tichuMaster)
                            save("Visionary",        \.visionary)
                            save("Addict",           \.addict)
                            save("Teamplayer",       \.teamplayer)
                            save("Announcer",        \.announcer)
                            save("Saboteur",         \.saboteur)
                            save("Gambler",          \.gambler)
                            save("BigGambler",       \.bigGambler)
                            save("PinguGambler",     \.pinguGambler)
                            save("Bomber",           \.bomber)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Friends Section

    //MARK: fetchFriends used in fetch(), SocketService and EditFriendsSHeetView
    func fetchFriends(profileId: Int) async {
        guard let url = URL(string: "\(apiURL)/friends/\(profileId)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

            let fetchedFriends = await Task.detached(priority: .userInitiated) { [decoder = self.flexibleDateDecoder] () -> [Friend] in
                raw.compactMap { dict in
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                          let profile = try? decoder.decode(Profile.self, from: jsonData) else { return nil }

                    var date: Date? = nil
                    if let dateStr = dict["friends_since"] as? String,
                       let dateData = try? JSONEncoder().encode(dateStr) {
                        date = try? decoder.decode(Date.self, from: dateData)
                    }

                    return Friend(id: profile.id, profile: profile, friendsSince: date)
                }
            }.value

            await MainActor.run {
                withAnimation(.easeInOut) {
                    self.friends = fetchedFriends
                }
            }
        } catch {
            print("fetchFriends error: \(error)")
        }
    }

    //MARK: addFriend not used because can only become friends after requesting which the server manages
    func addFriend(profileId: Int, friendId: Int) async {
        guard let url = URL(string: "\(apiURL)/add_friendship/\(profileId)/friends/\(friendId)") else { return }

        let request = authorizedRequest(url: url, method: "POST")

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            print("addFriend error: \(error)")
        }
        removeFriendRequestNotification(fromSenderId: friendId)
    }
    
    //MARK: removeFriend used in PlayView and AddPlayersSheetview ContextMenus, EditFriendsSheetView and SocketService
    func removeFriend(profileId: Int, friendId: Int) async {
        guard let url = URL(string: "\(apiURL)/delete_friendship/\(profileId)/friends/\(friendId)") else { return }

        let request = authorizedRequest(url: url, method: "DELETE")

        do {
            _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                withAnimation(.easeInOut) {
                    self.friends.removeAll { $0.id == friendId }
                }
            }
        } catch {
            print("removeFriend error: \(error)")
        }
    }

    //MARK: fetchSentRequests used SocketService and EditFriendsSheetView
    func fetchSentRequests(profileId: Int) async {
        guard let url = URL(string: "\(apiURL)/sent_requests/\(profileId)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

            let parsed = raw.compactMap { dict -> (id: Int, receiverId: Int)? in
                guard let id = dict["id"] as? Int,
                      let receiverId = dict["receiver_id"] as? Int else { return nil }
                return (id: id, receiverId: receiverId)
            }

            await MainActor.run {
                self.sentRequests = parsed
            }
        } catch {
            print("fetchSentRequests error: \(error)")
        }
    }
    
    //MARK: sendFriendRequest used in ContextMenus in AddPlayersSheetVeiw and PlayView and EditFriendSheetView
    func sendFriendRequest(senderId: Int, receiverId: Int) async {
        guard let url = URL(string: "\(apiURL)/add_request/\(senderId)/request/\(receiverId)") else { return }

        let request = authorizedRequest(url: url, method: "POST")

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            print("sendFriendRequest error: \(error)")
        }
    }
    
    //MARK: respondToFriendRequest used in EditFriendsSheet
    func respondToFriendRequest(receiverId: Int, senderId: Int, action: String) async {
        guard let url = URL(string: "\(apiURL)/manage_requests/\(receiverId)/from/\(senderId)") else { return }

        var request = authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action])

        do {
            _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                self.friendRequests.removeAll { $0.senderId == senderId }
                self.friendRequestProfiles.removeAll { $0.id == senderId }
            }
            removeFriendRequestNotification(fromSenderId: senderId)
        } catch {
            print("respondToFriendRequest error: \(error)")
        }
    }
    
    // MARK: cancelFriendRequest used in EditFriendsSheet
    func cancelFriendRequest(senderId: Int, receiverId: Int) async {
        guard let url = URL(
            string: "\(apiURL)/remove_request/\(senderId)/to/\(receiverId)"
        ) else { return }

        let request = authorizedRequest(url: url, method: "DELETE")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print(
                    "cancelFriendRequest failed:",
                    String(data: data, encoding: .utf8) ?? ""
                )
                return
            }

            await MainActor.run {
                withAnimation(.easeInOut) {
                    self.sentRequests.removeAll {
                        $0.receiverId == receiverId
                    }
                }
            }

        } catch {
            print("cancelFriendRequest error: \(error)")
        }
    }

    
    //MARK: fetchFriendRequests (fetches recieved requests) used in EditFriendsSheetview and SocketService
    func fetchFriendRequests(profileId: Int) async {
        guard let url = URL(string: "\(apiURL)/requests/\(profileId)/") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

            let parsed = raw.compactMap { dict -> (id: Int, senderId: Int)? in
                guard let id = dict["id"] as? Int,
                      let senderId = dict["sender_id"] as? Int else { return nil }
                return (id: id, senderId: senderId)
            }

            let senderIds = parsed.map { $0.senderId }

            await MainActor.run {
                self.friendRequests = parsed
                self.friendRequestProfiles = self.profiles.filter { senderIds.contains($0.id) }
            }

            let snapshot = await MainActor.run { friendRequestProfiles }
            for profile in snapshot {
                guard let urlString = profile.profileImageUrl,
                      let filename = urlString.components(separatedBy: "/").last,
                      let imageUrl = URL(string: "\(apiURL)/uploads/profile_images/\(filename)") else { continue }
                do {
                    let (imageData, _) = try await URLSession.shared.data(from: imageUrl)
                    await MainActor.run {
                        self.friendRequestImages[profile.id] = imageData
                    }
                } catch {
                    print("fetchFriendRequestImages error for profile \(profile.id): \(error)")
                }
            }
        } catch {
            print("fetchFriendRequests error: \(error)")
        }
    }
    
    
    //MARK: - Main Fetch Funciton used in PlayView, HistoryView Section
    func fetch(load: Bool = true) async {
        let currentUserId = userId
        guard currentUserId != -69420, !authToken.isEmpty else { return }
        if load { isLoading = true }
            await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let success = await self.fetchProfiles()

                await MainActor.run {
                    self.fetchFailed = !success
                }

                if !success {
                    return
                }

                let matchFound = await MainActor.run { self.profiles.first(where: { $0.id == currentUserId }) != nil }
                if !matchFound {
                    //Should be local but im not sure if server is clean profileId: currentUSerId,local:true
                    await NetworkService.shared.logout(profileId: currentUserId)
                    return
                }

                await self.fetchSelectedProfilesStats()
            }
            group.addTask { await self.fetchFriends(profileId: currentUserId) }
            group.addTask { await self.fetchFriendRequests(profileId: currentUserId) }
            group.addTask { await self.fetchProfileGames(profileId: currentUserId) }
            group.addTask { await self.fetchEloHistory(profileId: currentUserId) }
            group.addTask { await self.fetchProfileSettings(profileId: currentUserId) }
        }

        isLoading = false
    }
    
    //MARK: - Games and Rounds Section
    
    //MARK: fetchGamesHistory used in HistoryView to refresh the History
    func fetchGamesHistory(load: Bool = true) async {
        if load{
            isLoading = true
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchFriendRequests(profileId: self.userId) }
            group.addTask { await self.fetchProfileGames(profileId: self.userId) }
        }
        isLoading = false
    }
   
    // MARK: addGame used in PlayView
    func addGame(
        target: Int,
        allowPingus: Bool,
        team1Player1Id: Int?,
        team1Player2Id: Int?,
        team2Player1Id: Int?,
        team2Player2Id: Int?,
        guest2Name: String? = nil,
        guest3Name: String? = nil,
        guest4Name: String? = nil
    ) async -> Game? {
        guard let url = URL(string: "\(apiURL)/add_game") else { return nil }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "target": target,
            "allow_pingus": allowPingus,
            "team1_player1_id": team1Player1Id as Any,
            "team1_player2_id": team1Player2Id as Any,
            "team2_player1_id": team2Player1Id as Any,
            "team2_player2_id": team2Player2Id as Any,
            "guest2_name": guest2Name as Any,
            "guest3_name": guest3Name as Any,
            "guest4_name": guest4Name as Any
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = flexibleDateDecoder
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let game = try decoder.decode(Game.self, from: data)
            //Append the game itsself dont wait for socket
            await MainActor.run {
                if !self.games.contains(where: { $0.id == game.id }) {
                    self.games.append(game)
                }
            }
            return game
        } catch {
            print("addGame error: \(error)")
            return nil
        }
    }
    
    //MARK: isInOpenGame used in AddPlayersSheetView
    func isInOpenGame(profileId: Int) async -> Bool {
        guard let url = URL(string: "\(apiURL)/profile/\(profileId)/in_open_game") else { return false }

        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            return try JSONDecoder().decode(Bool.self, from: data)
        } catch {
            print("isInOpenGame error: \(error)")
            return false
        }
    }

    //MARK: deleteGame used in EditRoundsSheetView, GameSummarySheetView and GameSummaryListview
    func deleteGame(gameId: Int) async {
        guard let url = URL(string: "\(apiURL)/delete_game/\(gameId)") else { return }

        let request = authorizedRequest(url: url, method: "DELETE")

        do {
            _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                self.games.removeAll { $0.id == gameId }
                self.roundsByGame.removeValue(forKey: gameId)
                favDic.removeValue(forKey: gameId)
            }
        } catch {
            print("deleteGame error: \(error)")
        }
    }
    
    //MARK: fetchProfileGames used in SocketService
    func fetchProfileGames(profileId: Int) async {
        guard let url = URL(string: "\(apiURL)/profile/\(profileId)/games") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            nonisolated struct Response: Decodable {
                let profileId: Int
                let games: [Game]
            }

            let decoded = try await Task.detached(priority: .userInitiated) { [decoder = self.flexibleDateDecoder] in
                try decoder.decode(Response.self, from: data)
            }.value

            await MainActor.run {
                self.games = decoded.games.map { game in
                    var g = game
                    g.favorite = favDic[game.id].map { $0 == 1 } ?? false
                    return g
                }

                let defaults = UserDefaults(suiteName: "group.com.drakynem.tichu")

                var existingGames: [WidgetGameData] = []
                if let data = defaults?.data(forKey: "widgetGames"),
                   let decodedExisting = try? JSONDecoder().decode([WidgetGameData].self, from: data) {
                    existingGames = decodedExisting
                }

                let updatedGames = decoded.games.map { game -> WidgetGameData in
                    let isFavorite = favDic[game.id].map { $0 == 1 } ?? false
                    if let existing = existingGames.first(where: { $0.id == game.id }) {
                        return WidgetGameData(
                            winner: game.winner, favorite: isFavorite, id: game.id, date: game.date,
                            team1Score: game.currentPointsTeam1, team2Score: game.currentPointsTeam2,
                            rounds: existing.rounds
                        )
                    } else {
                        return WidgetGameData(
                            winner: game.winner, favorite: isFavorite, id: game.id, date: game.date,
                            team1Score: game.currentPointsTeam1, team2Score: game.currentPointsTeam2,
                            rounds: []
                        )
                    }
                }

                if let encoded = try? JSONEncoder().encode(updatedGames) {
                    defaults?.set(encoded, forKey: "widgetGames")
                }
            }
        } catch {
            print("fetchProfileGames error: \(error)")
        }
    }

    //MARK: fetchGame used in SocketService, GameSummaryListview, EditRoundsSheetView, HistoryView and PlayView
    func fetchGame(gameId: Int) async {
        guard let url = URL(string: "\(apiURL)/game/\(gameId)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let game = try flexibleDateDecoder.decode(Game.self, from: data)
            await MainActor.run {
                if let index = self.games.firstIndex(where: { $0.id == gameId }) {
                    self.games[index] = game
                } else {
                    self.games.append(game)
                }
            }
        } catch {
            print("fetchGame error: \(error)")
        }
    }
    
    
    //MARK: updateGuestName used in PlayView
    func updateGameGuestName(gameId: Int, guestId: Int, guestName: String) async {
        guard let url = URL(string: "\(apiURL)/game/edit_guest_name") else { return }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "game_id": gameId,
            "guest_id": guestId,
            "guest_name": guestName
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("updateGameGuestName failed: \(String(data: data, encoding: .utf8) ?? "")")
                return
            }

            await MainActor.run {
                guard let index = games.firstIndex(where: { $0.id == gameId }) else { return }

                withAnimation(.easeInOut) {
                    switch guestId {
                    case -2: games[index].guest2Name = guestName
                    case -3: games[index].guest3Name = guestName
                    case -4: games[index].guest4Name = guestName
                    default: print("updateGameGuestName: guestId \(guestId) not in -2, -3, -4")
                    }
                }
            }
        } catch {
            print("updateGameGuestName error: \(error)")
        }
    }
    
    //MARK: updateGameTarget used in EditRoundsSheet to change target of game
    func updateGameTarget(gameId: Int, target: Int) async{
        guard let url = URL(string: "\(apiURL)/game/edit_target")
                else { return }
       

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "game_id": gameId,
            "target":target
        ])
        
        do{
            let (data,response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                         (200...299).contains(httpResponse.statusCode) else {
                       print("updateGameTarget failed: \(String(data: data, encoding: .utf8) ?? "")")
                //fetch the updated game
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                guard let sentGameId = json?["game_id"] as? Int,let sentTarget = json?["target"] as? Int
                else {
                    print("changeTarget answer not in correct format")
                    return
                }
                await MainActor.run {
                    if let index = self.games.firstIndex(where: { $0.id == sentGameId }) {
                        withAnimation(.easeInOut) {
                            self.games[index].target = sentTarget
                        }
                    }
                }
                       return
                   }
            
            
        }catch{
            print("updateGameTarget error: \(error)")
        }
    }

    //MARK: addRound used in AddRoundsSheetView, GameSummaryListView, AddRoundSheetViewLocal, EditRoundsSheetView and PlayView
    func addRound(
        gameId: Int,
        roundOrder: Int = 1,
        firstProfileId: Int? = nil,
        secondProfileId: Int? = nil,
        thirdProfileId: Int? = nil,
        fourthProfileId: Int? = nil,
        firstBombs: Int = 0,
        secondBombs: Int = 0,
        thirdBombs: Int = 0,
        fourthBombs: Int = 0,
        tichuPointsTeam1: Int = 50,
        tichuPointsTeam2: Int = 50,
        roundPointsTeam1: Int = 0,
        roundPointsTeam2: Int = 0,
        doubleWinTeam1: Bool = false,
        doubleWinTeam2: Bool = false,
        announcedTichu: [Int] = [],
        announcedBigTichu: [Int] = [],
        announcedPingu: [Int] = []
    ) async -> Round? {
        guard let url = URL(string: "\(apiURL)/add_round") else { return nil }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "game_id": gameId,
            "round_order": roundOrder,
            "first_profile_id": firstProfileId as Any,
            "second_profile_id": secondProfileId as Any,
            "third_profile_id": thirdProfileId as Any,
            "fourth_profile_id": fourthProfileId as Any,
            "first_bombs": firstBombs,
            "second_bombs": secondBombs,
            "third_bombs": thirdBombs,
            "fourth_bombs": fourthBombs,
            "tichu_points_team1": tichuPointsTeam1,
            "tichu_points_team2": tichuPointsTeam2,
            "round_points_team1": roundPointsTeam1,
            "round_points_team2": roundPointsTeam2,
            "double_win_team1": doubleWinTeam1,
            "double_win_team2": doubleWinTeam2,
            "announced_tichu": announcedTichu,
            "announced_big_tichu": announcedBigTichu,
            "announced_pingu": announcedPingu
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let round = try flexibleDateDecoder.decode(Round.self, from: data)
            await MainActor.run {
                var list = self.roundsByGame[gameId] ?? []
                list.append(round)
                list.sort { $0.roundOrder < $1.roundOrder }
                self.roundsByGame[gameId] = list
            }
            return round
        } catch {
            print("addRound error: \(error)")
            return nil
        }
    }
    
    //MARK: fetchGameRounds used in SocketService, GameSummaryListview, EditRoundsSheetView, HistoryView and PlayView
    func fetchGameRounds(gameId: Int, isLoading: Binding<Bool> = .constant(true)) async {
        guard let url = URL(string: "\(apiURL)/game/\(gameId)/rounds") else { return }

        isLoading.wrappedValue = true
        defer { isLoading.wrappedValue = false }

        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))

            nonisolated struct Response: Decodable {
                let gameId: Int
                let rounds: [Round]
            }

            let decoded = try await Task.detached(priority: .userInitiated) { [decoder = self.flexibleDateDecoder] in
                try decoder.decode(Response.self, from: data)
            }.value

            await MainActor.run {
                self.roundsByGame[gameId] = decoded.rounds   // [] is stored too

                let defaults = UserDefaults(suiteName: "group.com.drakynem.tichu")
                if let existing = defaults?.data(forKey: "widgetGames"),
                   var widgetGames = try? JSONDecoder().decode([WidgetGameData].self, from: existing),
                   let index = widgetGames.firstIndex(where: { $0.id == gameId }) {
                    widgetGames[index] = WidgetGameData(
                        winner: widgetGames[index].winner,
                        favorite: widgetGames[index].favorite,
                        id: widgetGames[index].id,
                        date: widgetGames[index].date,
                        team1Score: widgetGames[index].team1Score,
                        team2Score: widgetGames[index].team2Score,
                        rounds: decoded.rounds.map { WidgetRound(from: $0) }
                    )
                    if let encoded = try? JSONEncoder().encode(widgetGames) {
                        defaults?.set(encoded, forKey: "widgetGames")
                        WidgetCenter.shared.reloadTimelines(ofKind: "favGameWidget")
                    }
                }
            }
        } catch {
            print("fetchGameRounds error: \(error)")
        }
    }
    
    
    //MARK: editRound used in AddRoundsSheetView, EditRoundsSheetView and PlayView
    func editRound(roundId: Int, updates: [String: Any]) async {
        guard let url = URL(string: "\(apiURL)/edit_round/\(roundId)") else { return }

        var request = authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: updates)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let updated = try flexibleDateDecoder.decode(Round.self, from: data)
            await MainActor.run {
                for (gameId, rounds) in self.roundsByGame {
                    if let index = rounds.firstIndex(where: { $0.id == roundId }) {
                        var updatedRounds = rounds
                        updatedRounds[index] = updated
                        withAnimation(.easeInOut){
                            self.roundsByGame[gameId] = updatedRounds
                        }
                        
                        break
                    }
                }
            }
        } catch {
            print("editRound error: \(error)")
        }
    }
    
    //MARK: UpdateGameFavorite (Local change only there is no server here) used in GameSummarySheetView and HistroyView
    func updateGameFavorite(gameId: Int, favorite: Bool) async {
        await MainActor.run {
            favDic[gameId] = favorite ? 1 : 0

            if let index = self.games.firstIndex(where: { $0.id == gameId }) {
                self.games[index].favorite = favorite
            }

            let defaults = UserDefaults(suiteName: "group.com.drakynem.tichu")
            guard let existing = defaults?.data(forKey: "widgetGames"),
                  var widgetGames = try? JSONDecoder().decode([WidgetGameData].self, from: existing),
                  let index = widgetGames.firstIndex(where: { $0.id == gameId }) else { return }

            widgetGames[index].favorite = favorite

            if let encoded = try? JSONEncoder().encode(widgetGames) {
                defaults?.set(encoded, forKey: "widgetGames")
                WidgetCenter.shared.reloadTimelines(ofKind: "favGameWidget")
            }
        }
    }

    //MARK: finishGame used in SocketService and PlayView
    func finishGame(gameId: Int, tie: Bool = false) async {
        guard let url = URL(string: "\(apiURL)/finish_game") else { return }

        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "game_id": gameId,
            "tie":tie
        ])
        print("FINSIH GAME MIT game_id: \(gameId) und tie: \(tie)")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        } catch {
            print("finishGame error: \(error)")
        }
    }
    
    //MARK: deleteRound used in GameSummaryListView and EditRoundsSheetview
    func deleteRound(gameId: Int, roundId: Int) async {
        guard let url = URL(string: "\(apiURL)/delete_round/\(roundId)") else { return }

        let request = authorizedRequest(url: url, method: "DELETE")

        do {
            _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                withAnimation(.easeInOut){
                    self.roundsByGame[gameId]?.removeAll { $0.id == roundId }
                }
            }
        } catch {
            print("deleteRound error: \(error)")
        }
    }
    
    //MARK: editGamePlayer not being used
    func editGamePlayer(gameId: Int, playerSlot: Int) async {
        let slotMap = [
            1: "team1_player1_id",
            2: "team1_player2_id",
            3: "team2_player1_id",
            4: "team2_player2_id"
        ]

        guard let field = slotMap[playerSlot] else {
            print("editGamePlayer: invalid slot \(playerSlot)")
            return
        }

        guard let url = URL(string: "\(apiURL)/game/edit_player/\(gameId)") else { return }

        var request = authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [field: NSNull()])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let updated = try flexibleDateDecoder.decode(Game.self, from: data)
            await MainActor.run {
                if let index = self.games.firstIndex(where: { $0.id == gameId }) {
                    self.games[index] = updated
                }
            }
        } catch {
            print("editGamePlayer error: \(error)")
        }
    }
    
    //MARK: reCalculate used in GameSumamryListView, AddRoundSheetView, EditRoundsSheetView and DebugSheetView
    func reCalculate(gameId: Int, tie: Bool = false) async {
        guard let url = URL(string: "\(apiURL)/recalculate_game") else { return }

        var request = authorizedRequest(url: url, method: "POST")
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "game_id": gameId,
            "tie":tie
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard
                let responseGameId = json?["game_id"] as? Int,
                let team1 = json?["current_points_team1"] as? Int,
                let team2 = json?["current_points_team2"] as? Int
            else {
                print("reCalculate: invalid response format")
                return
            }

            await MainActor.run {
                if let index = self.games.firstIndex(where: { $0.id == responseGameId }) {
                    withAnimation(.easeInOut) {
                        self.games[index].currentPointsTeam1 = team1
                        self.games[index].currentPointsTeam2 = team2
                    }
                }
            }
        } catch {
            print("reCalculate error: \(error)")
        }
    }
    
    //MARK: fetchEloHistory used in SocketService and EloHistoryChart
    func fetchEloHistory(profileId: Int) async {
        guard let url = URL(string: "\(apiURL)/elo_history/\(profileId)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let decoded = try await Task.detached(priority: .userInitiated) { [decoder = self.flexibleDateDecoder] in
                try decoder.decode([EloHistoryEntry].self, from: data)
            }.value

            let defaults = UserDefaults(suiteName: "group.com.drakynem.tichu")
            if let encoded = try? JSONEncoder().encode(decoded) {
                defaults?.set(encoded, forKey: "eloHistory")
                defaults?.set(self.userName, forKey: "userName")
                defaults?.set(self.userElo, forKey: "userElo")
            }

            WidgetCenter.shared.reloadAllTimelines()

            await MainActor.run {
                self.eloHistory = decoded
            }
        } catch {
            print("fetchEloHistory error: \(error)")
        }
    }
    
//MARK: - Export Section
    
    //MARK: fetchExportData used in BackgroundTaskService
    func fetchExportData(profileId: Int,exportProfile: Bool, exportSettings: Bool, exportFriends: Bool, exportGames: Bool, exportEloHistory: Bool, exportStatsHistory: Bool,fullStatsHistory: Bool, progress: Progress? = nil) async throws -> Data {
        guard let url = URL(string: "\(apiURL)/export") else {
            throw URLError(.badURL)
        }

        var request = authorizedRequest(url: url, method: "POST")
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "profile_id": profileId,
            "export_profile":exportProfile,
            "export_settings":exportSettings,
            "export_friends":exportSettings,
            "export_games":exportGames,
            "export_elo_history":exportEloHistory,
            "export_stats_history":exportStatsHistory,
            "full_stats_history": fullStatsHistory
        ])

        let downloader = ExportDownloader(progress: progress)
        let fileURL = try await downloader.download(request)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try Task.checkCancellation()
        return try Data(contentsOf: fileURL)
    }
}
