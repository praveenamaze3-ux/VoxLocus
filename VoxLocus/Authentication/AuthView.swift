import SwiftUI

struct AuthView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var viewModel: AuthViewModel

    init(authService: AuthService) {
        self.authService = authService
        _viewModel = StateObject(wrappedValue: AuthViewModel(authService: authService))
    }

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 28) {
                Spacer()
                header
                modePicker
                credentialFields
                errorMessage
                submitButton
                if viewModel.mode == .login {
                    forgotPasswordButton
                }
                Spacer(); Spacer()
            }
        }
        .alert("Reset Password", isPresented: $viewModel.showReset) {
            TextField("Email", text: $viewModel.email)
            Button("Send Reset Email") { viewModel.sendResetEmail() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("A reset link will be sent to your email.") }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.accent)
            Text("SmartNotes")
                .font(.largeTitle.bold()).foregroundStyle(AppTheme.textPrimary)
            Text("Your notes, securely encrypted")
                .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("", selection: $viewModel.mode) {
            ForEach(AuthViewModel.Mode.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 32)
        .onChange(of: viewModel.mode) { _, _ in viewModel.didChangeMode() }
    }

    // MARK: - Credential fields

    private var credentialFields: some View {
        VStack(spacing: 14) {
            field(icon: "envelope",   placeholder: String(localized: "Email"),            text: $viewModel.email,           secure: false)
            field(icon: "lock",       placeholder: String(localized: "Password"),          text: $viewModel.password,        secure: true)
            if viewModel.mode == .signUp {
                field(icon: "lock.rotation", placeholder: String(localized: "Confirm Password"), text: $viewModel.confirmPassword, secure: true)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let err = authService.errorMessage {
            Text(err).font(.caption).foregroundStyle(AppTheme.recordingRed)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            viewModel.submit()
        } label: {
            Group {
                if authService.isLoading { ProgressView() }
                else { Text(viewModel.mode.displayName).font(.headline) }
            }
            .frame(maxWidth: .infinity).padding()
        }
        .buttonStyle(.glassProminent)
        .tint(AppTheme.accent)
        .disabled(viewModel.isSubmitDisabled)
        .padding(.horizontal, 24)
    }

    private var forgotPasswordButton: some View {
        Button("Forgot Password?") { viewModel.showReset = true }
            .font(.caption).foregroundStyle(AppTheme.textSecondary)
    }

    // MARK: - Field row

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
