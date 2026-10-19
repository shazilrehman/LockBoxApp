/// Result of a PIN or biometric verification attempt.
class AuthResult {
  final bool isSuccess;
  final AuthFailureReason? failureReason;
  final int remainingAttempts;
  final Duration lockoutDuration;
  final String? message;

  const AuthResult._({
    required this.isSuccess,
    this.failureReason,
    this.remainingAttempts = 0,
    this.lockoutDuration = Duration.zero,
    this.message,
  });

  /// Authentication succeeded.
  factory AuthResult.success() => const AuthResult._(isSuccess: true);

  /// Wrong PIN entered, but not yet locked out.
  factory AuthResult.wrongPin({required int remainingAttempts}) => AuthResult._(
        isSuccess: false,
        failureReason: AuthFailureReason.wrongPin,
        remainingAttempts: remainingAttempts,
        message: 'Incorrect PIN. $remainingAttempts attempts remaining.',
      );

  /// Lockout triggered or currently active.
  factory AuthResult.lockedOut({required Duration remainingLockout}) =>
      AuthResult._(
        isSuccess: false,
        failureReason: AuthFailureReason.lockedOut,
        remainingAttempts: 0,
        lockoutDuration: remainingLockout,
        message:
            'Too many failed attempts. Try again in ${remainingLockout.inSeconds}s.',
      );

  /// Biometric authentication failed (e.g. unrecognized biometric).
  factory AuthResult.biometricFailed({String? reason}) => AuthResult._(
        isSuccess: false,
        failureReason: AuthFailureReason.biometricFailed,
        message: reason ?? 'Biometric authentication failed. Fallback to PIN.',
      );

  /// Biometrics not available on device or not enrolled.
  factory AuthResult.biometricUnavailable() => const AuthResult._(
        isSuccess: false,
        failureReason: AuthFailureReason.biometricUnavailable,
        message: 'Biometrics unavailable. Please use PIN.',
      );

  /// No PIN has been configured in secure storage.
  factory AuthResult.noPinConfigured() => const AuthResult._(
        isSuccess: false,
        failureReason: AuthFailureReason.noPinConfigured,
        message: 'No PIN configured.',
      );
}

/// Categorized failure reasons.
enum AuthFailureReason {
  wrongPin,
  lockedOut,
  biometricFailed,
  biometricUnavailable,
  noPinConfigured,
}

/// Current lockout state.
class LockoutStatus {
  final bool isLockedOut;
  final int failedAttempts;
  final Duration remainingLockout;
  final DateTime? lockoutUntil;

  const LockoutStatus({
    required this.isLockedOut,
    required this.failedAttempts,
    this.remainingLockout = Duration.zero,
    this.lockoutUntil,
  });

  factory LockoutStatus.none() => const LockoutStatus(
        isLockedOut: false,
        failedAttempts: 0,
      );
}
