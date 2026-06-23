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
    final urls = subscription?.importUrls ?? const <String>[];
    final repo = await _ref.read(profileRepositoryProvider.future);
    final canImport = subscription != null && subscription.canImport;
    final existingAccountProfile = await _deleteAccountProfiles(repo, activeUrls: urls);
    if (!canImport) {
      return;
    }

    await _importFirstWorkingUrl(repo, urls, existingAccountProfile);
  }

  Future<void> refreshActiveSubscription(AccountDashboard? dashboard) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    final subscription = dashboard?.subscription;
    final activeUrls = subscription?.importUrls ?? const <String>[];
    final canImport = subscription != null && subscription.canImport;
    final existingAccountProfile = await _deleteAccountProfiles(repo, activeUrls: activeUrls);
    if (!canImport) {
      return;
    }
    await _importFirstWorkingUrl(repo, activeUrls, existingAccountProfile);
  }

  Future<void> _importFirstWorkingUrl(
    ProfileRepository repo,
    List<String> urls,
    RemoteProfileEntity? existingAccountProfile,
  ) async {
    Object? lastFailure;
    for (final url in urls) {
      final result = await repo
          .upsertRemote(url, userOverride: _accountUserOverride(existingAccountProfile), active: true)
          .run();
      final imported = result.match((failure) {
        lastFailure = failure;
        return false;
      }, (_) => true);
      if (imported) {
        return;
      }
    }
    final failure = lastFailure;
    if (failure != null) {
      throw failure;
    }
  }

  Future<RemoteProfileEntity?> _deleteAccountProfiles(
    ProfileRepository repo, {
    List<String> activeUrls = const [],
  }) async {
    final profiles = await repo
        .watchAll(sortMode: SortMode.descending)
        .map((event) => event.getOrElse((failure) => throw failure))
        .first;
    RemoteProfileEntity? existingAccountProfile;
    for (final profile in profiles.where((profile) => _isAccountProfile(profile, activeUrls: activeUrls))) {
      if (profile is RemoteProfileEntity && _matchesSubscriptionUrls(profile.url, activeUrls)) {
        existingAccountProfile ??= profile;
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

  bool _isAccountProfile(ProfileEntity profile, {List<String> activeUrls = const []}) {
    return switch (profile) {
      RemoteProfileEntity(:final name, :final url, :final userOverride) =>
        name == accountProfileName ||
            userOverride?.name == accountProfileName ||
            _matchesSubscriptionUrls(url, activeUrls),
      LocalProfileEntity(:final name, :final userOverride) =>
        name == accountProfileName || userOverride?.name == accountProfileName,
    };
  }
}

bool _matchesSubscriptionUrls(String url, Iterable<String> candidates) {
  return candidates.any((candidate) => _sameSubscriptionUrl(url, candidate));
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
