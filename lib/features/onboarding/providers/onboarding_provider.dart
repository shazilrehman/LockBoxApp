import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lockbox/core/channels/lockbox_channel.dart';
import 'package:lockbox/core/channels/lockbox_channel_provider.dart';
import 'package:lockbox/core/services/secure_storage_service.dart';
import 'package:lockbox/features/onboarding/domain/permission_state.dart';

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingPermissionState>((ref) {
  final channel = ref.watch(lockboxChannelProvider);
  final storage = ref.watch(secureStorageServiceProvider);
  return OnboardingNotifier(channel: channel, storage: storage);
});

class OnboardingNotifier extends StateNotifier<OnboardingPermissionState> {
  static const String keyPlayDisclosure = 'lockbox_play_disclosure_accepted';
  static const String keyOnboardingComplete = 'lockbox_onboarding_completed';

  final LockboxChannel channel;
  final SecureStorageService storage;

  OnboardingNotifier({
    required this.channel,
    required this.storage,
  }) : super(const OnboardingPermissionState()) {
    checkPermissions();
  }

  /// Queries all Android system permissions and updates state.
  Future<void> checkPermissions() async {
    try {
      final results = await Future.wait([
        channel.isAccessibilityEnabled(),
        channel.isNotificationAccessEnabled(),
        channel.isOverlayPermissionGranted(),
        channel.isBatteryOptimizationIgnored(),
        channel.isSamsungDevice(),
        storage.read(key: keyPlayDisclosure),
      ]);

      final a11y = results[0] as bool;
      final notif = results[1] as bool;
      final overlay = results[2] as bool;
      final battery = results[3] as bool;
      final isSamsung = results[4] as bool;
      final disclosure = results[5] as String?;

      state = state.copyWith(
        isAccessibilityGranted: a11y,
        isNotificationGranted: notif,
        isOverlayGranted: overlay,
        isBatteryExemptGranted: battery,
        isSamsungDevice: isSamsung,
        isPlayDisclosureAccepted: disclosure == 'true',
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Records explicit user acceptance of the Google Play prominent disclosure.
  Future<void> acceptPlayDisclosure() async {
    await storage.write(key: keyPlayDisclosure, value: 'true');
    state = state.copyWith(isPlayDisclosureAccepted: true);
  }

  /// Marks the onboarding flow as completed.
  Future<void> completeOnboarding() async {
    await storage.write(key: keyOnboardingComplete, value: 'true');
  }

  /// Whether onboarding has previously been completed.
  Future<bool> isOnboardingCompleted() async {
    final value = await storage.read(key: keyOnboardingComplete);
    return value == 'true';
  }

  // ── Native Intent Triggers ─────────────────────────────

  Future<void> requestAccessibility() => channel.openAccessibilitySettings();

  Future<void> requestNotificationAccess() =>
      channel.openNotificationSettings();

  Future<void> requestOverlayPermission() => channel.openOverlaySettings();

  Future<void> requestBatteryExemption() =>
      channel.requestBatteryOptimization();
}
