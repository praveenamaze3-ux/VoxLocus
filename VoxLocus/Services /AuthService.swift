
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
        } catch { errorMessage = error.localizedDescription }
    }

    func signIn(email: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let r = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUser = r.user
        } catch { errorMessage = error.localizedDescription }
    }

    func signOut() {
        do { try Auth.auth().signOut(); currentUser = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func resetPassword(email: String) async {
        isLoading = true; defer { isLoading = false }
        do { try await Auth.auth().sendPasswordReset(withEmail: email) }
        catch { errorMessage = error.localizedDescription }
    }
}

