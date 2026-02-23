import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/workout_session.dart';
import '../services/database_service.dart';

class StatsNotifier extends AsyncNotifier<List<WorkoutSession>> {
  @override
  Future<List<WorkoutSession>> build() => DatabaseService.getAllSessions();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => DatabaseService.getAllSessions());
  }
}

final statsProvider =
    AsyncNotifierProvider<StatsNotifier, List<WorkoutSession>>(
  StatsNotifier.new,
);

/// Derived: sessions from the current ISO week (Mon–Sun).
final weeklySessionsProvider = Provider<List<WorkoutSession>>((ref) {
  final sessions = ref.watch(statsProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final weekStart = DateTime(monday.year, monday.month, monday.day);
  return sessions.where((s) => s.date.isAfter(weekStart)).toList();
});

/// Derived: sessions from the current calendar month.
final monthlySessionsProvider = Provider<List<WorkoutSession>>((ref) {
  final sessions = ref.watch(statsProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  return sessions.where((s) => s.date.isAfter(monthStart)).toList();
});

/// Derived: sessions from the current calendar year.
final yearlySessionsProvider = Provider<List<WorkoutSession>>((ref) {
  final sessions = ref.watch(statsProvider).valueOrNull ?? [];
  final yearStart = DateTime(DateTime.now().year);
  return sessions.where((s) => s.date.isAfter(yearStart)).toList();
});

/// Derived: all sessions ever (lifetime).
final lifetimeSessionsProvider = Provider<List<WorkoutSession>>((ref) {
  return ref.watch(statsProvider).valueOrNull ?? [];
});
