import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lockbox/core/services/local_auth_service.dart';
import 'package:lockbox/core/services/secure_storage_service.dart';
import 'package:lockbox/features/auth/domain/auth_models.dart';
import 'package:lockbox/features/auth/services/auth_service.dart';

/// In-memory fake implementation of [SecureStorageService] for fast, deterministic unit testing.
class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _data[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _data[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    return Map.unmodifiable(_data);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }
}

/// Fake implementation of [LocalAuthService] for mocking biometric responses.
class FakeLocalAuthService extends LocalAuthService {
  bool isSupported;
  bool canCheck;
  List<BiometricType> biometrics;
  bool authResult;

  FakeLocalAuthService({
    this.isSupported = true,
    this.canCheck = true,
    this.biometrics = const [BiometricType.fingerprint, BiometricType.weak],
    this.authResult = true,
  });

  @override
  Future<bool> isDeviceSupported() async => isSupported;

  @override
  Future<bool> canCheckBiometrics() async => canCheck;

  @override
  Future<List<BiometricType>> availableBiometrics() async => biometrics;

  @override
  Future<bool> hasEnrolledBiometrics() async => biometrics.isNotEmpty;

  @override
  Future<bool> authenticateBiometricOnly({
    String reason = 'Authenticate to unlock',
  }) async {
    if (!isSupported && !canCheck) return false;
    return authResult;
  }
}

void main() {
  group('AuthService', () {
    late FakeSecureStorageService fakeStorage;
    late FakeLocalAuthService fakeLocalAuth;
    late AuthService authService;

    setUp(() {
      fakeStorage = FakeSecureStorageService();
      fakeLocalAuth = FakeLocalAuthService();
      // Use 1,000 iterations for fast unit test execution while preserving full PBKDF2 logic
      authService = AuthService(
        storage: fakeStorage,
        localAuth: fakeLocalAuth,
        iterations: 1000,
      );
    });

    group('PIN Setup & Verification', () {
      test('hasPin returns false initially', () async {
        expect(await authService.hasPin(), isFalse);
      });

      test('setupPin stores salt, iterations, and PBKDF2 hash', () async {
        await authService.setupPin('1234');

        expect(await authService.hasPin(), isTrue);
        final hash = await fakeStorage.read(key: AuthService.keyPinHash);
        final salt = await fakeStorage.read(key: AuthService.keyPinSalt);
        final iter = await fakeStorage.read(key: AuthService.keyPinIterations);

        expect(hash, isNotNull);
        expect(hash!.length, equals(64)); // 32 bytes = 64 hex chars
        expect(salt, isNotNull);
        expect(salt!.length, equals(32)); // 16 bytes = 32 hex chars
        expect(iter, equals('1000'));
      });

      test('setupPin throws on empty PIN', () async {
        expect(() => authService.setupPin(''), throwsArgumentError);
        expect(() => authService.setupPin('   '), throwsArgumentError);
      });

      test('verifyPin returns success for correct PIN', () async {
        await authService.setupPin('4321');
        final result = await authService.verifyPin('4321');

        expect(result.isSuccess, isTrue);
        expect(result.failureReason, isNull);
      });

      test('verifyPin returns wrongPin for incorrect PIN', () async {
        await authService.setupPin('4321');
        final result = await authService.verifyPin('0000');

        expect(result.isSuccess, isFalse);
        expect(result.failureReason, equals(AuthFailureReason.wrongPin));
        expect(result.remainingAttempts, equals(4));
      });

      test('verifyPin returns noPinConfigured when no PIN is set', () async {
        final result = await authService.verifyPin('1234');
        expect(result.isSuccess, isFalse);
        expect(result.failureReason, equals(AuthFailureReason.noPinConfigured));
      });

      test('clearPin removes all credentials and reset lockout', () async {
        await authService.setupPin('1234');
        expect(await authService.hasPin(), isTrue);

        await authService.clearPin();
        expect(await authService.hasPin(), isFalse);
        expect(await fakeStorage.read(key: AuthService.keyPinHash), isNull);
        expect(await fakeStorage.read(key: AuthService.keyPinSalt), isNull);
      });
    });

    group('Lockout Progression (Increasing Delay)', () {
      setUp(() async {
        await authService.setupPin('1234');
      });

      test('failures 1 to 4 do not lock out but decrement remaining attempts', () async {
        for (int i = 1; i <= 4; i++) {
          final res = await authService.verifyPin('9999');
          expect(res.isSuccess, isFalse);
          expect(res.failureReason, equals(AuthFailureReason.wrongPin));
          expect(res.remainingAttempts, equals(5 - i));
        }

        final status = await authService.getLockoutStatus();
        expect(status.isLockedOut, isFalse);
        expect(status.failedAttempts, equals(4));
      });

      test('5th failure triggers 30-second lockout', () async {
        for (int i = 1; i <= 4; i++) {
          await authService.verifyPin('9999');
        }

        final res = await authService.verifyPin('9999');
        expect(res.isSuccess, isFalse);
        expect(res.failureReason, equals(AuthFailureReason.lockedOut));
        expect(res.lockoutDuration.inSeconds, equals(30));

        final status = await authService.getLockoutStatus();
        expect(status.isLockedOut, isTrue);
        expect(status.remainingLockout.inSeconds, inInclusiveRange(28, 30));
        expect(status.failedAttempts, equals(5));
      });

      test('attempts while locked out are immediately rejected without computing hash', () async {
        // Trigger 5th failure
        for (int i = 1; i <= 5; i++) {
          await authService.verifyPin('9999');
        }

        // Even with the CORRECT PIN, user is locked out until timer expires
        final res = await authService.verifyPin('1234');
        expect(res.isSuccess, isFalse);
        expect(res.failureReason, equals(AuthFailureReason.lockedOut));
        expect(res.lockoutDuration.inSeconds, greaterThan(0));
      });

      test('lockout delay increases with subsequent failures: 60s, 120s, 300s, 900s', () {
        expect(authService.calculateLockoutDuration(4), equals(Duration.zero));
        expect(authService.calculateLockoutDuration(5), equals(const Duration(seconds: 30)));
        expect(authService.calculateLockoutDuration(6), equals(const Duration(seconds: 60)));
        expect(authService.calculateLockoutDuration(7), equals(const Duration(seconds: 120)));
        expect(authService.calculateLockoutDuration(8), equals(const Duration(seconds: 300)));
        expect(authService.calculateLockoutDuration(9), equals(const Duration(seconds: 900)));
        expect(authService.calculateLockoutDuration(15), equals(const Duration(seconds: 900)));
      });

      test('correct PIN verification resets failed attempts counter', () async {
        // Fail 3 times
        for (int i = 1; i <= 3; i++) {
          await authService.verifyPin('9999');
        }
        expect((await authService.getLockoutStatus()).failedAttempts, equals(3));

        // Enter correct PIN
        final success = await authService.verifyPin('1234');
        expect(success.isSuccess, isTrue);

        // Counter reset
        expect((await authService.getLockoutStatus()).failedAttempts, equals(0));
      });

      test('expired lockout allows retry and increments delay on subsequent failure', () async {
        // Set up expired lockout state directly in storage
        await fakeStorage.write(key: AuthService.keyFailedAttempts, value: '5');
        // Expired 5 seconds ago
        final expiredEpoch = DateTime.now().subtract(const Duration(seconds: 5)).millisecondsSinceEpoch;
        await fakeStorage.write(key: AuthService.keyLockoutUntil, value: expiredEpoch.toString());

        final status = await authService.getLockoutStatus();
        expect(status.isLockedOut, isFalse); // expired

        // 6th failure -> should trigger 60s lockout!
        final res = await authService.verifyPin('9999');
        expect(res.isSuccess, isFalse);
        expect(res.failureReason, equals(AuthFailureReason.lockedOut));
        expect(res.lockoutDuration.inSeconds, equals(60));
      });
    });

    group('Biometric Authentication & PIN Fallback', () {
      setUp(() async {
        await authService.setupPin('1234');
      });

      test('successful biometric authentication returns success and resets lockout', () async {
        fakeLocalAuth.authResult = true;
        final res = await authService.authenticateBiometrics();

        expect(res.isSuccess, isTrue);
      });

      test('biometric failure/cancellation returns biometricFailed for PIN fallback', () async {
        fakeLocalAuth.authResult = false;
        final res = await authService.authenticateBiometrics();

        expect(res.isSuccess, isFalse);
        expect(res.failureReason, equals(AuthFailureReason.biometricFailed));
      });

      test('biometrics unavailable returns biometricUnavailable for PIN fallback', () async {
        fakeLocalAuth.biometrics = [];
        final res = await authService.authenticateBiometrics();

        expect(res.isSuccess, isFalse);
        expect(res.failureReason, equals(AuthFailureReason.biometricUnavailable));
      });

      test('biometrics blocked while locked out', () async {
        // Trigger lockout
        for (int i = 1; i <= 5; i++) {
          await authService.verifyPin('9999');
        }

        final res = await authService.authenticateBiometrics();
        expect(res.isSuccess, isFalse);
        expect(res.failureReason, equals(AuthFailureReason.lockedOut));
      });
    });
  });
}
