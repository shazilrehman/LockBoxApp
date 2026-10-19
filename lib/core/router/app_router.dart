import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lockbox/core/services/secure_storage_service.dart';
import 'package:lockbox/features/home/presentation/home_screen.dart';
import 'package:lockbox/features/onboarding/presentation/onboarding_screen.dart';
import 'package:lockbox/features/onboarding/providers/onboarding_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final storage = ref.watch(secureStorageServiceProvider);

  // Cached once true so we don't hit secure storage on every navigation.
  bool onboardingDone = false;

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      if (!onboardingDone) {
        final value =
            await storage.read(key: OnboardingNotifier.keyOnboardingComplete);
        onboardingDone = value == 'true';
      }
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!onboardingDone && !atOnboarding) return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
    ],
  );
});
