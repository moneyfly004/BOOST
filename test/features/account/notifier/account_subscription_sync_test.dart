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
    const accountUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token';
    const accountClashUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash';
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
      url: 'https://example.com/manual-token',
      lastUpdate: DateTime(2026),
    );
    final unrelatedBoostHostProfile = RemoteProfileEntity(
      id: 'unrelated-boost-host',
      active: false,
      name: 'VIP',
      url: 'https://new.moneyfly.top/api/v1/client/subscribe?token=legacy-token',
      lastUpdate: DateTime(2026),
      userOverride: const UserOverride(version: 1, name: 'VIP', updateInterval: 1),
    );
    final oldAccountProfile = RemoteProfileEntity(
      id: 'account',
      active: false,
      name: AccountSubscriptionSync.accountProfileName,
      url: accountUrl,
      lastUpdate: DateTime(2026),
      userOverride: const UserOverride(version: 1, name: AccountSubscriptionSync.accountProfileName, updateInterval: 1),
    );
    final repo = _FakeProfileRepository([
      manualProfile,
      manualUniversalProfile,
      unrelatedBoostHostProfile,
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
              tokenUrl: accountUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.deletedIds, ['account']);
    expect(repo.profiles.map((profile) => profile.id), contains('manual'));
    expect(repo.profiles.map((profile) => profile.id), contains('manual-universal'));
    expect(repo.profiles.map((profile) => profile.id), contains('unrelated-boost-host'));
    expect(repo.upsertedUrls, [accountClashUrl]);
    expect(repo.upsertedUserOverrides, [AccountSubscriptionSync.accountProfileOverride]);
  });

  test('sync removes account subscription profile when subscription is expired', () async {
    const expiredAccountUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=expired-token';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'old-expired-account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: expiredAccountUrl,
        lastUpdate: DateTime(2026),
        userOverride: const UserOverride(
          version: 1,
          name: AccountSubscriptionSync.accountProfileName,
          updateInterval: 1,
        ),
      ),
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
              packageName: 'Expired',
              tokenUrl: expiredAccountUrl,
              status: 'expired',
              remainingDays: -1,
            ),
          ),
        );

    expect(repo.deletedIds, ['old-expired-account']);
    expect(repo.upsertedUrls, isEmpty);
  });

  test('sync keeps user configured account subscription update interval', () async {
    const accountUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token';
    const accountClashUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: accountUrl,
        lastUpdate: DateTime(2026),
        userOverride: const UserOverride(name: AccountSubscriptionSync.accountProfileName, updateInterval: 12),
      ),
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
              tokenUrl: accountUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.deletedIds, ['account']);
    expect(repo.upsertedUrls, [accountClashUrl]);
    expect(repo.upsertedUserOverrides, [
      const UserOverride(name: AccountSubscriptionSync.accountProfileName, updateInterval: 12),
    ]);
  });

  test('sync removes account subscription profile when subscription is disabled but still has a url', () async {
    const disabledAccountUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=disabled-token';
    final repo = _FakeProfileRepository([
      RemoteProfileEntity(
        id: 'old-disabled-account',
        active: true,
        name: AccountSubscriptionSync.accountProfileName,
        url: disabledAccountUrl,
        lastUpdate: DateTime(2026),
        userOverride: const UserOverride(
          version: 1,
          name: AccountSubscriptionSync.accountProfileName,
          updateInterval: 1,
        ),
      ),
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
              packageName: 'Disabled',
              tokenUrl: disabledAccountUrl,
              status: 'disabled',
              remainingDays: 30,
            ),
          ),
        );

    expect(repo.deletedIds, ['old-disabled-account']);
    expect(repo.upsertedUrls, isEmpty);
  });

  test('sync imports token url as Clash profile and marks it active', () async {
    const tokenUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token';
    const expectedUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash';
    final repo = _FakeProfileRepository([]);
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
              tokenUrl: tokenUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUrls, [expectedUrl]);
    expect(repo.upsertedActiveValues, [true]);
  });

  test('sync prefers backend Clash url when present', () async {
    const tokenUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token';
    const clashUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash';
    const singboxUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox';
    final repo = _FakeProfileRepository([]);
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
              tokenUrl: tokenUrl,
              clashUrl: clashUrl,
              singboxUrl: singboxUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUrls, [clashUrl]);
  });

  test('sync converts backend universal url to Clash url', () async {
    const universalUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=universal-token';
    const expectedUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=universal-token&type=clash';
    final repo = _FakeProfileRepository([]);
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
              universalUrl: universalUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUrls, [expectedUrl]);
  });

  test('sync falls back to universal token url when Clash import fails', () async {
    const tokenUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token';
    const clashUrl = 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash';
    final repo = _FakeProfileRepository([], failingUrls: {clashUrl});
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
              tokenUrl: tokenUrl,
              clashUrl: clashUrl,
              status: 'active',
              remainingDays: 30,
              isActive: true,
            ),
          ),
        );

    expect(repo.upsertedUrls, [clashUrl, tokenUrl]);
    expect(repo.upsertedActiveValues, [true, true]);
  });
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.profiles, {Set<String>? failingUrls}) : failingUrls = failingUrls ?? const {};

  final List<ProfileEntity> profiles;
  final Set<String> failingUrls;
  final List<String> deletedIds = [];
  final List<String> upsertedUrls = [];
  final List<UserOverride?> upsertedUserOverrides = [];
  final List<bool> upsertedActiveValues = [];

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
    if (failingUrls.contains(url)) {
      upsertedUrls.add(url);
      upsertedUserOverrides.add(userOverride);
      upsertedActiveValues.add(active);
      return TaskEither.left(const ProfileFailure.invalidConfig('bad profile'));
    }
    return TaskEither.tryCatch(() async {
      upsertedUrls.add(url);
      upsertedUserOverrides.add(userOverride);
      upsertedActiveValues.add(active);
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
