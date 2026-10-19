import 'package:flutter/material.dart';
import 'package:lockbox/features/onboarding/domain/permission_state.dart';

/// Live checklist widget showing the real-time status of all 4 required permissions.
class LivePermissionChecklist extends StatelessWidget {
  final OnboardingPermissionState state;

  const LivePermissionChecklist({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final granted = state.grantedCount;
    final progress = granted / 4.0;
    const emeraldColor = Color(0xFF10B981);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: state.hasEssentialPermissions
              ? emeraldColor.withValues(alpha: 0.3)
              : Colors.indigoAccent.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title & Progress Counter ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fact_check_rounded,
                  color: Colors.indigoAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Permission Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Real-time system verification',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: state.hasEssentialPermissions
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: state.hasEssentialPermissions
                        ? Colors.greenAccent.withValues(alpha: 0.3)
                        : Colors.orangeAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '$granted / 4 Active',
                  style: TextStyle(
                    color: state.hasEssentialPermissions
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Progress Bar ──
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                state.hasAllPermissions
                    ? Colors.greenAccent
                    : (state.hasEssentialPermissions
                        ? Colors.indigoAccent
                        : Colors.amberAccent),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── 4 Live Status Badges ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: 'Accessibility',
                isGranted: state.isAccessibilityGranted,
                isRequired: true,
              ),
              _StatusPill(
                label: 'Appear on Top',
                isGranted: state.isOverlayGranted,
                isRequired: true,
              ),
              _StatusPill(
                label: 'Notifications',
                isGranted: state.isNotificationGranted,
                isRequired: false,
              ),
              _StatusPill(
                label: 'Battery Exemption',
                isGranted: state.isBatteryExemptGranted,
                isRequired: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool isGranted;
  final bool isRequired;

  const _StatusPill({
    required this.label,
    required this.isGranted,
    required this.isRequired,
  });

  @override
  Widget build(BuildContext context) {
    final color = isGranted
        ? Colors.greenAccent
        : (isRequired ? Colors.orangeAccent : Colors.white38);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isGranted
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGranted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isGranted ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: isGranted ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
