//
//  LoginSheetView.swift
//  TichuStats
//
//  Created by Leon on 06.09.2026.
//

import SwiftUI



struct LoginSheetView: View{
    @Binding var showLoginSheet:Bool
    @Binding var showCodeView: Bool
    @Binding var signIn: Bool
    @Binding var firstAppear: Bool
    @Binding var userEmail: String
    var chosenName: String = ""

    
    // MARK: - State
    @StateObject private var socket = SocketService.shared
    @ObservedObject private var network = NetworkService.shared
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isEmailFocused: Bool
    @State private var isChecking:Bool = false
    @State private var emailExists: Bool = false
    @State private var showOfflineAlert: Bool = false
    @State private var isPasskeyLoading: Bool = false
    @State private var passkeyErrorMessage: String?
    @State private var showPasskeyError: Bool = false
    @State private var mailNotExists: Bool = false
    @State private var mailLegit: Bool = true
      
    //MARK: Check if mail is valid: somthing@something.somthing
    private func isValidEmail(_ email: String) -> Bool {
            let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
            return email.range(of: pattern, options: .regularExpression) != nil
        }
    

    // MARK: - Email Field
    private var emailField: some View {
        HStack {
            if !mailLegit || mailNotExists{
                Image("envelope.exclamation").foregroundStyle(Color.red)
                    .foregroundColor(.secondary)
                    .padding(.leading)
                    .offset(y:2)
            }else{
                Image(systemName: "envelope.fill")
                    .foregroundColor(.secondary)
                    .padding(.leading)
            }

            TextField("\(String(localized:"general.mailPlaceholder"))", text: $userEmail)
                /*.foregroundStyle(!mailLegit || mailNotExists ? Color.red : .primary)*/
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
                .foregroundColor(.primary)
                .focused($isEmailFocused)
                .alert(isPresented:$showOfflineAlert){
                    OfflineView.offlineAlert()
                }
                .onAppear{
                    if !firstAppear{
                        isEmailFocused = true
                    }
                }
                .onChange(of: userEmail) {

                    if network.isOnline{
                        isChecking = true
                        Task {
                            emailExists = await network.checkEmail(email: userEmail)
                            isChecking = false
                        }
                    }
                    }
                

            Spacer()
            
            ZStack {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .opacity(0) // always reserves the space

                if isChecking {
                    ProgressView()
                } else {
                    if network.isOnline && socket.connected {
                        
                        Button{
                            withAnimation(.easeInOut){
                                mailLegit = isValidEmail(userEmail)
                            }
                            if mailLegit{
                                //If users does not sign up meaning he signs in
                                if signIn{
                                    //then the mail has to exist
                                    if !emailExists {
                                        withAnimation(.easeInOut){
                                            mailNotExists = true
                                        }
                                    }else{
                                        Task{
                                            showCodeView = true
                                            _ = await network.sendMail(mail: userEmail)
                                        }
                                    }
                                }else{
                                    Task{
                                        showCodeView = true
                                        _ = await network.sendMail(mail: userEmail)
                                    }
                                }
                            }
                            

                        }label:{
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        Button {
                            showOfflineAlert = true
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.vertical, 13)
        .glassEffect(.regular.tint(.secondary.opacity(0.2)).interactive())
    }
    
    private func passKeySignInButton() -> some View {
        Button {
            Task { await handlePasskeyTap(signIn: signIn) }
        } label: {
            HStack{
                Spacer()
                if isPasskeyLoading {
                    ProgressView()
                        .tint(colorScheme == .light ? Color.white : Color.black)
                } else {
                    Image(systemName:"person.badge.key.fill")
                    Text(String(localized:signIn ? "login.signInPasskey" : "login.signUpPasskey"))
                }
                Spacer()
            }.fontWeight(.semibold).font(.system(size: 18)).foregroundStyle(colorScheme == .light ? Color.white : Color.black).backgroundStyle(Color.black).frame(height: 50).clipShape(RoundedRectangle(cornerRadius: 24))
                .glassEffect(.regular.tint(colorScheme == .light ? .black : .white).interactive())
        }
        .disabled(isChecking || isPasskeyLoading)
    }

    // MARK: - Passkey Tap Handler
    private func handlePasskeyTap(signIn: Bool) async {
        guard network.isOnline else {
            showOfflineAlert = true
            return
        }

        isPasskeyLoading = true
        defer { isPasskeyLoading = false }

        
        do{
            if signIn == true{
                _ = try await network.signInWithPasskey(email: userEmail)
            } else if !chosenName.isEmpty {
                _ = try await network.signUpWithPasskey(name: chosenName,mail:userEmail)
                showLoginSheet = false
            } else {
                print("LOGIN ChosenNAME ERROR: \(chosenName)")
                showPasskeyError = true
                return
            }
        }catch PasskeyError.cancelled {
            
        } catch PasskeyError.server(let code) {
            passkeyErrorMessage = friendlyMessage(for: code)
            showPasskeyError = true
        } catch {
            passkeyErrorMessage =  String(localized:"passKeyError.general")
            showPasskeyError = true
        }
        
    }

    private func friendlyMessage(for code: String) -> String {
        switch code {
        case "challenge_expired":
            return String(localized:"passKeyError.expired")
        case "unknown_credential", "unknown_user":
            return String(localized:"passKeyError.unknown")
        case "verification_failed":
            return String(localized:"passKeyError.verfication")
        default:
            return String(localized:"passKeyError.general")
        }
    }
    var body: some View {
        NavigationStack{
            GlassEffectContainer {
                Spacer()
                
                VStack {
                    Text("")
                    passKeySignInButton()
                   
                    
                    HStack {
                        Spacer()
                        Text(String(localized: "login.or"))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    emailField
                    HStack{
                        
                        
                        if !mailLegit{
                            
                            Text(String(localized:"login.mail.enterValid")).foregroundStyle(Color.red)
                            
                            
                        }else if mailNotExists{

                            Text(String(localized:"login.mail.incorrect")).foregroundStyle(Color.red)
                                
                            
                            
                        }else{
                            Text(" ")
                        }
                        Spacer()
                    }.padding(.leading,17)
                    
                    
                }
                
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            
            .alert(String(localized:"passKeyError.failed.signIn"), isPresented: $showPasskeyError, presenting: passkeyErrorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }
}


struct CodeView: View {
    @Binding var userEmail: String
    @Binding var showCodeView: Bool
    @Binding var showLoginSheet: Bool
    @Binding var firstAppear: Bool
    @Binding var userName: String
    @State private var isLoading: Bool = false
    @State private var code: String = ""
    @State private var valid: Bool = false
    @ObservedObject private var network = NetworkService.shared

    var body: some View {
        VStack {
            VStack {
                VerficationField(
                    type: .six,
                    style: .roundedBorder,
                    value: $code
                ) { result in
                    guard result.count == 6 else { return .typing }

                    isLoading = true
                    let success = await network.verifyLoginCode(mail: userEmail, code: result, name: userName)
                    isLoading = false

                    return success ? .valid : .invalid
                }
            }
            GlassEffectContainer{
                VStack{
                    Button{
                        Task{
                            _ = await network.sendMail(mail: userEmail)
                        }
                    }label: {
                        Text(String(localized:"login.resendEmail")).frame(maxWidth: .infinity).padding(.horizontal)
                    }.buttonStyle(GlassButtonStyle())
                    Button{
                        showCodeView = false
                    }label:{
                        Text(String(localized:"login.differentEmail")).padding(.horizontal).frame(maxWidth: .infinity)
                    }.buttonStyle(GlassButtonStyle())
                }.padding(.top,40).padding(.horizontal,85)
                    .onAppear {
                        firstAppear = false
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        
    }
}
