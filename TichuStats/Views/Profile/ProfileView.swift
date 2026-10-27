//
//  ProfileView.swift
//  TichuStats
//
//  Created by Leon on 21.04.2026.
//

import SwiftUI


struct ProfileView: View {
    // MARK: Storage
    @AppStorage("userId") var userId: Int = -69420
    @AppStorage("userImageData") var userImageData: Data?
    @AppStorage("userName") var userName: String = "Unknown"
    @AppStorage("userElo") var userElo: Double = 404
    @AppStorage("selectedTab") private var selectedTab = 0
    
    //MARK: Observed and Environment
    @ObservedObject private var network = NetworkService.shared
    @StateObject private var socket = SocketService.shared
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var profileSpace
    
    // MARK: Photo Picker
    @State private var showImageCropper: Bool = false
    @State private var croppedImage: UIImage?
    @State private var isUploadingImage: Bool = false
    
    // MARK: Sheet & Alert Presentation
    @State private var showNameSheet: Bool = false
    @State private var showFriendsSheet: Bool = false
    @State private var showPrivacyAlert: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var showOfflineAlert: Bool = false
    @State private var showImageFailAlert: Bool = false
    @State private var isAddingPasskey: Bool = false
    @State private var showAddPasskeyError: Bool = false
    @State private var addPasskeyErrorMessage: String?
    @State private var chosenName: String = ""
    
    //MARK: Export Variables
    @State private var exportProfile: Bool = true
    @State private var exportSettings: Bool = false
    @State private var exportFriends: Bool = false
    @State private var exportGames: Bool = true
    @State private var exportEloHistory: Bool = true
    @State private var exportStatsHistory: Bool = false
    @State private var fullStatsHistory: Bool = false
    
    private func uploadImage(_ image: UIImage) {
        guard let data = image.pngData() else {
            showImageFailAlert = true
            croppedImage = nil
            return
        }

        isUploadingImage = true
        Task {
            await network.uploadProfileImage(profileId: userId, imageData: data)
            isUploadingImage = false
            croppedImage = nil
        }
    }
    

    // MARK: Body
    var body: some View {
        NavigationStack {
            //MARK: Main List
            List {
                profileHeaderSection
                accountSection
                supportSection
                authSection
                deleteAccountSection
                footerSection
            }.alert(isPresented:$showOfflineAlert){
                OfflineView.offlineAlert()
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .animation(.easeInOut, value: network.isOnline)
            .padding(.top, -10)
            .navigationTitle(String(localized: "profile.title"))
            .toolbarTitleDisplayMode(.inlineLarge)
            // navigationDestination must live inside the NavigationStack
            .navigationDestination(isPresented: $showFriendsSheet) {
                EditFriendsSheetView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFriendsSheet)) { _ in
            if network.isOnline{
                showFriendsSheet = true
            }
        }
    }

    // MARK: - Profile Header
    private var profileHeaderSection: some View {
        HStack {
            Spacer()
            VStack {
                ZStack {
                    ZStack{
                        ProfileImage(data: userImageData, size: 100)
                            .shadow(radius: 10)
                            .allowsHitTesting(false)
                        if isUploadingImage{
                            ProgressView().scaleEffect(2)
                        }
                    }
                    Button {
                        showImageCropper = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                            .foregroundColor(.primary)
                            .glassEffect(.regular.interactive())
                            .offset(y: 32)
                    }
                    .disabled(!network.isOnline)
                    .alert(isPresented: $showImageFailAlert) {
                        Alert(
                            title: Text(String(localized: "profile.header.imageUploadFail.title")),
                            message: Text(String(localized: "profile.header.imageUploadFail.message")),
                            dismissButton: .default(Text(String(localized: "profile.header.imageUploadFail.dismiss")))
                        )
                    }
                }
                Text("\(userName)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .allowsHitTesting(false)
                Text("\(Int(userElo))")
                    .foregroundStyle(.gray)
                    .fontWeight(.bold)
                    .allowsHitTesting(false)
            }
            Spacer()
        }
        .listRowBackground(Color.clear)
        .imageCropPicker(
            isPresented: $showImageCropper,
            croppedImage: $croppedImage
        )
        .onChange(of: croppedImage) {
            if let image = croppedImage{
                uploadImage(image)
                }
        }
    }

    // MARK: - Account Section
    private var accountSection: some View {
        Section {
            
            //MARK: General
            NavigationLink {
                    GameSettingsView()
            } label: {
                Label(String(localized: "profile.section.account.general"), systemImage: "gear")
                    .labelStyle(ColorfulIconLabelStyle(color: .gray, fontSize: 14))
            }
            //MARK: Edit Username
            NavigationLink {
                EditNameSheetView(editMode: true,showLoginSheet:.constant(false),signIn:.constant(false),chosenName:$chosenName)
            } label: {
                HStack {
                    Label(String(localized: "profile.section.account.editUsername"), systemImage: "person.fill")
                        .labelStyle(ColorfulIconLabelStyle(color: .accent, fontSize: 17))
                    Spacer()
                }
            }
            .disabled(!network.isOnline)
            .foregroundColor(network.isOnline ? .primary : .secondary)
            
            //MARK: Manage Friends
            NavigationLink {
                EditFriendsSheetView().onDisappear {
                    Task {
                        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
                        let toRemove = delivered
                            .compactMap { $0.request.content.userInfo["notification_id"] as? String }
                            .filter { $0.hasPrefix("friend-request-accepted-") }
                        
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove)
                        try? await UNUserNotificationCenter.current().setBadgeCount(network.friendRequests.count)
                    }
                }
            } label: {
                HStack {
                    Label(String(localized: "profile.section.account.manageFriends"), systemImage: "person.2.fill")
                        .labelStyle(ColorfulIconLabelStyle(color: .accent, fontSize: 13))
                    Spacer()
                    if network.friendRequestProfiles.count > 0 {
                        Text("\(network.friendRequestProfiles.count)")
                            .foregroundStyle(.white)
                            .background {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 24, height: 24)
                            }
                            .padding(.trailing)
                    }
                }
            }.disabled(!network.isOnline)
            .foregroundColor(network.isOnline ? .primary : .secondary)
            
        }
    }

    // MARK: - Support Section
    private var supportSection: some View {
        Section {
            //MARK: Privacy
            
            Button {
                withAnimation(.easeInOut(duration: 0.285)) {
                    showPrivacyAlert = true
                }
            } label: {
                HStack {
                    Label(String(localized: "profile.section.support.privacy"), systemImage: "hand.raised.fill")
                        .labelStyle(ColorfulIconLabelStyle(color: .blue, fontSize: 15))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.trailing,1.2)
                        .rotationEffect(.degrees(showPrivacyAlert ? 90 : 0))
                }
            }
            .foregroundColor(.primary)
            .alert(String(localized: "profile.section.support.privacy.alert.title"), isPresented: $showPrivacyAlert) {
                Button(role:.confirm){
                    if let url = PDFKitView.resolveGeneralURL(urlDomain:getURL(front:true),urlString:"/privacy") {
                        UIApplication.shared.open(url)
                    }
                }label:{
                    Text(String(localized: "profile.section.support.privacy.alert.readPrivacy"))
                }
                Button(role: .cancel) {
                    withAnimation(.easeInOut(duration: 0.285)) {
                        showPrivacyAlert = false
                    }
                } label: {
                    Text(String(localized: "offline.alertDissmiss"))
                }
            } message: {
                Text(String(localized: "profile.section.support.privacy.alert.message"))
            }
            
            //MARK: Contact
            Button {
                let subject = String(localized:"profile.tichuStatsSupport")
                let osVersion = ProcessInfo.processInfo.operatingSystemVersion
                let iosVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
                let iosBuild = ProcessInfo.processInfo.operatingSystemVersionString
                    .components(separatedBy: " ")
                    .last?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()")) ?? String(localized: "general.unknown")
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? String(localized: "general.unknown")
                let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? String(localized: "general.unknown")

                let body = """
                    
                    
                    
                    App Version: \(appVersion) (\(buildNumber))
                    iOS: \(iosVersion) (\(iosBuild))
                    Device: \(DeviceModelName())
                    User ID: \(userId)356af6d-ec96-49e1-a7e8-e372ce3c6363
                    """
                let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "mailto:leon@tichu.dev?subject=\(encodedSubject)&body=\(encodedBody)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Label(String(localized: "profile.section.support.contact"), systemImage: "envelope.fill")
                        .labelStyle(ColorfulIconLabelStyle(color: .blue, fontSize: 14))
                }
                .foregroundStyle(Color.primary)
            }.foregroundColor(.primary)

            Button {
                if let url = URL(string: "https://github.com/LeonHTM/Tichu") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(String(localized: "profile.section.support.sourceCode"), image: "github")
                    .labelStyle(ColorfulIconLabelStyle(color: .black, fontSize: 17))
            }
            .foregroundColor(.primary)
            Button{
                Task {
                    isAddingPasskey = true
                    defer { isAddingPasskey = false }
                    do {
                        try await network.addPasskeyToAccount()
                    } catch PasskeyError.cancelled {
                        // backed out of Face ID sheet — no-op
                    } catch PasskeyError.server(let code) {
                        addPasskeyErrorMessage = code == "challenge_expired"
                        ? String(localized:"passKeyError.expired")
                        : String(localized:"passKeyError.notAdd")
                        showAddPasskeyError = true
                    } catch {
                        addPasskeyErrorMessage = String(localized:"passKeyError.expired")
                        showAddPasskeyError = true
                    }
                }
            }label:{
                HStack {
                    
                    Label(String(localized:"profile.section.support.passKey"), systemImage:"person.badge.key.fill")
                            .labelStyle(ColorfulIconLabelStyle(color: .green, fontSize: 13))
                    Spacer()
                    if isAddingPasskey {
                        ProgressView()
                    }
                    
                }
            }
            .disabled(!network.isOnline || isAddingPasskey)
            .foregroundStyle(Color.primary)
            .alert(String(localized:"passKeyError.general"), isPresented: $showAddPasskeyError, presenting: addPasskeyErrorMessage) { _ in
                Button(String(localized:"general.alert.ok"), role: .cancel) {}
            } message: { message in
                Text(message)
            }
            
            //MARK: Export Data
            NavigationLink{
                ExportDataView(exportProfile:$exportProfile,exportSettings:$exportSettings,exportFriends: $exportFriends,exportGames: $exportGames,exportEloHistory: $exportEloHistory,exportStatsHistory: $exportStatsHistory,fullStatsHistory: $fullStatsHistory)
                }label: {
                HStack {
                    Label(String(localized:"export.title.data"), systemImage: "arrow.down.circle.fill")
                        .labelStyle(ColorfulIconLabelStyle(color: .gray, fontSize: 13))
                }
            }
        }
    }

    // MARK: - Auth Section
    private var authSection: some View {
        Section {
            //MARK: Log Out
            Button {
                withAnimation(.easeInOut(duration: 0.285)) {
                    if network.isOnline {
                        Task {
                            await network.logout(profileId: userId)
                        }
                    } else {
                        showOfflineAlert = true
                    }
                }
            } label: {
                HStack {
                    Label(String(localized: "profile.section.auth.logOut"), systemImage: "rectangle.portrait.and.arrow.right.fill")
                        .labelStyle(ColorfulIconLabelStyle(color: .accentColor, fontSize: 13))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.trailing,1.2)
                      
                }
                .foregroundColor(network.isOnline ? .primary : .secondary)
            }
        }
    }

    // MARK: - Delete Account Section
    private var deleteAccountSection: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.285)) {
                    if network.isOnline {
                        showDeleteAlert = true
                    } else {
                        showOfflineAlert = true
                    }
                }
            } label: {
                HStack {
                    Label(String(localized: "profile.section.deleteAccount.delete"), systemImage: "trash.fill")
                        .labelStyle(ColorfulIconLabelStyle(color: .red, fontSize: 14))
                        .foregroundStyle(.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.trailing,1.2)
                        .rotationEffect(.degrees(showDeleteAlert ? 90 : 0))
                }
            }
            .foregroundStyle(.secondary)
            .alert(String(localized: "profile.section.deleteAccount.alert.title"), isPresented: $showDeleteAlert) {
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.285)) {
                        Task {
                            await network.deleteProfile(profileId: userId)
                        }
                        showDeleteAlert = false
                    }
                } label: {
                    Text(String(localized: "profile.section.deleteAccount.alert.confirm"))
                }
                Button(role: .cancel) {
                    withAnimation(.easeInOut(duration: 0.285)) {
                        showDeleteAlert = false
                    }
                }
            } message: {
                Text(String(localized: "profile.section.deleteAccount.alert.message"))
            }
        }
    }

    // MARK: Footer
    private var footerSection: some View {
        HStack {
            Spacer()
            VStack {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text(String(localized: "profile.footer.madeWith"))
                    Text(String(format: String(localized: "profile.footer.version"), version, build))
                        .foregroundStyle(.gray)
                }
            }
            Spacer()
        }
        .listRowBackground(Color.clear)
    }
}



#Preview {
    ProfileView()
}
