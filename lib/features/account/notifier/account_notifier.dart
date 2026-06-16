import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_subscription_sync.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final accountApiProvider = Provider<AccountApi>((ref) => AccountApi());

final accountNotifierProvider = StateNotifierProvider<AccountNotifier, AccountState>((ref) {
  return AccountNotifier(
    ref.watch(accountApiProvider),
    ref.watch(accountSubscriptionSyncProvider),
    ref.watch(sharedPreferencesProvider).requireValue,
  );
});

class AccountState {
  const AccountState({
    this.token,
    this.refreshToken,
    this.user,
    this.dashboard,
    this.packages = const [],
    this.paymentMethods = const [],
    this.orders = const [],
    this.loading = false,
    this.syncingSubscription = false,
    this.message,
  });

  final String? token;
  final String? refreshToken;
  final AccountUser? user;
  final AccountDashboard? dashboard;
  final List<AccountPackage> packages;
  final List<PaymentMethod> paymentMethods;
  final List<AccountOrder> orders;
  final bool loading;
  final bool syncingSubscription;
  final String? message;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  AccountState copyWith({
    String? token,
    String? refreshToken,
    AccountUser? user,
    AccountDashboard? dashboard,
    List<AccountPackage>? packages,
    List<PaymentMethod>? paymentMethods,
    List<AccountOrder>? orders,
    bool? loading,
    bool? syncingSubscription,
    String? message,
    bool clearAuth = false,
  }) {
    return AccountState(
      token: clearAuth ? null : token ?? this.token,
      refreshToken: clearAuth ? null : refreshToken ?? this.refreshToken,
      user: clearAuth ? null : user ?? this.user,
      dashboard: clearAuth ? null : dashboard ?? this.dashboard,
      packages: packages ?? this.packages,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      orders: orders ?? this.orders,
      loading: loading ?? this.loading,
      syncingSubscription: syncingSubscription ?? this.syncingSubscription,
      message: message,
    );
  }
}

class AccountNotifier extends StateNotifier<AccountState> {
  AccountNotifier(this._api, this._subscriptionSync, this._preferences) : super(const AccountState()) {
    _restore();
  }

  final AccountApi _api;
  final AccountSubscriptionSync _subscriptionSync;
  final SharedPreferences _preferences;

  static const _tokenKey = 'cboard_account_access_token';
  static const _refreshTokenKey = 'cboard_account_refresh_token';
  static const _userKey = 'cboard_account_user';

  Future<void> login(String email, String password) async {
    await _run(() async {
      await _subscriptionSync.clearAccountSubscriptions();
      final response = await _api.login(email: email.trim(), password: password);
      state = state.copyWith(token: response.accessToken, refreshToken: response.refreshToken, user: response.user);
      await _persistAuth(response.accessToken, response.refreshToken, response.user);
      await refresh();
    });
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? verificationCode,
    String? inviteCode,
  }) async {
    await _run(() async {
      await _subscriptionSync.clearAccountSubscriptions();
      final response = await _api.register(
        username: username.trim(),
        email: email.trim(),
        password: password,
        verificationCode: verificationCode?.trim(),
        inviteCode: inviteCode?.trim(),
      );
      state = state.copyWith(token: response.accessToken, refreshToken: response.refreshToken, user: response.user);
      await _persistAuth(response.accessToken, response.refreshToken, response.user);
      await refresh();
    });
  }

  Future<String> sendRegisterCode(String email) {
    return _runWithResult(() => _api.sendRegisterCode(email.trim()));
  }

  Future<String> forgotPassword(String email) {
    return _runWithResult(() => _api.forgotPassword(email.trim()));
  }

  Future<String> resetPassword({required String email, required String verificationCode, required String newPassword}) {
    return _runWithResult(
      () =>
          _api.resetPassword(email: email.trim(), verificationCode: verificationCode.trim(), newPassword: newPassword),
    );
  }

  Future<void> refresh() async {
    final token = state.token;
    if (token == null || token.isEmpty) {
      await loadPublicData();
      return;
    }
    await _run(() async {
      await _subscriptionSync.clearAccountSubscriptions();
      final results = await Future.wait<Object>([
        _api.getDashboard(token),
        _api.getPackages(),
        _api.getPaymentMethods(),
        _api.getOrders(token),
      ]);
      final dashboard = results[0] as AccountDashboard;
      state = state.copyWith(
        user: dashboard.user,
        dashboard: dashboard,
        packages: results[1] as List<AccountPackage>,
        paymentMethods: results[2] as List<PaymentMethod>,
        orders: results[3] as List<AccountOrder>,
      );
      await _persistAuth(token, state.refreshToken, dashboard.user);
      await _syncSubscription(dashboard);
    });
  }

  Future<void> syncSubscription() async {
    final token = _requireToken();
    await _run(() async {
      await _subscriptionSync.clearAccountSubscriptions();
      final dashboard = await _api.getDashboard(token);
      state = state.copyWith(user: dashboard.user, dashboard: dashboard);
      await _persistAuth(token, state.refreshToken, dashboard.user);
      await _syncSubscription(dashboard, successMessage: '订阅已同步');
    });
  }

  Future<void> refreshActiveSubscription() async {
    final token = _requireToken();
    await _run(() async {
      state = state.copyWith(syncingSubscription: true);
      await _subscriptionSync.clearAccountSubscriptions();
      final dashboard = await _api.getDashboard(token);
      state = state.copyWith(user: dashboard.user, dashboard: dashboard);
      await _persistAuth(token, state.refreshToken, dashboard.user);
      await _subscriptionSync.refreshActiveSubscription(dashboard);
      state = state.copyWith(syncingSubscription: false, message: '订阅已更新');
    });
  }

  Future<void> loadPublicData() async {
    await _run(() async {
      final results = await Future.wait<Object>([_api.getPackages(), _api.getPaymentMethods()]);
      state = state.copyWith(
        packages: results[0] as List<AccountPackage>,
        paymentMethods: results[1] as List<PaymentMethod>,
      );
    });
  }

  Future<void> updateProfile({required String displayName, required String phone, required String bio}) async {
    final token = _requireToken();
    await _run(() async {
      final user = await _api.updateProfile(
        token: token,
        displayName: displayName.trim(),
        phone: phone.trim(),
        bio: bio.trim(),
      );
      state = state.copyWith(user: user, message: '个人信息已更新');
      await _persistAuth(token, state.refreshToken, user);
      await refresh();
    });
  }

  Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    final token = _requireToken();
    final message = await _runWithResult(
      () => _api.changePassword(token: token, oldPassword: oldPassword, newPassword: newPassword),
    );
    state = state.copyWith(message: message);
  }

  Future<OrderResult> buyPackage({required AccountPackage package, PaymentMethod? paymentMethod}) {
    final token = _requireToken();
    return _runWithResult(() async {
      final order = await _api.createOrder(token: token, packageId: package.id, paymentMethod: paymentMethod?.key);
      OrderResult result = order;
      if ((result.paymentUrl == null || result.paymentUrl!.isEmpty) && paymentMethod != null && order.id > 0) {
        result = await _api.createPayment(token: token, orderId: order.id, paymentMethodId: paymentMethod.id);
      }
      await refresh();
      return result;
    });
  }

  Future<OrderResult> createPackageOrder(AccountPackage package) {
    final token = _requireToken();
    return _runWithResult(() => _api.createOrder(token: token, packageId: package.id));
  }

  Future<OrderResult> createOrderPayment({required int orderId, required PaymentMethod paymentMethod}) {
    final token = _requireToken();
    return _runWithResult(() => _api.createPayment(token: token, orderId: orderId, paymentMethodId: paymentMethod.id));
  }

  Future<AccountOrderStatus> checkOrderStatus(String orderNo) {
    final token = _requireToken();
    return _api.getOrderStatus(token: token, orderNo: orderNo);
  }

  Future<void> refreshAfterPayment() async {
    await refresh();
  }

  Future<void> logout() async {
    state = state.copyWith(loading: true);
    try {
      await _subscriptionSync.clearAccountSubscriptions();
      await _preferences.remove(_tokenKey);
      await _preferences.remove(_refreshTokenKey);
      await _preferences.remove(_userKey);
      state = AccountState(packages: state.packages, paymentMethods: state.paymentMethods, message: '已退出登录');
    } catch (_) {
      state = state.copyWith(loading: false);
      rethrow;
    }
  }

  Future<void> _syncSubscription(AccountDashboard dashboard, {String? successMessage}) async {
    state = state.copyWith(syncingSubscription: true);
    try {
      await _subscriptionSync.sync(dashboard);
      state = state.copyWith(syncingSubscription: false, message: successMessage);
    } catch (_) {
      state = state.copyWith(syncingSubscription: false);
      rethrow;
    }
  }

  void _restore() {
    final token = _preferences.getString(_tokenKey);
    final refreshToken = _preferences.getString(_refreshTokenKey);
    final userRaw = _preferences.getString(_userKey);
    AccountUser? user;
    if (userRaw != null && userRaw.isNotEmpty) {
      try {
        final json = jsonDecode(userRaw);
        if (json is Map<String, dynamic>) {
          user = AccountUser.fromJson(json);
        }
      } catch (_) {
        _preferences.remove(_userKey);
      }
    }
    if (token != null && token.isNotEmpty) {
      state = state.copyWith(token: token, refreshToken: refreshToken, user: user);
      Future.microtask(() => refresh());
    } else if (refreshToken != null && refreshToken.isNotEmpty) {
      Future.microtask(() => _refreshAccessToken(refreshToken));
    } else {
      Future.microtask(() async {
        await _subscriptionSync.clearAccountSubscriptions();
        await loadPublicData();
      });
    }
  }

  Future<void> _refreshAccessToken(String refreshToken) async {
    await _run(() async {
      final response = await _api.refreshToken(refreshToken);
      state = state.copyWith(
        token: response.accessToken,
        refreshToken: response.refreshToken ?? refreshToken,
        user: response.user.id == 0 ? state.user : response.user,
      );
      await _persistAuth(state.token, state.refreshToken, state.user);
      await refresh();
    });
  }

  Future<void> _persistAuth(String? token, String? refreshToken, AccountUser? user) async {
    if (token != null && token.isNotEmpty) {
      await _preferences.setString(_tokenKey, token);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _preferences.setString(_refreshTokenKey, refreshToken);
    }
    if (user != null) {
      await _preferences.setString(_userKey, jsonEncode(user.toJson()));
    }
  }

  String _requireToken() {
    final token = state.token;
    if (token == null || token.isEmpty) {
      throw AccountApiException('请先登录');
    }
    return token;
  }

  Future<void> _run(Future<void> Function() action) async {
    state = state.copyWith(loading: true);
    try {
      await action();
      state = state.copyWith(loading: false, syncingSubscription: false);
    } catch (error) {
      state = state.copyWith(loading: false, syncingSubscription: false);
      rethrow;
    }
  }

  Future<T> _runWithResult<T>(Future<T> Function() action) async {
    state = state.copyWith(loading: true);
    try {
      final result = await action();
      state = state.copyWith(loading: false, syncingSubscription: false);
      return result;
    } catch (error) {
      state = state.copyWith(loading: false, syncingSubscription: false);
      rethrow;
    }
  }
}
