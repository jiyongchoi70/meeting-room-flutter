import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/presentation/pages/login_page.dart';
import '../features/calendar/presentation/pages/calendar_page.dart';

class AppRouter {
  static const String login = '/login';
  static const String calendar = '/calendar';

  static final GoRouter router = GoRouter(
    initialLocation: calendar,
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (_, state) {
      final isLoggedIn = Supabase.instance.client.auth.currentSession != null;
      final isOnLogin = state.matchedLocation == login;

      if (!isLoggedIn && !isOnLogin) return login;
      if (isLoggedIn && isOnLogin) return calendar;
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: login,
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: calendar,
        builder: (_, __) => const CalendarPage(),
      ),
    ],
  );
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
