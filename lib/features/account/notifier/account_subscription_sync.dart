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
  static const accountProfileName = 'MoneyFly 账户订阅';

  Future<void> clearAccountSubscriptions() async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    await _deleteAccountProfiles(repo);
  }

  Future<void> sync(AccountDashboard? dashboard) async {
    final subscription = dashboard?.subscription;
    final url = subscription?.importUrl ?? '';
    final repo = await _ref.read(profileRepositoryProvider.future);
    await _deleteAccountProfiles(repo, activeUrl: url);
    if (subscription == null || !subscription.hasImportUrl || !_isUniversalSubscriptionUrl(url)) {
      return;
    }

    await repo
        .upsertRemote(url, userOverride: const UserOverride(name: accountProfileName, updateInterval: 1), active: true)
        .getOrElse((failure) => throw failure)
        .run();
  }

  Future<void> refreshActiveSubscription(AccountDashboard? dashboard) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    final subscription = dashboard?.subscription;
    final activeUrl = subscription?.importUrl ?? '';
    await _deleteAccountProfiles(repo, activeUrl: activeUrl);
    if (subscription == null || !subscription.hasImportUrl || !_isUniversalSubscriptionUrl(activeUrl)) {
      return;
    }
    await repo
        .upsertRemote(
          activeUrl,
          userOverride: const UserOverride(name: accountProfileName, updateInterval: 1),
          active: true,
        )
        .getOrElse((failure) => throw failure)
        .run();
  }

  bool _isUniversalSubscriptionUrl(String url) {
    return url.contains('/subscriptions/universal/');
  }

  Future<void> _deleteAccountProfiles(ProfileRepository repo, {String? activeUrl}) async {
    final profiles = await repo
        .watchAll(sortMode: SortMode.descending)
        .map((event) => event.getOrElse((failure) => throw failure))
        .first;
    for (final profile in profiles.where((profile) => _isAccountProfile(profile, activeUrl: activeUrl))) {
      await repo.deleteById(profile.id, profile.active).getOrElse((failure) => throw failure).run();
    }
  }

  bool _isAccountProfile(ProfileEntity profile, {String? activeUrl}) {
    return switch (profile) {
      RemoteProfileEntity(:final name, :final url, :final userOverride) =>
        name == accountProfileName ||
            userOverride?.name == accountProfileName ||
            (activeUrl != null && activeUrl.isNotEmpty && url == activeUrl) ||
            _isLegacyAccountProfile(name: name, url: url, userOverride: userOverride),
      LocalProfileEntity(:final name, :final userOverride) =>
        name == accountProfileName || userOverride?.name == accountProfileName,
    };
  }

  bool _isLegacyAccountProfile({required String name, required String url, required UserOverride? userOverride}) {
    if (userOverride?.name != name || userOverride?.updateInterval != 1) {
      return false;
    }
    final uri = Uri.tryParse(url);
    return uri != null &&
        _isKnownAccountSubscriptionHost(uri.host) &&
        uri.pathSegments.contains('subscriptions') &&
        uri.pathSegments.contains('universal');
  }

  bool _isKnownAccountSubscriptionHost(String host) {
    final apiHost = Uri.tryParse(kCBoardApiBaseUrl)?.host;
    return host == 'dy.moneyfly.top' || (apiHost != null && apiHost.isNotEmpty && host == apiHost);
  }
}
