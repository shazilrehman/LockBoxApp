/// State of all system permissions required for Lockbox operation.
class OnboardingPermissionState {
  final bool isAccessibilityGranted;
  final bool isNotificationGranted;
  final bool isOverlayGranted;
  final bool isBatteryExemptGranted;
  final bool isSamsungDevice;
  final bool isPlayDisclosureAccepted;
  final bool isLoading;

  const OnboardingPermissionState({
    this.isAccessibilityGranted = false,
    this.isNotificationGranted = false,
    this.isOverlayGranted = false,
    this.isBatteryExemptGranted = false,
    this.isSamsungDevice = false,
    this.isPlayDisclosureAccepted = false,
    this.isLoading = true,
  });

  /// True when core essential permissions (Accessibility + Overlay) are granted.
  bool get hasEssentialPermissions =>
      isAccessibilityGranted && isOverlayGranted;

  /// True when all 4 permissions are granted.
  bool get hasAllPermissions =>
      isAccessibilityGranted &&
      isNotificationGranted &&
      isOverlayGranted &&
      isBatteryExemptGranted;

  /// Number of granted permissions out of 4.
  int get grantedCount {
    int count = 0;
    if (isAccessibilityGranted) count++;
    if (isNotificationGranted) count++;
    if (isOverlayGranted) count++;
    if (isBatteryExemptGranted) count++;
    return count;
  }

  /// Number of granted essential permissions (Accessibility + Overlay) out of 2.
  int get essentialGrantedCount =>
      (isAccessibilityGranted ? 1 : 0) + (isOverlayGranted ? 1 : 0);

  OnboardingPermissionState copyWith({
    bool? isAccessibilityGranted,
    bool? isNotificationGranted,
    bool? isOverlayGranted,
    bool? isBatteryExemptGranted,
    bool? isSamsungDevice,
    bool? isPlayDisclosureAccepted,
    bool? isLoading,
  }) {
    return OnboardingPermissionState(
      isAccessibilityGranted:
          isAccessibilityGranted ?? this.isAccessibilityGranted,
      isNotificationGranted:
          isNotificationGranted ?? this.isNotificationGranted,
      isOverlayGranted: isOverlayGranted ?? this.isOverlayGranted,
      isBatteryExemptGranted:
          isBatteryExemptGranted ?? this.isBatteryExemptGranted,
      isSamsungDevice: isSamsungDevice ?? this.isSamsungDevice,
      isPlayDisclosureAccepted:
          isPlayDisclosureAccepted ?? this.isPlayDisclosureAccepted,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
