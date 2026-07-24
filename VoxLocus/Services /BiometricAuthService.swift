import LocalAuthentication
import Foundation

/// Wraps `LocalAuthentication` for the app-lock feature — mirrors
/// `AuthService`'s shape (MainActor singleton, async operations, friendly
/// error mapping) but this is a UI-level privacy gate, not a cryptographic
/// one: `EncryptionService`'s Keychain key has no biometric ACL.
@MainActor
final class BiometricAuthService {
    static let shared = BiometricAuthService()
    private init() {}

    enum Kind {
        case none, touchID, faceID, opticID

        fileprivate init(laType: LABiometryType) {
            switch laType {
            case .faceID: self = .faceID
            case .touchID: self = .touchID
            case .opticID: self = .opticID
            default: self = .none
            }
        }

        var displayName: String {
            switch self {
            case .faceID, .none: return String(localized: "Face ID")
            case .touchID: return String(localized: "Touch ID")
            case .opticID: return String(localized: "Optic ID")
            }
        }

        var systemImage: String {
            switch self {
            case .faceID, .none: return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            }
        }
    }

    /// `kind` is the best-effort hardware kind (populated even when unusable,
    /// e.g. present but not enrolled) — used for copy. `isUsable` is the
    /// actual `canEvaluatePolicy` result — used for gating.
    struct Capability {
        let kind: Kind
        let isUsable: Bool
    }

    enum AuthError: Error {
        case notAvailable(Kind)
        case notEnrolled(Kind)
        case lockedOut
        case passcodeNotSet
        case cancelled
        case unknown(String)
    }

    var capability: Capability {
        let context = LAContext()
        var error: NSError?
        // canEvaluatePolicy must run before reading biometryType — that
        // property only populates after this call.
        let usable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return Capability(kind: Kind(laType: context.biometryType), isUsable: usable)
    }

    var isAvailable: Bool { capability.isUsable }

    /// One authentication challenge. Deliberately uses `.deviceOwnerAuthentication`
    /// here (not `.deviceOwnerAuthenticationWithBiometrics`, unlike `capability`
    /// above) so the system automatically offers "Enter Passcode" if Face ID
    /// fails, is temporarily unavailable, or locks out mid-session — the
    /// toggle is still gated on biometrics being enrolled (`capability`), but
    /// once the lock is armed, the device passcode is always a valid fallback
    /// to actually get back in. Uses a fresh `LAContext` per call, per
    /// Apple's guidance that a context shouldn't be reused across evaluations.
    func unlock(reason: String = String(localized: "Unlock VoxLocus to view your notes")) async -> Result<Void, AuthError> {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failure(map(error))
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
                Task { @MainActor in
                    continuation.resume(returning: success ? .success(()) : .failure(self.map(evalError as NSError?)))
                }
            }
        }
    }

    /// Mirrors `AuthService.friendlyMessage` — returns `nil` for
    /// cancellations so the caller doesn't flash an error for a routine
    /// dismissal (e.g. the app being backgrounded mid-prompt).
    func friendlyMessage(for error: AuthError) -> String? {
        switch error {
        case .cancelled:
            return nil
        case .notAvailable(let kind):
            return String(localized: "\(kind.displayName) isn't available on this device.")
        case .notEnrolled(let kind):
            return String(localized: "\(kind.displayName) isn't set up. Enable it in Settings, or sign out below.")
        case .lockedOut:
            return String(localized: "Too many failed attempts. Enter your device passcode to continue, or sign out below.")
        case .passcodeNotSet:
            return String(localized: "Set a device passcode in Settings to use Face ID or Touch ID.")
        case .unknown(let message):
            return message
        }
    }

    private func map(_ nsError: NSError?) -> AuthError {
        guard let nsError, let code = LAError.Code(rawValue: nsError.code) else {
            return .unknown(nsError?.localizedDescription ?? "Biometric authentication failed.")
        }
        let kind = capability.kind
        switch code {
        case .biometryNotAvailable: return .notAvailable(kind)
        case .biometryNotEnrolled:  return .notEnrolled(kind)
        case .biometryLockout:      return .lockedOut
        case .passcodeNotSet:       return .passcodeNotSet
        case .userCancel, .systemCancel, .appCancel: return .cancelled
        default: return .unknown(nsError.localizedDescription)
        }
    }
}

// MARK: - Persisted preference

/// Single source of truth for the "Require Face ID" toggle key, shared
/// between `AccountView`'s `@AppStorage` (reactive UI) and `RootViewModel`'s
/// plain `UserDefaults` read (not a View, so no `@AppStorage`) — both must
/// read/write the same key.
enum AppLockSettings {
    static let isEnabledKey = "isFaceIDLockEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }
}
