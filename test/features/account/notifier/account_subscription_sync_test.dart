import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_subscription_sync.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('sync only replaces account subscription profile', () async {
    const accountUrl = 'https://dy.moneyfly.top/api/v1/subscriptions/universal/account-token';
    final manualProfile = RemoteProfileEntity(
      id: 'manual',
      active: true,
      name: 'Manual',
      url: 'https://example.com/manual.yaml',
      lastUpdate: DateTime(2026),
    );
    final manualUniversalProfile = RemoteProfileEntity(
      id: 'manual-universal',
      active: false,
      name: 'Manual Universal',
      url: 'https://example.com/subscriptions/universal/manual-token',
      lastUpdate: DateTime(2026),
    );
    final legacyAccountProfile = RemoteProfileEntity(
      id: 'legacy-account',
      active: false,
      name: 'VIP',
      url: 'https://dy.moneyfly.top/api/v1/subscriptions/universal/legacy-token',
      lastUpdate: DateTime(2026),
      userOverride: const UserOverride(name: 'VIP', updateInterval: 1),
    );
    final oldAccountProfile = RemoteProfileEntity(
      id: 'account',
      active: false,
      name: AccountSubscriptionSync.accountProfileName,
      url: accountUrl,
      lastUpdate: DateTime(2026),
      userOverride: const UserOverride(name: AccountSubscriptionSync.accountProfileName, updateInterval: 1),
    );
    final repo = _FakeProfileRepository([
      manualProfile,
      manualUniversalProfile,
      legacyAccountProfile,
      oldAccountProfile,
    ]);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);

    await container
        .read(accountSubscriptionSyncProvider)
        .sync(
          const AccountDashboard(
            subscription: AccountSubscription(
              id: 1,
              packageName: 'VIP',
              universalUrl: accountUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.deletedIds, unorderedEquals(['account', 'legacy-account']));
    expect(repo.profiles.map((profile) => profile.id), contains('manual'));
    expect(repo.profiles.map((profile) => profile.id), contains('manual-universal'));
    expect(repo.upsertedUrls, [accountUrl]);
  });
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.profiles);

  final List<ProfileEntity> profiles;
  final List<String> deletedIds = [];
  final List<String> upsertedUrls = [];

  @override
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive) {
    return TaskEither.tryCatch(() async {
      deletedIds.add(id);
      profiles.removeWhere((profile) => profile.id == id);
      return unit;
    }, ProfileFailure.unexpected);
  }

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) {
    return Stream.value(right(List<ProfileEntity>.of(profiles)));
  }

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    bool active = false,
  }) {
    return TaskEither.tryCatch(() async {
      upsertedUrls.add(url);
      profiles.add(
        RemoteProfileEntity(
          id: 'new-account',
          active: active,
          name: userOverride?.name ?? 'Remote',
          url: url,
          lastUpdate: DateTime(2026),
          userOverride: userOverride,
        ),
      );
      return unit;
    }, ProfileFailure.unexpected);
  }

  @override
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride}) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, Unit> init() {
    return TaskEither.of(unit);
  }

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity nProfile, String nContent) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, Unit> setAsActive(String id) {
    throw UnimplementedError();
  }

  @override
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug) {
    throw UnimplementedError();
  }

  @override
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile() {
    throw UnimplementedError();
  }

  @override
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile() {
    throw UnimplementedError();
  }
}
