import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import '../auth/auth_providers.dart';
import '../auth/domain/auth_state.dart';
import '../auth/domain/user.dart';
import 'data/profile_api.dart';

final profileApiProvider = Provider<ProfileApi>((ref) => ProfileApi(ref.watch(dioProvider)));

/// Holds the current user's full profile (username, email, About Me, avatar).
///
/// Kept separate from [AuthController] - that provider only owns
/// authentication state - but successful edits here are also pushed into
/// [AuthController] so the rest of the app (e.g. the home screen's greeting)
/// reflects the change immediately.
class ProfileController extends AsyncNotifier<User> {
  @override
  Future<User> build() async {
    final token = await _requireToken();
    return ref.read(profileApiProvider).getProfile(token);
  }

  Future<void> updateProfile({
    required String username,
    required String email,
    required String aboutMe,
  }) async {
    final token = await _requireToken();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final updated = await ref.read(profileApiProvider).updateProfile(
            token,
            username: username,
            email: email,
            aboutMe: aboutMe,
          );
      ref.read(authControllerProvider.notifier).updateUser(updated);
      return updated;
    });
  }

  Future<void> uploadAvatar(File imageFile) async {
    final token = await _requireToken();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final updated = await ref.read(profileApiProvider).uploadAvatar(token, imageFile);
      ref.read(authControllerProvider.notifier).updateUser(updated);
      return updated;
    });
  }

  /// Waits for [AuthController] to finish resolving (it may still be mid
  /// startup token-check) before reading its state, rather than racing it
  /// with a plain synchronous read.
  Future<String> _requireToken() async {
    final authState = await ref.read(authControllerProvider.future);
    if (authState is! AuthAuthenticated) {
      throw StateError('ProfileController used while not authenticated');
    }
    return authState.token;
  }
}

final profileControllerProvider = AsyncNotifierProvider<ProfileController, User>(ProfileController.new);
