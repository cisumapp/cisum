import Aesthetics
import ClerkKit
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct LoginView: View {
    enum Step {
        case email, password, profile
    }

    @Environment(AuthService.self) private var authService
    public var onLoginSuccess: ((_ signup: Bool) async -> Void)?

    @State private var step: Step = .email
    @State private var isNewUser = false
    @State private var isOAuthFlow = false
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var errorMessage: String?

    private static let bg = Color.cisumBg
    private static let fieldBg = Color.cisumSurface
    private static let highlights = Color.cisumAccent

    public init(onLoginSuccess: ((_ signup: Bool) async -> Void)? = nil) {
        self.onLoginSuccess = onLoginSuccess
    }

    public var body: some View {
        ZStack {
            Self.bg.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer(minLength: 300)

                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        if step != .email {
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    goBack()
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }

                        Text(title)
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .fontWeight(.bold)
//                            .fontWidth(.expanded)
                            .contentTransition(.numericText())
                    }

                    Group {
                        switch step {
                        case .email:
                            emailFields
                        case .password:
                            passwordFields
                        case .profile:
                            profileFields
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    actionButton
                }

                if step == .email {
                    socialSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()

                if step == .email {
                    continueAsGuest
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding([.horizontal, .bottom], 24)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
        .onChange(of: email) { _, _ in isNewUser = false }
        .loginTabBarHidden()
    }

    // MARK: - Step Fields

    private var emailFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Email")
            TextField("", text: $email)
                .textFieldStyle(.plain)
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            #endif
                .textContentType(.emailAddress)
                .padding(12)
                .background(Self.fieldBg)
                .cornerRadius(6)
                .foregroundColor(.primary)
        }
    }

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Password")
            SecureField("", text: $password)
                .textFieldStyle(.plain)
                .textContentType(isNewUser ? .newPassword : .password)
                .padding(12)
                .background(Self.fieldBg)
                .cornerRadius(6)
                .foregroundColor(.primary)
        }
    }

    private var profileFields: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("First Name")
                TextField("First", text: $firstName)
                    .textFieldStyle(.plain)
                #if os(iOS)
                    .textInputAutocapitalization(.words)
                #endif
                    .padding(12)
                    .background(Self.fieldBg)
                    .cornerRadius(6)
                    .foregroundColor(.primary)
            }
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Last Name")
                TextField("Last", text: $lastName)
                    .textFieldStyle(.plain)
                #if os(iOS)
                    .textInputAutocapitalization(.words)
                #endif
                    .padding(12)
                    .background(Self.fieldBg)
                    .cornerRadius(6)
                    .foregroundColor(.primary)
            }
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Username")
                TextField("@username", text: $username)
                    .textFieldStyle(.plain)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .padding(12)
                    .background(Self.fieldBg)
                    .cornerRadius(6)
                    .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Shared Components

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
//            .fontWidth(.expanded)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var actionButton: some View {
        Button(action: handleAction) {
            Group {
                if authService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().progressViewStyle(.circular).tint(.primary)
                        Text(loadingLabel)
                    }
                } else {
                    Text(actionLabel)
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 16, weight: .semibold))
//            .fontWidth(.expanded)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isActionDisabled ? Self.highlights.opacity(0.4) : Self.highlights)
            .foregroundColor(.primary)
            .cornerRadius(50)
            .disabled(isActionDisabled)
            .animation(.easeInOut(duration: 0.2), value: isActionDisabled)
        }
        .buttonStyle(.plain)
    }

    private var socialSection: some View {
        VStack(spacing: 12) {
            HStack {
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                Text("or").foregroundColor(.secondary).font(.system(size: 14))
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            }

            AppleSignInButton(action: handleAppleSignIn)
                .frame(maxWidth: .infinity)
                .frame(height: 52) // Approximate height for standard buttons

            Button(action: handleGoogleSignIn) {
                HStack {
                    Image("googlelogo")
                        .resizable()
                        .frame(width: 18, height: 18)

                    Text("Continue with Google").font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Self.fieldBg)
                .foregroundColor(.primary)
                .cornerRadius(50)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var continueAsGuest: some View {
        Button(action: { authService.enterGuestMode() }) {
            Text("Continue as guest")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Self.highlights.opacity(0.8))
                .underline(color: Self.highlights.opacity(0.4))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Computed Labels

    private var title: String {
        switch step {
        case .email: ""
        case .password: isNewUser ? "Create a password" : "Enter your password"
        case .profile: "Almost there"
        }
    }

    private var actionLabel: String {
        switch step {
        case .email: "Next"
        case .password: "Continue"
        case .profile: "Create Account"
        }
    }

    private var loadingLabel: String {
        switch step {
        case .email: "Next"
        case .password: isNewUser ? "Continue" : "Signing In..."
        case .profile: "Creating Account..."
        }
    }

    private var isActionDisabled: Bool {
        let busy = authService.isLoading
        switch step {
        case .email:
            return busy || email.isEmpty
        case .password:
            return busy || password.isEmpty
        case .profile:
            return busy || firstName.isEmpty || username.isEmpty
        }
    }

    // MARK: - Navigation

    private func goBack() {
        errorMessage = nil
        switch step {
        case .email: break
        case .password:
            password = ""
            step = .email
        case .profile:
            firstName = ""
            lastName = ""
            username = ""
            step = .password
        }
    }

    // MARK: - Actions

    private func handleAction() {
        errorMessage = nil
        switch step {
        case .email:
            withAnimation { step = .password }
        case .password where isNewUser:
            withAnimation { step = .profile }
        case .password:
            attemptSignIn()
        case .profile:
            if isOAuthFlow {
                completeOAuthSignUp()
            } else {
                signUp()
            }
        }
    }

    private func attemptSignIn() {
        Task {
            let result = await authService.signInWithEmailPassword(email: email, password: password)
            switch result {
            case .success:
                if let onLoginSuccess { await onLoginSuccess(false) }
            case .accountNotFound, .needsProfile:
                isNewUser = true
                withAnimation { step = .profile }
            case let .failed(message):
                errorMessage = message
            }
        }
    }

    private func signUp() {
        Task {
            let ok = await authService.signUpWithEmailPassword(
                email: email, password: password,
                firstName: firstName, lastName: lastName.isEmpty ? nil : lastName
            )
            if ok {
                if let onLoginSuccess { await onLoginSuccess(true) }
            } else { errorMessage = authService.error?.localizedDescription ?? "Sign-up failed" }
        }
    }

    private func completeOAuthSignUp() {
        Task {
            let result = await authService.completeOAuthSignUp(username: username, firstName: firstName, lastName: lastName)
            switch result {
            case .success:
                if let onLoginSuccess { await onLoginSuccess(true) }
            case let .failed(message):
                errorMessage = message
            case .accountNotFound, .needsProfile:
                errorMessage = "An unexpected error occurred during OAuth profile completion."
            }
        }
    }

    private func handleAppleSignIn() {
        errorMessage = nil
        Task {
            let result = await authService.signInWithApple()
            switch result {
            case .success:
                if let onLoginSuccess { await onLoginSuccess(false) }
            case .needsProfile:
                isNewUser = true
                isOAuthFlow = true
                withAnimation { step = .profile }
            case .accountNotFound:
                break
            case let .failed(message):
                errorMessage = message
            }
        }
    }

    private func handleGoogleSignIn() {
        errorMessage = nil
        Task {
            let result = await authService.signInWithGoogle()
            switch result {
            case .success:
                if let onLoginSuccess { await onLoginSuccess(false) }
            case .needsProfile:
                isNewUser = true
                isOAuthFlow = true
                withAnimation { step = .profile }
            case .accountNotFound:
                break
            case let .failed(message):
                errorMessage = message
            }
        }
    }
}

// MARK: - View Modifiers

private extension View {
    @ViewBuilder
    func loginTabBarHidden() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }
}

#Preview {
    LoginView()
        .environment(AuthService(checksSessionOnInit: false))
}
