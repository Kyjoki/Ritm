import Foundation

/// Decides what a failed launch-time session check means for a device that has a saved session.
public enum SessionRestorePolicy {
  /// Only the server saying the session is gone (401 AUTH_REQUIRED) signs the device out.
  /// A server error (5xx), rate limit or lost connection at launch is temporary: the app stays
  /// signed in with its saved session and the regular refresh retries.
  public static func keepsSignedIn(afterStartupFailure error: Error, hadSavedSession: Bool) -> Bool
  {
    guard hadSavedSession else { return false }
    if let failure = error as? APIError { return !failure.requiresAuthentication }
    return true
  }
}
