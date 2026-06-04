public import ClerkKit
import Foundation
import Observation

@Observable
@MainActor
public final class AuthService {
    private enum Keys {
        static let guestMode = "auth.guest_mode"
    }

    public enum SignInResult {
        case success
        case accountNotFound
        case needsProfile
        case failed(String)
    }

    public private(set) var session: Session?
    public private(set) var user: User?
    public private(set) var isLoading: Bool = false
    public private(set) var error: Error?
    public private(set) var isGuestMode: Bool

    public var isAuthenticated: Bool {
        session != nil && user != nil
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, checksSessionOnInit: Bool = true) {
        self.defaults = defaults
        self.isGuestMode = defaults.bool(forKey: Keys.guestMode)
        if checksSessionOnInit {
            Task {
                await checkSession()
            }
        }
    }

    public func checkSession() async {
        session = Clerk.shared.session
        user = Clerk.shared.user
        error = nil
        print("[AuthService] checkSession: authenticated=\(isAuthenticated), user=\(user?.id ?? "nil")")
    }

    // MARK: - Guest Mode

    public func enterGuestMode() {
        isGuestMode = true
        defaults.set(true, forKey: Keys.guestMode)
        print("[AuthService] Entered guest mode")
    }

    public func exitGuestMode() {
        isGuestMode = false
        defaults.removeObject(forKey: Keys.guestMode)
        print("[AuthService] Exited guest mode")
    }

    // MARK: - Sign In / Up

    public func signInWithEmailPassword(email: String, password: String) async -> SignInResult {
        isLoading = true
        defer { isLoading = false }
        print("[AuthService] signIn: attempting with email=\(email)")

        do {
            _ = try await Clerk.shared.auth.signInWithPassword(identifier: email, password: password)
            session = Clerk.shared.session
            user = Clerk.shared.user
            error = nil
            print("[AuthService] signIn: ✅ success, user=\(user?.id ?? "nil")")
            return .success
        } catch {
            self.error = error
            let reflected = String(reflecting: error)
            let localized = error.localizedDescription

            if reflected.contains("form_identifier_not_found") {
                return .accountNotFound
            }
            return .failed(localized)
        }
    }

    public func signInWithApple() async -> SignInResult {
        isLoading = true
        defer { isLoading = false }
        print("[AuthService] signInWithApple: attempting")

        do {
            let result = try await Clerk.shared.auth.signInWithApple()
            return handleTransferFlowResult(result)
        } catch {
            self.error = error
            print("[AuthService] signInWithApple: ❌ \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    public func signInWithGoogle() async -> SignInResult {
        isLoading = true
        defer { isLoading = false }
        print("[AuthService] signInWithGoogle: attempting")

        do {
            let result = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
            return handleTransferFlowResult(result)
        } catch {
            self.error = error
            print("[AuthService] signInWithGoogle: ❌ \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func handleTransferFlowResult(_ result: TransferFlowResult) -> SignInResult {
        switch result {
        case let .signIn(signIn):
            if signIn.status == .complete {
                session = Clerk.shared.session
                user = Clerk.shared.user
                error = nil
                return .success
            }
            return .failed("Sign in incomplete: \(signIn.status)")

        case let .signUp(signUp):
            if signUp.status == .complete {
                session = Clerk.shared.session
                user = Clerk.shared.user
                error = nil
                return .success
            } else if signUp.status == .missingRequirements {
                return .needsProfile
            }
            return .failed("Sign up incomplete: \(signUp.status)")
        }
    }

    public func completeOAuthSignUp(username: String, firstName: String, lastName: String) async -> SignInResult {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let currentSignUp = Clerk.shared.client?.signUp else {
                return .failed("No active sign up found")
            }
            let updated = try await currentSignUp.update(
                firstName: firstName.isEmpty ? nil : firstName,
                lastName: lastName.isEmpty ? nil : lastName,
                username: username
            )
            if updated.status == .complete {
                session = Clerk.shared.session
                user = Clerk.shared.user
                return .success
            }
            return .failed("Sign up incomplete: \(updated.status)")
        } catch {
            self.error = error
            return .failed(error.localizedDescription)
        }
    }

    public func signUpWithEmailPassword(email: String, password: String, firstName: String?, lastName: String?) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        print("[AuthService] signUp: attempting with email=\(email), firstName=\(firstName ?? "nil")")

        do {
            _ = try await Clerk.shared.auth.signUp(
                emailAddress: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            )
            session = Clerk.shared.session
            user = Clerk.shared.user
            error = nil
            print("[AuthService] signUp: ✅ success, user=\(user?.id ?? "nil")")
            return true
        } catch {
            self.error = error
            print("[AuthService] signUp: ❌ \(error.localizedDescription)")
            print("[AuthService] signUp: reflected = \(String(reflecting: error))")
            return false
        }
    }

    // MARK: - Account Linking

    public func connectAppleAccount() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        print("[AuthService] connectAppleAccount: attempting")

        do {
            guard let currentUser = Clerk.shared.user else { return false }
            _ = try await currentUser.connectAppleAccount()
            user = Clerk.shared.user
            error = nil
            print("[AuthService] connectAppleAccount: ✅ success")
            return true
        } catch {
            self.error = error
            print("[AuthService] connectAppleAccount: ❌ \(error.localizedDescription)")
            return false
        }
    }

    public func connectGoogleAccount() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        print("[AuthService] connectGoogleAccount: attempting")

        do {
            guard let currentUser = Clerk.shared.user else { return false }
            let account = try await currentUser.createExternalAccount(provider: .google)
            _ = try await account.reauthorize()
            user = Clerk.shared.user
            error = nil
            print("[AuthService] connectGoogleAccount: ✅ success")
            return true
        } catch {
            self.error = error
            print("[AuthService] connectGoogleAccount: ❌ \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Sign Out

    public func signOut() async {
        print("[AuthService] signOut: attempting")
        do {
            try await Clerk.shared.auth.signOut()
            session = nil
            user = nil
            error = nil
            exitGuestMode()
            print("[AuthService] signOut: ✅ success")
        } catch {
            self.error = error
            print("[AuthService] signOut: ❌ \(error.localizedDescription)")
        }
    }

    public func getSessionToken() async -> String? {
        do {
            let token = try await Clerk.shared.session?.getToken()
            print("[AuthService] getSessionToken: \(token != nil ? "✅ got token" : "⚠️ nil")")
            return token
        } catch {
            self.error = error
            print("[AuthService] getSessionToken: ❌ \(error.localizedDescription)")
            return nil
        }
    }
}

public extension User {
    var fullName: String {
        let first = firstName ?? ""
        let last = lastName ?? ""
        let combined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? "Unknown" : combined
    }
}
