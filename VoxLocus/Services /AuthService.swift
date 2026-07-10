
import FirebaseAuth
import Combine
import Foundation

@MainActor
final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    private var handle: AuthStateDidChangeListenerHandle?

    private init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.currentUser = user }
        }
    }

    deinit { if let h = handle { Auth.auth().removeStateDidChangeListener(h) } }

    var isSignedIn: Bool { currentUser != nil }

    func signUp(email: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let r = try await Auth.auth().createUser(withEmail: email, password: password)
            currentUser = r.user
        } catch { errorMessage = Self.friendlyMessage(for: error) }
    }

    func signIn(email: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let r = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUser = r.user
        } catch { errorMessage = Self.friendlyMessage(for: error) }
    }

    func signOut() {
        do { try Auth.auth().signOut(); currentUser = nil }
        catch { errorMessage = Self.friendlyMessage(for: error) }
    }

    func resetPassword(email: String) async {
        isLoading = true; defer { isLoading = false }
        do { try await Auth.auth().sendPasswordReset(withEmail: email) }
        catch { errorMessage = Self.friendlyMessage(for: error) }
    }

    // MARK: - Validation & error formatting

    /// Basic client-side shape check (`name@domain.tld`) so obviously-invalid
    /// addresses are rejected instantly, before a network round trip.
    static func isValidEmailFormat(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// Translates Firebase Auth's error codes into plain, user-facing copy —
    /// Firebase's own `localizedDescription` is inconsistent in tone and
    /// sometimes exposes internal wording, e.g. "The email address is badly
    /// formatted." with no guidance on what a valid one looks like.
    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return error.localizedDescription
        }
        switch code {
        case .invalidEmail:
            return "That email address doesn't look valid. Please enter it in the format name@example.com."
        case .emailAlreadyInUse:
            return "An account with this email already exists. Try logging in instead."
        case .weakPassword:
            return "Your password is too weak. Please use at least 6 characters."
        case .wrongPassword, .userNotFound, .invalidCredential:
            return "Incorrect email or password. Please try again."
        case .networkError:
            return "Network error. Please check your connection and try again."
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment and try again."
        default:
            return error.localizedDescription
        }
    }
}

