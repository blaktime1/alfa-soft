import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/user.dart';
import '../../data/repositories/user_repository.dart';
import 'app_state_provider.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return UserRepository(db);
});

/// Current authenticated user session.
/// ALWAYS starts as null on application launch, enforcing authentication on every app launch.
final currentUserProvider = StateNotifierProvider<CurrentUserNotifier, UserEntity?>((ref) {
  return CurrentUserNotifier(ref);
});

class CurrentUserNotifier extends StateNotifier<UserEntity?> {
  final Ref _ref;

  CurrentUserNotifier(this._ref) : super(null);

  bool login(String username, String password) {
    final repo = _ref.read(userRepositoryProvider);
    final user = repo.authenticate(username, password);
    if (user != null) {
      state = user;
      return true;
    }
    return false;
  }

  void logout() {
    state = null;
  }

  void setUser(UserEntity user) {
    state = user;
  }
}

/// Active branch model
class ActiveBranch {
  final String id;
  final String code;
  final String name;

  const ActiveBranch({required this.id, required this.code, required this.name});
}

final activeBranchProvider = StateNotifierProvider<ActiveBranchNotifier, ActiveBranch?>((ref) {
  return ActiveBranchNotifier(ref);
});

class ActiveBranchNotifier extends StateNotifier<ActiveBranch?> {
  final Ref _ref;

  ActiveBranchNotifier(this._ref) : super(null) {
    _loadDefaultBranch();
  }

  void _loadDefaultBranch() {
    try {
      final db = _ref.read(databaseServiceProvider);
      final rows = db.select('SELECT id, code, name FROM branches WHERE is_main = 1 LIMIT 1');
      if (rows.isNotEmpty) {
        state = ActiveBranch(
          id: rows.first['id'] as String,
          code: rows.first['code'] as String,
          name: rows.first['name'] as String,
        );
      } else {
        final anyBranch = db.select('SELECT id, code, name FROM branches LIMIT 1');
        if (anyBranch.isNotEmpty) {
          state = ActiveBranch(
            id: anyBranch.first['id'] as String,
            code: anyBranch.first['code'] as String,
            name: anyBranch.first['name'] as String,
          );
        }
      }
    } catch (_) {
      // Ignored during early boot or tests
    }
  }

  void setBranch(ActiveBranch branch) {
    state = branch;
  }
}
