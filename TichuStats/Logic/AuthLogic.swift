//
//  AuthLogic.swift
//  TichuStats
//
//  Created by Leon on 01.09.2026.
//

import AuthenticationServices
import UIKit

struct AuthResult {
    let token: String
    let userId: Int
}

enum PasskeyError: Error {
    case cancelled
    case badServerResponse
    case server(String)
}

final class PasskeyManager: NSObject {

    static let shared = PasskeyManager()

    // RP_ID from Server
    private let relyingPartyIdentifier = getURL(auth:true,front:true)
    private var baseURL: URL = URL(string:getURL(front:true)) ?? URL(string: "https://0.0.0.0")!
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var authController: ASAuthorizationController?

    // MARK: - Public API
    func signUp(name: String,mail: String?) async throws -> AuthResult {
        let options = try await fetchJSON(
            path: "/passkey/register/options",
            body: ["name": name]
        )
        print("Sign Up")

        guard
            let challengeB64 = options["challenge"] as? String,
            let userDict = options["user"] as? [String: Any],
            let userIdB64 = userDict["id"] as? String,
            let userName = userDict["name"] as? String,
            let challengeId = options["challengeId"] as? String
        else {
            throw PasskeyError.badServerResponse
        }
        
        print("challengeB64: \(challengeB64), userDict: \(userDict), challengeId: \(challengeId), userIdB64: \(userIdB64), userName: \(userName)")

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: Data.fromBase64URL(challengeB64),
            name: userName,
            userID: Data.fromBase64URL(userIdB64)
        )
        request.userVerificationPreference = .required

        let authorization = try await performRequests([request])

        guard
            let credential = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
            let attestationObject = credential.rawAttestationObject
        else {
            throw PasskeyError.badServerResponse
        }

        let credentialJSON: [String: Any] = [
            "id": credential.credentialID.toBase64URL(),
            "rawId": credential.credentialID.toBase64URL(),
            "type": "public-key",
            "response": [
                "attestationObject": attestationObject.toBase64URL(),
                "clientDataJSON": credential.rawClientDataJSON.toBase64URL(),
            ],
        ]

        let verifyResponse = try await fetchJSON(
            path: "/passkey/register/verify",
            body: [
                "challengeId": challengeId,
                "credential": credentialJSON,
                "name": name,
            ]
        )
        return try parseAuthResult(verifyResponse)
    }

    //Email is not necessary
    func signIn(email: String?) async throws -> AuthResult {
        var body: [String: Any] = [:]
        if let email { body["email"] = email }

        let options = try await fetchJSON(path: "/passkey/login/options", body: body)

        guard
            let challengeB64 = options["challenge"] as? String,
            let challengeId = options["challengeId"] as? String
        else {
            throw PasskeyError.badServerResponse
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let request = provider.createCredentialAssertionRequest(
            challenge: Data.fromBase64URL(challengeB64)
        )
        request.userVerificationPreference = .required

        let authorization = try await performRequests([request])

        guard
            let credential = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialAssertion
        else {
            throw PasskeyError.badServerResponse
        }

        var response: [String: Any] = [
            "authenticatorData": credential.rawAuthenticatorData.toBase64URL(),
            "clientDataJSON": credential.rawClientDataJSON.toBase64URL(),
            "signature": credential.signature.toBase64URL(),
        ]
        if let userID = credential.userID, !userID.isEmpty {
            response["userHandle"] = userID.toBase64URL()
        }

        let credentialJSON: [String: Any] = [
            "id": credential.credentialID.toBase64URL(),
            "rawId": credential.credentialID.toBase64URL(),
            "type": "public-key",
            "response": response,
        ]

        let verifyResponse = try await fetchJSON(
            path: "/passkey/login/verify",
            body: ["challengeId": challengeId, "credential": credentialJSON]
        )
        return try parseAuthResult(verifyResponse)
    }
    
    // Adds a passkey to an already logged-in account 
    func addPasskey(userToken: String) async throws {
        let timezone = TimeZone.current.identifier
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"

        let options = try await fetchJSON(
            path: "/passkey/add/options",
            body:[:],
            userToken: userToken
        )

        guard
            let challengeB64 = options["challenge"] as? String,
            let userDict = options["user"] as? [String: Any],
            let userIdB64 = userDict["id"] as? String,
            let userName = userDict["name"] as? String,
            let challengeId = options["challengeId"] as? String
        else {
            throw PasskeyError.badServerResponse
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: Data.fromBase64URL(challengeB64),
            name: userName,
            userID: Data.fromBase64URL(userIdB64)
        )
        request.userVerificationPreference = .required

        let authorization = try await performRequests([request])

        guard
            let credential = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
            let attestationObject = credential.rawAttestationObject
        else {
            throw PasskeyError.badServerResponse
        }

        let credentialJSON: [String: Any] = [
            "id": credential.credentialID.toBase64URL(),
            "rawId": credential.credentialID.toBase64URL(),
            "type": "public-key",
            "response": [
                "attestationObject": attestationObject.toBase64URL(),
                "clientDataJSON": credential.rawClientDataJSON.toBase64URL(),
            ],
        ]

        _ = try await fetchJSON(
            path: "/passkey/add/verify",
            body: [
                "challengeId": challengeId,
                "credential": credentialJSON,
                "timezone_str": timezone,
                "language_code": languageCode
            ],
            userToken: userToken
        )
    }

    // MARK: - ASAuthorizationController bridging
    private func performRequests(
        _ requests: [ASAuthorizationRequest]
    ) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            self.authController = controller
            controller.performRequests()
        }
    }

    // MARK: - Networking
    private func fetchJSON(path: String, body: [String: Any], userToken: String? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        if let userToken, !userToken.isEmpty {
            req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        } else if let appToken = Bundle.main.object(forInfoDictionaryKey: "APP_TOKEN") as? String,
           !appToken.isEmpty {
            req.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PasskeyError.badServerResponse
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? nil

        guard (200..<300).contains(http.statusCode) else {
            let message = (json?["error"] as? String) ?? "request_failed"
            throw PasskeyError.server(message)
        }
        guard let json else { throw PasskeyError.badServerResponse }
        return json
    }

    private func parseAuthResult(_ json: [String: Any]) throws -> AuthResult {
        guard
            let token = json["token"] as? String,
            let userId = json["id"] as? Int
        else {
            throw PasskeyError.badServerResponse
        }
        return AuthResult(token: token, userId: userId)
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension PasskeyManager: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: PasskeyError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension PasskeyManager: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            
            return windowScene.windows.first(where: { $0.isKeyWindow })
                ?? ASPresentationAnchor(windowScene: windowScene)
        }

        fatalError("No active UIWindowScene available")
    }
}



// MARK: - base64url helpers
private extension Data {
    static func fromBase64URL(_ string: String) -> Data {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64) ?? Data()
    }

    func toBase64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
