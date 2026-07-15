import Foundation
import Combine

/// Owns all state and business logic for the sign-in/sign-up form: mode
/// selection, field validation, and submission orchestration against
/// `AuthService`. `AuthView` only binds to this and renders — the two
/// reactive fields it reads directly from `authService` (`isLoading`,
/// `errorMessage`) are AuthService's own published state, not view logic.
@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode: String, CaseIterable {
        case login = "Log In"
        case signUp = "Sign Up"

        var displayName: String {
            switch self {
            case .login:  return String(localized: "Log In")
            case .signUp: return String(localized: "Sign Up")
            }
        }
    }

    @Published var mode: Mode = .login
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var showReset = false

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var isSubmitDisabled: Bool {
        authService.isLoading || email.isEmpty || password.isEmpty
    }

    /// Called when the user switches between Log In / Sign Up — clears any
    /// error left over from the previous mode.
    func didChangeMode() {
        authService.errorMessage = nil
    }

    func submit() {
        guard AuthService.isValidEmailFormat(email) else {
            authService.errorMessage = String(localized: "That email address doesn't look valid. Please enter it in the format name@example.com.")
            return
        }
        Task {
            if mode == .login {
                await authService.signIn(email: email, password: password)
            } else {
                guard password == confirmPassword else {
                    authService.errorMessage = String(localized: "Passwords do not match.")
                    return
                }
                await authService.signUp(email: email, password: password)
            }
        }
    }

    func sendResetEmail() {
        Task { await authService.resetPassword(email: email) }
    }
}
