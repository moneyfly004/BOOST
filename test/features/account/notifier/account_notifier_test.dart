import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_notifier.dart';
import 'package:hiddify/features/account/notifier/account_subscription_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('restore refreshes expired access token and syncs subscription', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
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

    expect(api.dashboardTokens, ['expired-access-token', 'fresh-access-token']);
    expect(api.refreshTokenCalls, 1);
    expect(api.refreshTokens, ['valid-refresh-token']);
    expect(sync.syncCalls, 1);
    expect(sync.clearCalls, 0);
    expect(api.deviceTokens, ['fresh-access-token']);
    expect(notifier.state.deviceTotal, 1);
    expect(notifier.state.devices.single.deviceName, 'MacBook');
    expect(notifier.state.isAuthenticated, isTrue);
    expect(notifier.state.token, 'fresh-access-token');
    expect(notifier.state.refreshToken, 'fresh-refresh-token');
    expect(preferences.getString('boost_account_access_token'), 'fresh-access-token');
    expect(preferences.getString('boost_account_refresh_token'), 'fresh-refresh-token');
  });

  test('login stores credentials for startup auto login', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = await SharedPreferences.getInstance();
    final api = _RefreshingAccountApi();
    final sync = _FakeSubscriptionSync();

    final notifier = AccountNotifier(api, sync, preferences);
    await pumpEventQueue();
    sync.reset();

    await notifier.login(' fresh@example.com ', 'password');

    expect(api.loginEmails, ['fresh@example.com']);
    expect(api.loginPasswords, ['password']);
    expect(preferences.getString('boost_account_email'), 'fresh@example.com');
    expect(preferences.getString('boost_account_password'), 'password');
    expect(preferences.getString('boost_account_access_token'), 'fresh-access-token');
    expect(notifier.state.isAuthenticated, isTrue);
  });

  test('restore uses saved credentials to auto login and refresh subscription', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
    SharedPreferences.setMockInitialValues({
      'boost_account_access_token': 'expired-access-token',
      'boost_account_refresh_token': 'invalid-refresh-token',
      'boost_account_user': jsonEncode(savedUser.toJson()),
      'boost_account_email': 'saved@example.com',
      'boost_account_password': 'saved-password',
    });

    final preferences = await SharedPreferences.getInstance();
    final api = _RefreshingAccountApi()..refreshFailure = AccountApiException('invalid refresh token', statusCode: 401);
    final sync = _FakeSubscriptionSync();

    final notifier = AccountNotifier(api, sync, preferences);
    await pumpEventQueue();

    expect(api.loginEmails, ['saved@example.com']);
    expect(api.loginPasswords, ['saved-password']);
    expect(api.dashboardTokens, ['fresh-access-token']);
    expect(sync.syncCalls, 1);
    expect(notifier.state.isAuthenticated, isTrue);
    expect(notifier.state.authExpired, isFalse);
    expect(notifier.state.token, 'fresh-access-token');
    expect(preferences.getString('boost_account_email'), 'saved@example.com');
    expect(preferences.getString('boost_account_password'), 'saved-password');
  });

  test('restore auto logs in with saved credentials when tokens are missing', () async {
    SharedPreferences.setMockInitialValues({
      'boost_account_email': 'saved@example.com',
      'boost_account_password': 'saved-password',
    });

    final preferences = await SharedPreferences.getInstance();
    final api = _RefreshingAccountApi();
    final sync = _FakeSubscriptionSync();

    final notifier = AccountNotifier(api, sync, preferences);
    await pumpEventQueue();

    expect(api.loginEmails, ['saved@example.com']);
    expect(api.loginPasswords, ['saved-password']);
    expect(api.dashboardTokens, ['fresh-access-token']);
    expect(sync.syncCalls, 1);
    expect(notifier.state.isAuthenticated, isTrue);
    expect(preferences.getString('boost_account_access_token'), 'fresh-access-token');
  });

  test('login still syncs subscription when optional account data fails', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = await SharedPreferences.getInstance();
    final api = _RefreshingAccountApi()
      ..ordersFailure = AccountApiException('orders unavailable', statusCode: 500)
      ..devicesFailure = AccountApiException('devices unavailable', statusCode: 500);
    final sync = _FakeSubscriptionSync();

    final notifier = AccountNotifier(api, sync, preferences);
    await pumpEventQueue();
    sync.reset();

    await notifier.login('fresh@example.com', 'password');

    expect(api.loginEmails, ['fresh@example.com']);
    expect(api.dashboardTokens, ['fresh-access-token']);
    expect(api.deviceTokens, ['fresh-access-token']);
    expect(sync.syncCalls, 1);
    expect(notifier.state.isAuthenticated, isTrue);
    expect(notifier.state.devices, isEmpty);
  });

  test('login uses saved credentials when optional refresh hits authorization failure', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = await SharedPreferences.getInstance();
    final api = _RefreshingAccountApi()
      ..devicesFailure = AccountApiException('device token expired', statusCode: 401)
      ..refreshFailure = AccountApiException('refresh token expired', statusCode: 401);
    final sync = _FakeSubscriptionSync();

    final notifier = AccountNotifier(api, sync, preferences);
    await pumpEventQueue();
    sync.reset();

    await notifier.login('fresh@example.com', 'password');

    expect(sync.syncCalls, 1);
    expect(api.loginEmails, ['fresh@example.com', 'fresh@example.com']);
    expect(api.loginPasswords, ['password', 'password']);
    expect(notifier.state.authExpired, isFalse);
  });

  test('manual sync refreshes expired access token and preserves stored subscription until success', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
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
  });

  test('concurrent manual sync shares the same account refresh operation', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
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
  });

  test('expired refresh token marks auth expired without clearing local subscription', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
    SharedPreferences.setMockInitialValues({
      'boost_account_access_token': 'expired-access-token',
      'boost_account_refresh_token': 'invalid-refresh-token',
      'boost_account_user': jsonEncode(savedUser.toJson()),
    });

    final preferences = await SharedPreferences.getInstance();
    final api = _RefreshingAccountApi()..refreshFailure = AccountApiException('invalid refresh token', statusCode: 401);
    final sync = _FakeSubscriptionSync();

    final notifier = AccountNotifier(api, sync, preferences);
    await pumpEventQueue();

    expect(notifier.state.isAuthenticated, isTrue);
    expect(notifier.state.authExpired, isTrue);
    expect(sync.syncCalls, 0);
    expect(sync.clearCalls, 0);
    expect(preferences.getString('boost_account_refresh_token'), 'invalid-refresh-token');
  });

  test('saved credential auto login failure clears account subscription but keeps credentials', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
    SharedPreferences.setMockInitialValues({
      'boost_account_access_token': 'expired-access-token',
      'boost_account_refresh_token': 'invalid-refresh-token',
      'boost_account_user': jsonEncode(savedUser.toJson()),
      'boost_account_email': 'saved@example.com',
      'boost_account_password': 'saved-password',
    });

    final preferences = await SharedPreferences.getInstance();
    final api = _RefreshingAccountApi()
      ..refreshFailure = AccountApiException('invalid refresh token', statusCode: 401)
      ..loginFailure = AccountApiException('account disabled', statusCode: 403);
    final sync = _FakeSubscriptionSync();

    final notifier = AccountNotifier(api, sync, preferences);
    await pumpEventQueue();

    expect(api.loginEmails, ['saved@example.com']);
    expect(sync.clearCalls, 1);
    expect(notifier.state.isAuthenticated, isTrue);
    expect(notifier.state.authExpired, isTrue);
    expect(preferences.getString('boost_account_email'), 'saved@example.com');
    expect(preferences.getString('boost_account_password'), 'saved-password');
  });

  test('logout clears local account state when remote logout fails', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
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
    api.logoutFailure = AccountApiException('remote logout failed', statusCode: 500);

    await notifier.logout();

    expect(api.logoutTokens, ['fresh-access-token']);
    expect(api.logoutRefreshTokens, ['fresh-refresh-token']);
    expect(sync.clearCalls, 1);
    expect(notifier.state.isAuthenticated, isFalse);
    expect(notifier.state.message, '已退出登录');
    expect(preferences.getString('boost_account_access_token'), isNull);
    expect(preferences.getString('boost_account_refresh_token'), isNull);
    expect(preferences.getString('boost_account_user'), isNull);
    expect(preferences.getString('boost_account_email'), isNull);
    expect(preferences.getString('boost_account_password'), isNull);
  });

  test('shutdown cleanup removes account subscriptions without deleting saved credentials', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
    SharedPreferences.setMockInitialValues({
      'boost_account_access_token': 'fresh-access-token',
      'boost_account_refresh_token': 'fresh-refresh-token',
      'boost_account_user': jsonEncode(savedUser.toJson()),
      'boost_account_email': 'saved@example.com',
      'boost_account_password': 'saved-password',
    });

    final preferences = await SharedPreferences.getInstance();
    final api = _RefreshingAccountApi();
    final sync = _FakeSubscriptionSync();

    final notifier = AccountNotifier(api, sync, preferences);
    await pumpEventQueue();
    api.reset();
    sync.reset();

    await notifier.clearAccountSubscriptionsForShutdown();

    expect(sync.clearCalls, 1);
    expect(notifier.state.isAuthenticated, isTrue);
    expect(preferences.getString('boost_account_email'), 'saved@example.com');
    expect(preferences.getString('boost_account_password'), 'saved-password');
  });

  test('silent subscription status refresh syncs active subscription from dashboard', () async {
    const savedUser = AccountUser(id: 1, username: 'saved', email: 'saved@example.com');
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
  });
}

class _RefreshingAccountApi extends AccountApi {
  _RefreshingAccountApi() : super(baseUrl: 'https://example.invalid');

  final List<String> dashboardTokens = [];
  final List<String> deviceTokens = [];
  final List<String> refreshTokens = [];
  final List<String> logoutTokens = [];
  final List<String?> logoutRefreshTokens = [];
  final List<String> loginEmails = [];
  final List<String> loginPasswords = [];
  int refreshTokenCalls = 0;
  bool _expireFreshTokenOnce = false;
  bool holdDashboards = false;
  AccountApiException? loginFailure;
  AccountApiException? refreshFailure;
  AccountApiException? logoutFailure;
  AccountApiException? ordersFailure;
  AccountApiException? devicesFailure;
  Completer<void>? _dashboardRelease;

  void reset() {
    dashboardTokens.clear();
    deviceTokens.clear();
    refreshTokens.clear();
    logoutTokens.clear();
    logoutRefreshTokens.clear();
    loginEmails.clear();
    loginPasswords.clear();
    refreshTokenCalls = 0;
    _expireFreshTokenOnce = false;
    holdDashboards = false;
    loginFailure = null;
    refreshFailure = null;
    logoutFailure = null;
    ordersFailure = null;
    devicesFailure = null;
    _dashboardRelease = null;
  }

  void expireFreshTokenOnce() {
    _expireFreshTokenOnce = true;
  }

  @override
  Future<AccountAuthResponse> login({required String email, required String password}) async {
    loginEmails.add(email);
    loginPasswords.add(password);
    final failure = loginFailure;
    if (failure != null) {
      throw failure;
    }
    return AccountAuthResponse(
      accessToken: 'fresh-access-token',
      refreshToken: 'fresh-refresh-token',
      user: const AccountUser(id: 1, username: 'fresh', email: 'fresh@example.com'),
    );
  }

  @override
  Future<String> logout({required String token, String? refreshToken}) async {
    logoutTokens.add(token);
    logoutRefreshTokens.add(refreshToken);
    final failure = logoutFailure;
    if (failure != null) {
      throw failure;
    }
    return '已登出';
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
      user: const AccountUser(id: 1, username: 'fresh', email: 'fresh@example.com'),
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
    final failure = ordersFailure;
    if (failure != null) {
      throw failure;
    }
    return const [];
  }

  @override
  Future<AccountDevicesResult> getDevices(String token, {int page = 1, int size = 100}) async {
    deviceTokens.add(token);
    final failure = devicesFailure;
    if (failure != null) {
      throw failure;
    }
    return AccountDevicesResult(
      devices: const [AccountDevice(id: 1, deviceName: 'MacBook', deviceType: 'desktop')],
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
