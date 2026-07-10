import SwiftUI

struct AuthView: View {
    @ObservedObject var authService: AuthService

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showReset = false

    enum Mode: String, CaseIterable { case login = "Log In"; case signUp = "Sign Up" }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.background, AppTheme.surfaceRaised],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 52))
                        .foregroundStyle(AppTheme.accent)
                    Text("SmartNotes")
                        .font(.largeTitle.bold()).foregroundStyle(AppTheme.textPrimary)
                    Text("Your notes, securely encrypted")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 32)
                .onChange(of: mode) { _, _ in authService.errorMessage = nil }

                VStack(spacing: 14) {
                    field(icon: "envelope",   placeholder: "Email",            text: $email,           secure: false)
                    field(icon: "lock",       placeholder: "Password",          text: $password,        secure: true)
                    if mode == .signUp {
                        field(icon: "lock.rotation", placeholder: "Confirm Password", text: $confirmPassword, secure: true)
                    }
                }
                .padding(.horizontal, 24)

                if let err = authService.errorMessage {
                    Text(err).font(.caption).foregroundStyle(AppTheme.recordingRed)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }

                Button {
                    guard AuthService.isValidEmailFormat(email) else {
                        authService.errorMessage = "That email address doesn't look valid. Please enter it in the format name@example.com."
                        return
                    }
                    Task {
                        if mode == .login {
                            await authService.signIn(email: email, password: password)
                        } else {
                            guard password == confirmPassword else {
                                authService.errorMessage = "Passwords do not match."; return
                            }
                            await authService.signUp(email: email, password: password)
                        }
                    }
                } label: {
                    Group {
                        if authService.isLoading { ProgressView() }
                        else { Text(mode.rawValue).font(.headline) }
                    }
                    .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.glassProminent)
                .tint(AppTheme.accent)
                .disabled(authService.isLoading || email.isEmpty || password.isEmpty)
                .padding(.horizontal, 24)

                if mode == .login {
                    Button("Forgot Password?") { showReset = true }
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(); Spacer()
            }
        }
        .alert("Reset Password", isPresented: $showReset) {
            TextField("Email", text: $email)
            Button("Send Reset Email") { Task { await authService.resetPassword(email: email) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("A reset link will be sent to your email.") }
    }

    private func field(icon: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 20)
            if secure {
                SecureField(placeholder, text: text)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: text)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border, lineWidth: 1))
    }
}
