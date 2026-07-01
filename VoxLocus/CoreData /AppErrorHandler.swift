//
//  AppErrorHandler.swift
//  VoxLocus
//
//  Created by Praveen V on 01/07/26.
//
//
//  AppErrorHandler.swift
//  SmartNotes
//
//  Centralised error types and safe task launcher — zero UIKit.
//

import Foundation
internal import CoreData
import SwiftUI

// MARK: - App-wide error types

enum AppError: LocalizedError {
    case coreDataFault(String)
    case syncFailed(String)
    case encryptionFailed(String)
    case speechUnavailable(String)
    case permissionDenied(String)
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .coreDataFault(let m):     return "Data error: \(m)"
        case .syncFailed(let m):        return "Sync failed: \(m)"
        case .encryptionFailed(let m):  return "Encryption error: \(m)"
        case .speechUnavailable(let m): return "Speech error: \(m)"
        case .permissionDenied(let m):  return "Permission denied: \(m)"
        case .networkUnavailable:       return "No network — changes will sync later."
        }
    }

    /// Show alert for user-actionable errors; log silently for recoverable ones.
    var shouldAlert: Bool {
        switch self {
        case .networkUnavailable, .syncFailed: return false
        default: return true
        }
    }
}

// MARK: - Thread assertions (debug only)

func assertMainThread(file: String = #file, line: Int = #line) {
    #if DEBUG
    assert(Thread.isMainThread, "⚠️ Must run on main thread — \(file):\(line)")
    #endif
}

func assertBackgroundThread(file: String = #file, line: Int = #line) {
    #if DEBUG
    assert(!Thread.isMainThread, "⚠️ Must NOT run on main thread — \(file):\(line)")
    #endif
}

// MARK: - Safe Task launcher

/// Runs an async throwing operation and routes errors to a SwiftUI binding
/// instead of letting them propagate as unhandled crashes.
func safeTask(
    errorBinding: Binding<String?>,
    operation: @escaping () async throws -> Void
) {
    Task {
        do {
            try await operation()
        } catch let appError as AppError {
            if appError.shouldAlert {
                await MainActor.run {
                    errorBinding.wrappedValue = appError.localizedDescription
                }
            } else {
                print("ℹ️ Non-fatal: \(appError.localizedDescription)")
            }
        } catch {
            await MainActor.run {
                errorBinding.wrappedValue = error.localizedDescription
            }
        }
    }
}

// MARK: - Core Data fault guard

/// Safely reads from a managed object, returning `fallback` if the
/// object is faulted or deleted instead of crashing.
func guardFault<T: NSManagedObject, R>(
    _ object: T,
    fallback: R,
    _ block: (T) -> R
) -> R {
    guard object.isAccessible else { return fallback }
    return block(object)
}
