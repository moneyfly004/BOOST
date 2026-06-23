import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_notifier.dart';
import 'package:hiddify/features/account/notifier/account_subscription_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'restore refreshes expired access token and syncs subscription',
    () async {
      const savedUser = AccountUser(
        id: 1,
        username: 'saved',
        email: 'saved@example.com',
      );
      SharedPreferences.setMockInitialValues({
        'boost_account_access_token': 'expired-access-token',
        'boost_account_refresh_token': 'valid-refresh-token',
        'boost_account_user': jsonEncode(savedUser.toJson()),
      });

      final preferences = await SharedPreferences.getInstance();
      final api = _RefreshingAccountApi();
      final sync = _FakeSubscriptionSync();

      final notifier = AccountNotifier(api, sync, preferences);
      await pumpEventQueue();

      expect(api.dashboardTokens, [
        'expired-access-token',
        'fresh-access-token',
      ]);
      expect(api.refreshTokenCalls, 1);
      expect(api.refreshTokens, ['valid-refresh-token']);
      expect(sync.syncCalls, 1);
      expect(sync.clearCalls, 0);
      expect(api.deviceTokens, ['expired-access-token', 'fresh-access-token']);
      expect(notifier.state.deviceTotal, 1);
      expect(notifier.state.devices.single.deviceName, 'MacBook');
      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.token, 'fresh-access-token');
      expect(notifier.state.refreshToken, 'fresh-refresh-token');
      expect(
        preferences.getString('boost_account_access_token'),
        'fresh-access-token',
      );
      expect(
        preferences.getString('boost_account_refresh_token'),
        'fresh-refresh-token',
      );
    },
  );

  test(
    'manual sync refreshes expired access token and preserves stored subscription until success',
    () async {
      const savedUser = AccountUser(
        id: 1,
        username: 'saved',
        email: 'saved@example.com',
      );
      SharedPreferences.setMockInitialValues({
        'boost_account_access_token': 'expired-access-token',
        'boost_account_refresh_token': 'valid-refresh-token',
        'boost_account_user': jsonEncode(savedUser.toJson()),
      });

      final preferences = await SharedPreferences.getInstance();
      final api = _RefreshingAccountApi();
      final sync = _FakeSubscriptionSync();

      final notifier = AccountNotifier(api, sync, preferences);
      await pumpEventQueue();

      api.reset();
      sync.reset();
      api.expireFreshTokenOnce();

      await notifier.syncSubscription();

      expect(api.dashboardTokens, ['fresh-access-token', 'fresh-access-token']);
      expect(api.refreshTokenCalls, 1);
      expect(api.refreshTokens, ['fresh-refresh-token']);
      expect(api.deviceTokens, isEmpty);
      expect(sync.syncCalls, 1);
      expect(sync.clearCalls, 0);
      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.token, 'fresh-access-token');
      expect(notifier.state.refreshToken, 'fresh-refresh-token');
    },
  );

  test(
    'concurrent manual sync shares the same account refresh operation',
    () async {
      const savedUser = AccountUser(
        id: 1,
        username: 'saved',
        email: 'saved@example.com',
      );
      SharedPreferences.setMockInitialValues({
        'boost_account_access_token': 'fresh-access-token',
        'boost_account_refresh_token': 'fresh-refresh-token',
        'boost_account_user': jsonEncode(savedUser.toJson()),
      });

      final preferences = await SharedPreferences.getInstance();
      final api = _RefreshingAccountApi();
      final sync = _FakeSubscriptionSync();

      final notifier = AccountNotifier(api, sync, preferences);
      await pumpEventQueue();
      api.reset();
      sync.reset();
      api.holdDashboards = true;

      final firstSync = notifier.syncSubscription();
      final secondSync = notifier.syncSubscription();
      await pumpEventQueue();

      expect(api.dashboardTokens, ['fresh-access-token']);
      api.releaseDashboards();
      await Future.wait([firstSync, secondSync]);

      expect(sync.syncCalls, 1);
    },
  );

  test(
    'expired refresh token marks auth expired without clearing local subscription',
    () async {
      const savedUser = AccountUser(
        id: 1,
        username: 'saved',
        email: 'saved@example.com',
      );
      SharedPreferences.setMockInitialValues({
        'boost_account_access_token': 'expired-access-token',
        'boost_account_refresh_token': 'invalid-refresh-token',
        'boost_account_user': jsonEncode(savedUser.toJson()),
      });

      final preferences = await SharedPreferences.getInstance();
      final api = _RefreshingAccountApi()
        ..refreshFailure = AccountApiException(
          'invalid refresh token',
          statusCode: 401,
        );
      final sync = _FakeSubscriptionSync();

      final notifier = AccountNotifier(api, sync, preferences);
      await pumpEventQueue();

      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.authExpired, isTrue);
      expect(sync.syncCalls, 0);
      expect(sync.clearCalls, 0);
      expect(
        preferences.getString('boost_account_refresh_token'),
        'invalid-refresh-token',
      );
    },
  );

  test(
    'silent subscription status refresh syncs active subscription from dashboard',
    () async {
      const savedUser = AccountUser(
        id: 1,
        username: 'saved',
        email: 'saved@example.com',
      );
      SharedPreferences.setMockInitialValues({
        'boost_account_access_token': 'fresh-access-token',
        'boost_account_refresh_token': 'fresh-refresh-token',
        'boost_account_user': jsonEncode(savedUser.toJson()),
      });

      final preferences = await SharedPreferences.getInstance();
      final api = _RefreshingAccountApi();
      final sync = _FakeSubscriptionSync();

      final notifier = AccountNotifier(api, sync, preferences);
      await pumpEventQueue();
      api.reset();
      sync.reset();

      await notifier.refreshSubscriptionStatusSilently();

      expect(api.dashboardTokens, ['fresh-access-token']);
      expect(api.deviceTokens, isEmpty);
      expect(sync.refreshActiveCalls, 1);
      expect(sync.syncCalls, 0);
      expect(notifier.state.authExpired, isFalse);
    },
  );
}

class _RefreshingAccountApi extends AccountApi {
  _RefreshingAccountApi() : super(baseUrl: 'https://example.invalid');

  final List<String> dashboardTokens = [];
  final List<String> deviceTokens = [];
  final List<String> refreshTokens = [];
  int refreshTokenCalls = 0;
  bool _expireFreshTokenOnce = false;
  bool holdDashboards = false;
  AccountApiException? refreshFailure;
  Completer<void>? _dashboardRelease;

  void reset() {
    dashboardTokens.clear();
    deviceTokens.clear();
    refreshTokens.clear();
    refreshTokenCalls = 0;
    _expireFreshTokenOnce = false;
    holdDashboards = false;
    refreshFailure = null;
    _dashboardRelease = null;
  }

  void expireFreshTokenOnce() {
    _expireFreshTokenOnce = true;
  }

  void releaseDashboards() {
    _dashboardRelease?.complete();
    _dashboardRelease = null;
  }

  @override
  Future<AccountAuthResponse> refreshToken(String refreshToken) async {
    refreshTokenCalls++;
    refreshTokens.add(refreshToken);
    final failure = refreshFailure;
    if (failure != null) {
      throw failure;
    }
    return AccountAuthResponse(
      accessToken: 'fresh-access-token',
      refreshToken: 'fresh-refresh-token',
      user: const AccountUser(
        id: 1,
        username: 'fresh',
        email: 'fresh@example.com',
      ),
    );
  }

  @override
  Future<AccountDashboard> getDashboard(String token) async {
    dashboardTokens.add(token);
    if (holdDashboards) {
      _dashboardRelease ??= Completer<void>();
      await _dashboardRelease!.future;
    }
    if (token == 'expired-access-token' || _expireFreshTokenOnce) {
      _expireFreshTokenOnce = false;
      throw AccountApiException('expired', statusCode: 401);
    }
    return const AccountDashboard(
      user: AccountUser(id: 1, username: 'fresh', email: 'fresh@example.com'),
    );
  }

  @override
  Future<List<AccountPackage>> getPackages() async {
    return const [];
  }

  @override
  Future<List<PaymentMethod>> getPaymentMethods() async {
    return const [];
  }

  @override
  Future<List<AccountOrder>> getOrders(String token) async {
    return const [];
  }

  @override
  Future<AccountDevicesResult> getDevices(
    String token, {
    int page = 1,
    int size = 100,
  }) async {
    deviceTokens.add(token);
    return AccountDevicesResult(
      devices: const [
        AccountDevice(id: 1, deviceName: 'MacBook', deviceType: 'desktop'),
      ],
    );
  }
}

class _FakeSubscriptionSync implements AccountSubscriptionSync {
  int clearCalls = 0;
  int refreshActiveCalls = 0;
  int syncCalls = 0;

  void reset() {
    clearCalls = 0;
    refreshActiveCalls = 0;
    syncCalls = 0;
  }

  @override
  Future<void> clearAccountSubscriptions() async {
    clearCalls++;
  }

  @override
  Future<void> refreshActiveSubscription(AccountDashboard? dashboard) async {
    refreshActiveCalls++;
  }

  @override
  Future<void> sync(AccountDashboard? dashboard) async {
    syncCalls++;
  }
}
