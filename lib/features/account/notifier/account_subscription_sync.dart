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

  Future<void> clearAccountSubscriptions() async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    await _deleteExistingProfiles(repo);
  }

  Future<void> sync(AccountDashboard? dashboard) async {
    final subscription = dashboard?.subscription;
    final url = subscription?.importUrl ?? '';
    final repo = await _ref.read(profileRepositoryProvider.future);
    await _deleteExistingProfiles(repo);
    if (subscription == null || !subscription.canImport || !_isUniversalSubscriptionUrl(url)) {
      return;
    }

    await repo
        .upsertRemote(
          url,
          userOverride: UserOverride(name: _profileName(subscription), updateInterval: 1),
          active: true,
        )
        .getOrElse((failure) => throw failure)
        .run();
  }

  Future<void> refreshActiveSubscription(AccountDashboard? dashboard) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    await _deleteExistingProfiles(repo);
    final subscription = dashboard?.subscription;
    final activeUrl = subscription?.importUrl ?? '';
    if (subscription == null || !subscription.canImport || !_isUniversalSubscriptionUrl(activeUrl)) {
      return;
    }
    await repo
        .upsertRemote(
          activeUrl,
          userOverride: UserOverride(name: _profileName(subscription), updateInterval: 1),
          active: true,
        )
        .getOrElse((failure) => throw failure)
        .run();
  }

  bool _isUniversalSubscriptionUrl(String url) {
    return url.contains('/subscriptions/universal/');
  }

  Future<void> _deleteExistingProfiles(ProfileRepository repo) async {
    final profiles = await repo
        .watchAll(sortMode: SortMode.descending)
        .map((event) => event.getOrElse((failure) => throw failure))
        .first;
    for (final profile in profiles) {
      await repo.deleteById(profile.id, profile.active).getOrElse((failure) => throw failure).run();
    }
  }

  String _profileName(AccountSubscription subscription) {
    if (subscription.packageName.isNotEmpty) {
      return subscription.packageName;
    }
    return 'MoneyFly 账户订阅';
  }
}
