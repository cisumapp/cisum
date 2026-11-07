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
        case email, password, profile, verify
    }

    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    public var onLoginSuccess: ((_ signup: Bool) async -> Void)?

    @State private var step: Step = .email
    @State private var isNewUser = false
    @State private var isOAuthFlow = false
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var code = ""
    @State private var errorMessage: String?

    private static let fieldBg = Color.surfaceRaised

    public init(onLoginSuccess: ((_ signup: Bool) async -> Void)? = nil) {
        self.onLoginSuccess = onLoginSuccess
    }

    public var body: some View {
        // Scrolls, bottom-anchored when it fits: opened from Profile (guest mode) the player and the
        // tab bar stay on screen, and a fixed layout put the buttons underneath them.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 120)

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
                                        .foregroundStyle(.textPrimary)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }

                            Text(title)
                                .font(.title2)
                                .foregroundStyle(.textPrimary)
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
                            case .verify:
                                verifyFields
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

                    if step == .email, !authService.isGuestMode {
                        continueAsGuest
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding([.horizontal, .bottom], 24)
                .frame(minHeight: proxy.size.height, alignment: .bottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, authService.isGuestMode ? 150 : 0, for: .scrollContent)
        }
        .background(Color.surfaceBackground.ignoresSafeArea())
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
                .foregroundStyle(.textPrimary)
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
                .foregroundStyle(.textPrimary)
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
                    .foregroundStyle(.textPrimary)
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
                    .foregroundStyle(.textPrimary)
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
                    .foregroundStyle(.textPrimary)
            }
        }
    }

    private var verifyFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Code")
            Text("Sent to \(email)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("", text: $code)
                .textFieldStyle(.plain)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .textContentType(.oneTimeCode)
                .padding(12)
                .background(Self.fieldBg)
                .cornerRadius(6)
                .foregroundStyle(.textPrimary)
        }
    }

    // MARK: - Shared Components

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(.textPrimary)
//            .fontWidth(.expanded)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.textDestructive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.textDestructive.opacity(0.12))
        .cornerRadius(8)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var actionButton: some View {
        Button(action: handleAction) {
            Group {
                if authService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().progressViewStyle(.circular).tint(.textOnAccent)
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
            .background(isActionDisabled ? Color.fillStrong : Color.accentFill)
            .foregroundStyle(isActionDisabled ? Color.textTertiary : Color.textOnAccent)
            .cornerRadius(50)
            .disabled(isActionDisabled)
            .animation(.easeInOut(duration: 0.2), value: isActionDisabled)
        }
        .buttonStyle(.plain)
    }

    private var socialSection: some View {
        VStack(spacing: 12) {
            HStack {
                Rectangle().fill(.separatorLine).frame(height: 1)
                Text("or").foregroundStyle(.textSecondary).font(.system(size: 14))
                Rectangle().fill(.separatorLine).frame(height: 1)
            }

            #if os(iOS)
            AppleSignInButton(action: handleAppleSignIn)
                // Apple's button takes its style once, at creation: rebuilt when the mode changes.
                .id(colorScheme)
                .frame(maxWidth: .infinity)
                .frame(height: 52) // Approximate height for standard buttons
            #endif

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
                .foregroundStyle(.textPrimary)
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
                .foregroundStyle(.textSecondary)
                .underline(color: .textTertiary)
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
        case .verify: "Check your email"
        }
    }

    private var actionLabel: String {
        switch step {
        case .email: "Next"
        case .password: "Continue"
        case .profile: "Create Account"
        case .verify: "Verify"
        }
    }

    private var loadingLabel: String {
        switch step {
        case .email: "Next"
        case .password: isNewUser ? "Continue" : "Signing In..."
        case .profile: "Creating Account..."
        case .verify: "Verifying..."
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
        case .verify:
            return busy || code.count < 6
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
        case .verify:
            code = ""
            step = .profile
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
        case .verify:
            verify()
        }
    }

    private func attemptSignIn() {
        Task {
            let result = await authService.signInWithEmailPassword(email: email, password: password)
            switch result {
            case .success:
                await finish(signup: false)
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
            let result = await authService.signUpWithEmailPassword(
                email: email, password: password,
                firstName: firstName, lastName: lastName.isEmpty ? nil : lastName,
                username: username
            )
            await handle(result)
        }
    }

    private func verify() {
        Task { await handle(authService.verifySignUpEmail(code: code)) }
    }

    private func handle(_ result: AuthService.SignUpResult) async {
        switch result {
        case .success:
            await finish(signup: true)
        case .needsEmailCode:
            withAnimation { step = .verify }
        case let .failed(message):
            errorMessage = message
        }
    }

    /// Signed in: tells the app, then leaves. Opened from Profile the page is pushed and has to pop
    /// itself; at launch the root swaps to the app on its own and `dismiss` does nothing.
    private func finish(signup: Bool) async {
        authService.exitGuestMode()
        if let onLoginSuccess {
            await onLoginSuccess(signup)
        }
        dismiss()
    }

    private func completeOAuthSignUp() {
        Task {
            let result = await authService.completeOAuthSignUp(username: username, firstName: firstName, lastName: lastName)
            switch result {
            case .success:
                await finish(signup: true)
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
                await finish(signup: false)
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
                await finish(signup: false)
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
