//
//  NotificationHelper.swift
// TichuStatsNotificationService
//
//  Created by Leon on 18.05.2026.
//

import SwiftUI
import UserNotifications

extension Notification.Name {
    static let didTapPushNotification = Notification.Name("didTapPushNotification")
    static let openFriendsSheet = Notification.Name("openFriendsSheet")
    static let openGame = Notification.Name("openGame")
}

@MainActor
class CustomAppDelegate: NSObject, UIApplicationDelegate {
    var app: TichuStats?
    var onDeviceToken: ((String) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map {
            String(format: "%02.2hhx", $0)
        }.joined()

        print("APNs token:", token)

        UserDefaults.standard.set(token, forKey: "pendingDeviceToken")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications:", error)
    }
}

extension CustomAppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {

        let userInfo = response.notification.request.content.userInfo

        // Game pushes: open the game directly
        if userInfo["type"] as? String == "game_added",
           let gameId = userInfo["game_id"] as? Int {
            NotificationCenter.default.post(
                name: .openGame,
                object: nil,
                userInfo: ["game_id": gameId]
            )
            return
        }

        // Everything else (friend requests etc.)
        NotificationCenter.default.post(
            name: .didTapPushNotification,
            object: nil,
            userInfo: userInfo as? [String: Any]
        )
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.badge, .banner, .list, .sound]
    }
}

func removeFriendRequestNotification(fromSenderId senderId: Int) {
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
        let toRemove = notifications
            .filter { notification in
                let userInfo = notification.request.content.userInfo
                let id = userInfo["sender_id"] as? String
                let type = userInfo["type"] as? String
                // Don't clear game notifications from the same sender
                return id == String(senderId) && type != "game_added"
            }
            .map { $0.request.identifier }

        print("Removing notifications: \(toRemove)")
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove)
    }
}
