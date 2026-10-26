//
//  SmallHelpers.swift
//  TichuStats
//
//  Created by Leon on 25.04.2026.
//

import SwiftUI

//MARK: - RequirementRow used in EditNameSheet
@ViewBuilder
func requirementRow(
    text: String,
    isValid: Bool
) -> some View {
    HStack(spacing: 10) {
        Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
        Text(text)
        Spacer()
    }
    .foregroundStyle(isValid ? .green : .red)
}

//MARK: - Reusable glossy icon background styling
struct GlossyIconBackground: ViewModifier {
    var color: Color
    var cornerRadius: CGFloat = 7

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color)
                    // Top light gloss
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.45),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .blendMode(.overlay)
                            )
                    )
                    // Subtle glossy border
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.15),
                                        .clear,
                                        .clear,
                                        .white.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    // Depth shadow
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            )
    }
}

extension View {
    func glossyIconBackground(color: Color, cornerRadius: CGFloat = 7) -> some View {
        modifier(GlossyIconBackground(color: color, cornerRadius: cornerRadius))
    }
}

//MARK: - LabelStyle used in ProfilesView
struct ColorfulIconLabelStyle: LabelStyle {
    //MARK: Varibles
    var color: Color
    var fontSize: CGFloat
    //MARK: Function
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
        } icon: {
            configuration.icon
                .font(.system(size: fontSize))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .glossyIconBackground(color: color)
        }
    }
}


struct OfflineView: View{
    //MARK: Variables
    @Binding  var showNavBar: Bool
    @AppStorage("userId") private var userId = -69420
    var title: String.LocalizationValue = "general.title.play"
    
    //MARK: Body
    var body: some View{
        NavigationStack{
            VStack(alignment:.center,spacing:10){
                //Offline Text
                Spacer()
                Text(String(localized:"offline.title")).font(.title2).fontWeight(.bold)
                Text(String(localized:"offline.description")).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal,40)
               Spacer()
                VStack(alignment:.leading){
                    Text(String(localized: "gamesettings.section.howToPlay")).font(.headline).foregroundStyle(Color(.gray)).padding(.leading,28)
                    NavigationLink{
                        TichuRulesPDFView()
                    }label:{
                        HStack(alignment: .center,spacing:15){
                            Image(systemName:"book.fill").font(.system(size: 18))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .glossyIconBackground(color: .green)
                            Text(String(localized:"gamesettings.section.howToPlay.officialRules")).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName:"chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary).padding(.trailing,1.2)
                        }.padding(.horizontal,15).padding(.vertical,12).background(Color(.secondarySystemBackground)).cornerRadius(25).padding(.horizontal,15)
                    }.foregroundStyle(.primary)
                }.padding(.bottom,20)
                
            }.toolbarTitleDisplayMode(.inlineLarge)
                .navigationTitle(showNavBar ? String(localized: title) : "" )
                .toolbar {
                    //Shows NavBar everywhere except LoginView
                    if showNavBar{
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationProfileImage()
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
            }
        }
    //Alert that is used
    static func offlineAlert() -> Alert {
        Alert(
            title: Text(String(localized:"offline.title")),
            message: Text(String(localized:"offline.alert.description")),
            dismissButton: .default(Text(String(localized:"offline.alertDissmiss")))
        )
    }
}


import UIKit

//MARK: - DeviceModelName used in Contact Form to send the Device Model Name for exmaple iPhone 14,5
func DeviceModelName() -> String {
    //Mark: Vars
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    //Mark: Build Identifier
    let identifier = machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
    return identifier
}


//MARK: - BombView used in GameSummaryListView and EditRoundsShettView to show the little Grpahic for the bomb and the counter
func bombView(bomb: Int) -> some View {
    Group {
        if bomb > 0 {
            HStack {
                Image("bomb.fill")
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(.secondary)
                    .frame(width: 15, height: 13)
                    .offset(x: 52)
                Text("\(bomb)").font(.system(size: 13,weight:.bold)).offset(x: 41, y: 7).foregroundStyle(Color.secondary)
            }
        }
    }
}
  
//MARK: - Extension to save Array in AppStorage used to Store the List of Players in StatsView
// Source - https://stackoverflow.com/a/65598711
extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}


//MARK: - Extension to save Dictionaries in AppStorage
extension Dictionary: @retroactive RawRepresentable where Key == Int, Value == Int {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Int: Int].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return result
    }
}


//MARK: - Function to check if user isFriend user in contextMenus in AddPlayersSheetView and PlayView
func isFriend(profileId: Int) -> Bool{
    if NetworkService.shared.friends.first(where:{$0.id == profileId}) == nil{
        return false
    }else{
        return true
    }
}

//MARK: - OnFirstAppear used in StatsVeiw to trigger on on the first Appearance
struct OnFirstAppear: ViewModifier {
    @State private var hasAppeared = false
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            action()
        }
    }
}

extension View {
    func onFirstAppear(_ action: @escaping () -> Void) -> some View {
        modifier(OnFirstAppear(action: action))
    }
}

// MARK: - Safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

//MARK: - Placeholder animations and redacted
public struct Shimmer: ViewModifier {
    @State private var isInitial = true

    public func body(content: Content) -> some View {
        content
            .mask(
                LinearGradient(
                    colors: [.black.opacity(0.4), .black, .black.opacity(0.4)],
                    startPoint: isInitial ? UnitPoint(x: -0.3, y: -0.3) : UnitPoint(x: 1, y: 1),
                    endPoint: isInitial ? UnitPoint(x: 0, y: 0) : UnitPoint(x: 1.3, y: 1.3)
                )
            )
            .animation(.linear(duration: 1.25).delay(0.25).repeatForever(autoreverses: false), value: isInitial)
            .onAppear { isInitial = false }
    }
}

public struct RedactedShimmer: ViewModifier {
    @AppStorage("isLoading") private var isLoading = false

    public func body(content: Content) -> some View {
        ZStack {
            if isLoading {
                content
                    .redacted(reason: .placeholder)
                    .modifier(Shimmer())
            } else {
                content
            }
        }
        .animation(.easeInOut, value: isLoading)
    }
}

public struct RedactedShimmerConstant: ViewModifier {
    public func body(content: Content) -> some View {
                content
                    .redacted(reason: .placeholder)
                    .modifier(Shimmer())
          
    }
}

public extension View {
    func redactedShimmer() -> some View {
        modifier(RedactedShimmer())
    }
    func redactedShimmerConstant() -> some View {
        modifier(RedactedShimmerConstant())
    }
}

func getURL(dev:Bool = false,auth:Bool = false,front:Bool = false) -> String{
    if dev{
        //DEVELOPMENT URL
        guard let host = Bundle.main.object(forInfoDictionaryKey: "DEV_API_URL") as? String,
              !host.isEmpty else {
            return "https://0.0.0.0"
        }
        //http here
        if auth{
            return host
        }else{
            return "http://" + host
        }
        
    
    } else if front {
        //PUBLIC URL
        guard let host = Bundle.main.object(forInfoDictionaryKey: "FRONT_URL") as? String,
              !host.isEmpty else {
            return "https://0.0.0.0"
        }
        
        if auth{
            //print("AUTH: \(host)")
            return host
            
        }else{
            //print("REGULAR: https://\(host)")
            return "https://" + host
        }
        
    }else{
        //PRODUCTION URL
        guard let host = Bundle.main.object(forInfoDictionaryKey: "API_URL") as? String,
              !host.isEmpty else {
            return "https://0.0.0.0" 
        }
        //https here
        if auth{
            //print("AUTH: \(host)")
            return host
            
        }else{
            //print("REGULAR: https://\(host)")
            return "https://" + host
        }
        
    }
}

struct NavigationButton<Destination: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let icon: String?
    let primary: Bool
    @Binding var animation: Bool
    let destination: () -> Destination

    init(
        title: String,
        icon: String? = nil,
        primary: Bool = false,
        animation: Binding<Bool> = .constant(true),   // ← default binding, not Bool
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.icon = icon
        self.primary = primary
        self._animation = animation   // ← use _animation to assign the Binding
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Spacer()

                HStack {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                }
                .blurOpacityEffect(animation)

                Spacer()
            }
            .fontWeight(.semibold)
            .font(.system(size: 18))
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .foregroundStyle(primary ? Color.white : colorScheme == .dark ? Color.black : Color.white)
            .glassEffect(primary ? .regular.tint(.accent).interactive() : .regular.tint(colorScheme == .dark ? Color.white : Color.primary).interactive())
        }
    }
}


struct VerficationField: View {
    var type: CodeType
    var style: TextFieldStyle = .roundedBorder
    @Binding var value: String
    var onChange: (String) async -> TypingState
    @State private var state: TypingState = .typing
    @State private var invalidTrigger: Bool = false
    @State private var validTrigger: Bool = false
    @FocusState private var isActive: Bool
    @State private var timer:Timer?
    var body: some View {
        HStack(spacing: style == .roundedBorder ? 6 : 10){
            
            ForEach(0..<type.rawValue, id: \.self) { index in
                CharacterView(index)
            }
        }
        /*.phaseAnimator([0, 10, -10, 10, -5, 5, 0], trigger: invalidTrigger, content: { content, offset in
            content
                .offset(x: offset)
        }, animation: { _ in
                .linear(duration: 0.006)
                
            
        })*/
        .sensoryFeedback(.success, trigger: validTrigger)
        .sensoryFeedback(.error, trigger: invalidTrigger)
        //.animation(.easeInOut(duration:0.1), value: value)
        //.animation(.easeInOut(duration:0.1), value: isActive)
        .compositingGroup()
        
        .background {
            TextField("", text: $value)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .foregroundColor(.clear)
                .tint(.clear)
                .accentColor(.clear)
                .focused($isActive)
                
        }
        .contentShape(.rect)
        .onTapGesture{
            isActive = true
        }
        .onAppear {
            //DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isActive = true
            //}
        }
        .onChange(of: value) { oldValue, newValue in
            if newValue.count > type.rawValue {
                DispatchQueue.main.async {
                    value = String(newValue.prefix(type.rawValue))
                }
            }
            Task {
                let result = await onChange(value)
                state = result
                if state == .invalid { invalidTrigger.toggle() }
                if state == .valid { validTrigger.toggle() }
            }
        }
        
    }
    
    @ViewBuilder
    func CharacterView(_ index: Int) -> some View {
        Group {
            if style == .roundedBorder {
                RoundedRectangle (cornerRadius: 16).stroke(borderColor(index), lineWidth:2).padding(1).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
            }else{
                Rectangle()
                    .fill(borderColor(index))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: style == .roundedBorder ? 50 : 40,height:50)
        .overlay{
            let stringvalue = string(index)
            if stringvalue != "" {
                Text(stringvalue)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .transition(.blurReplace)
            }
            
        }
    }
    
    func string(_ index: Int) -> String {
        if value.count > index {
            let startIndex = value.startIndex
            let stringIndex = value.index(startIndex, offsetBy: index)
            
            return String(value[stringIndex])
        }else{
            
            return ""
        }
        
    }
    func borderColor(_ index: Int) -> Color {
        switch state {
        case .typing: value.count == index && isActive ? Color.primary : .gray
        case .valid: .accentColor
        case .invalid: .red
        }
    }
}
    



enum CodeType: Int, CaseIterable {
    case four = 4
    case six = 6
    
    var stringvalue: String {
        "\(rawValue) Digit"
    }
}

enum TypingState{
    case typing
    case valid
    case invalid
}

enum TextFieldStyle: String, CaseIterable{
    case roundedBorder = "Rounded Border"
    case underlined = "Underlined"
}


func timeFrametoString(timeframe:Timeframe,elo:Bool = false) -> String{
    if elo{
        return String(localized:"statistics.timeframe.sinceDownload")
    }else{
        switch timeframe{
        case .day: return String(localized:"statistics.timeframe.daily")
        case .week: return String(localized:"statistics.timeframe.weekly")
        case .month: return String(localized:"statistics.timeframe.monthly")
        case .year: return String(localized:"statistics.timeframe.yearly")
        case .allTime: return String(localized:"statistics.timeframe.sinceDownload")
        }
    }
 }
