import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final accountSubscriptionSyncProvider = Provider<AccountSubscriptionSync>((ref) {
  return AccountSubscriptionSync(ref);
});

class AccountSubscriptionSync {
  const AccountSubscriptionSync(this._ref);

  final Ref _ref;
  static const accountProfileName = 'BOOST 账户订阅';
  static const accountProfileOverride = UserOverride(name: accountProfileName, isAutoUpdateDisable: true);

  Future<void> clearAccountSubscriptions() async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    await _deleteAccountProfiles(repo);
  }

  Future<void> sync(AccountDashboard? dashboard) async {
    final subscription = dashboard?.subscription;
    final url = subscription?.importUrl ?? '';
    final repo = await _ref.read(profileRepositoryProvider.future);
    final canImport = subscription != null && subscription.canImport;
    final existingAccountProfile = await _deleteAccountProfiles(repo, activeUrl: url, keepActiveUrl: canImport);
    if (!canImport) {
      return;
    }

    await repo
        .upsertRemote(url, userOverride: _accountUserOverride(existingAccountProfile), active: true)
        .getOrElse((failure) => throw failure)
        .run();
  }

  Future<void> refreshActiveSubscription(AccountDashboard? dashboard) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    final subscription = dashboard?.subscription;
    final activeUrl = subscription?.importUrl ?? '';
    final canImport = subscription != null && subscription.canImport;
    final existingAccountProfile = await _deleteAccountProfiles(repo, activeUrl: activeUrl, keepActiveUrl: canImport);
    if (!canImport) {
      return;
    }
    await repo
        .upsertRemote(activeUrl, userOverride: _accountUserOverride(existingAccountProfile), active: true)
        .getOrElse((failure) => throw failure)
        .run();
  }

  Future<RemoteProfileEntity?> _deleteAccountProfiles(
    ProfileRepository repo, {
    String? activeUrl,
    bool keepActiveUrl = false,
  }) async {
    final profiles = await repo
        .watchAll(sortMode: SortMode.descending)
        .map((event) => event.getOrElse((failure) => throw failure))
        .first;
    RemoteProfileEntity? existingAccountProfile;
    for (final profile in profiles.where((profile) => _isAccountProfile(profile, activeUrl: activeUrl))) {
      if (profile is RemoteProfileEntity &&
          activeUrl != null &&
          activeUrl.isNotEmpty &&
          _sameSubscriptionUrl(profile.url, activeUrl)) {
        existingAccountProfile ??= profile;
      }
      if (keepActiveUrl &&
          activeUrl != null &&
          activeUrl.isNotEmpty &&
          profile is RemoteProfileEntity &&
          profile.url == activeUrl) {
        existingAccountProfile ??= profile;
        continue;
      }
      await repo.deleteById(profile.id, profile.active).getOrElse((failure) => throw failure).run();
    }
    return existingAccountProfile;
  }

  UserOverride _accountUserOverride(RemoteProfileEntity? existingProfile) {
    final userOverride = existingProfile?.userOverride;
    if (userOverride != null &&
        userOverride.version >= 2 &&
        (userOverride.updateInterval != null || userOverride.isAutoUpdateDisable)) {
      return userOverride.copyWith(name: accountProfileName);
    }
    return accountProfileOverride;
  }

  bool _isAccountProfile(ProfileEntity profile, {String? activeUrl}) {
    return switch (profile) {
      RemoteProfileEntity(:final name, :final url, :final userOverride) =>
        name == accountProfileName ||
            userOverride?.name == accountProfileName ||
            (activeUrl != null && activeUrl.isNotEmpty && _sameSubscriptionUrl(url, activeUrl)),
      LocalProfileEntity(:final name, :final userOverride) =>
        name == accountProfileName || userOverride?.name == accountProfileName,
    };
  }
}

bool _sameSubscriptionUrl(String left, String right) {
  final leftIdentity = _subscriptionIdentity(left);
  final rightIdentity = _subscriptionIdentity(right);
  return leftIdentity != null && leftIdentity == rightIdentity;
}

String? _subscriptionIdentity(String url) {
  final uri = Uri.tryParse(url.trim());
  final token = uri?.queryParameters['token']?.trim();
  if (uri == null || uri.host.isEmpty || token == null || token.isEmpty) {
    return null;
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.host.toLowerCase()}$port${uri.path}?token=$token';
}
