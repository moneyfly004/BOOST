import 'package:dio/dio.dart';

const kCBoardApiBaseUrl = String.fromEnvironment('CBOARD_API_BASE_URL', defaultValue: 'https://dy.moneyfly.top/api/v1');

class AccountApiException implements Exception {
  AccountApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AccountApi {
  AccountApi({Dio? dio, String baseUrl = kCBoardApiBaseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  Future<AccountAuthResponse> login({required String email, required String password}) async {
    final data = await _post('/auth/login', data: {'email': email, 'password': password});
    return AccountAuthResponse.fromJson(data);
  }

  Future<AccountAuthResponse> refreshToken(String refreshToken) async {
    final data = await _post('/auth/refresh', data: {'refresh_token': refreshToken});
    return AccountAuthResponse.fromJson(data);
  }

  Future<AccountAuthResponse> register({
    required String username,
    required String email,
    required String password,
    String? verificationCode,
    String? inviteCode,
  }) async {
    final data = await _post(
      '/auth/register',
      data: {
        'username': username,
        'email': email,
        'password': password,
        if (verificationCode != null && verificationCode.isNotEmpty) 'verification_code': verificationCode,
        if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
      },
    );
    return AccountAuthResponse.fromJson(data);
  }

  Future<String> sendRegisterCode(String email) async {
    final data = await _post('/auth/verification/send', data: {'email': email, 'type': 'email'});
    return _messageFromData(data, fallback: '验证码已发送');
  }

  Future<String> forgotPassword(String email) async {
    final data = await _post('/auth/forgot-password', data: {'email': email});
    return _messageFromData(data, fallback: '如果邮箱存在，验证码已发送');
  }

  Future<String> resetPassword({
    required String email,
    required String verificationCode,
    required String newPassword,
  }) async {
    final data = await _post(
      '/auth/reset-password',
      data: {'email': email, 'verification_code': verificationCode, 'new_password': newPassword},
    );
    return _messageFromData(data, fallback: '密码已更新');
  }

  Future<AccountUser> getProfile(String token) async {
    final data = await _get('/users/me', token: token);
    return AccountUser.fromJson(_payload(data));
  }

  Future<AccountUser> updateProfile({
    required String token,
    required String displayName,
    required String phone,
    required String bio,
  }) async {
    final data = await _put('/users/me', token: token, data: {'display_name': displayName, 'phone': phone, 'bio': bio});
    return AccountUser.fromJson(_payload(data));
  }

  Future<String> changePassword({
    required String token,
    required String oldPassword,
    required String newPassword,
  }) async {
    final data = await _post(
      '/users/change-password',
      token: token,
      data: {'current_password': oldPassword, 'new_password': newPassword},
    );
    return _messageFromData(data, fallback: '密码已修改');
  }

  Future<AccountDashboard> getDashboard(String token) async {
    final data = await _get('/users/dashboard-info', token: token);
    return AccountDashboard.fromJson(_payload(data));
  }

  Future<List<AccountPackage>> getPackages() async {
    final data = await _get('/packages');
    return _listPayload(data).map(AccountPackage.fromJson).toList();
  }

  Future<List<PaymentMethod>> getPaymentMethods() async {
    final data = await _get('/payment-methods/active');
    return _listPayload(data).map(PaymentMethod.fromJson).toList();
  }

  Future<OrderResult> createOrder({
    required String token,
    required int packageId,
    String? paymentMethod,
    bool useBalance = false,
  }) async {
    final data = await _post(
      '/orders',
      token: token,
      data: {
        'package_id': packageId,
        'use_balance': useBalance,
        if (paymentMethod != null && paymentMethod.isNotEmpty) 'payment_method': paymentMethod,
      },
    );
    return OrderResult.fromJson(_payload(data));
  }

  Future<List<AccountOrder>> getOrders(String token) async {
    final data = await _get('/orders', token: token, queryParameters: const {'page': 1, 'size': 20});
    final payload = _payload(data);
    final orders = payload['orders'];
    if (orders is List) {
      return orders.whereType<Map<String, dynamic>>().map(AccountOrder.fromJson).toList();
    }
    return const [];
  }

  Future<AccountOrderStatus> getOrderStatus({required String token, required String orderNo}) async {
    final data = await _get('/orders/$orderNo/status', token: token);
    return AccountOrderStatus.fromJson(_payload(data));
  }

  Future<OrderResult> createPayment({required String token, required int orderId, required int paymentMethodId}) async {
    final data = await _post(
      '/payment',
      token: token,
      data: {'order_id': orderId, 'payment_method_id': paymentMethodId},
    );
    return OrderResult.fromJson(_payload(data));
  }

  Future<Map<String, dynamic>> _get(String path, {String? token, Map<String, dynamic>? queryParameters}) {
    return _request(
      () => _dio.get<Map<String, dynamic>>(path, queryParameters: queryParameters, options: _options(token)),
    );
  }

  Future<Map<String, dynamic>> _post(String path, {Object? data, String? token}) {
    return _request(() => _dio.post<Map<String, dynamic>>(path, data: data, options: _options(token)));
  }

  Future<Map<String, dynamic>> _put(String path, {Object? data, String? token}) {
    return _request(() => _dio.put<Map<String, dynamic>>(path, data: data, options: _options(token)));
  }

  Options _options(String? token) {
    return Options(headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'});
  }

  Future<Map<String, dynamic>> _request(Future<Response<Map<String, dynamic>>> Function() run) async {
    try {
      final response = await run();
      return response.data ?? const {};
    } on DioException catch (error) {
      final responseData = error.response?.data;
      var message = error.message ?? '请求失败';
      if (responseData is Map<String, dynamic>) {
        final remoteMessage = responseData['message'] ?? responseData['error'];
        if (remoteMessage is String && remoteMessage.isNotEmpty) {
          message = remoteMessage;
        }
      }
      throw AccountApiException(message, statusCode: error.response?.statusCode);
    }
  }

  Map<String, dynamic> _payload(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    return data;
  }

  List<Map<String, dynamic>> _listPayload(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is List) {
      return payload.whereType<Map<String, dynamic>>().toList();
    }
    if (data['packages'] is List) {
      return (data['packages'] as List).whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  String _messageFromData(Map<String, dynamic> data, {required String fallback}) {
    final message = data['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
    return fallback;
  }
}

class AccountAuthResponse {
  AccountAuthResponse({required this.accessToken, this.refreshToken, required this.user});

  final String accessToken;
  final String? refreshToken;
  final AccountUser user;

  factory AccountAuthResponse.fromJson(Map<String, dynamic> json) {
    final payload = json['data'] is Map<String, dynamic> ? json['data'] as Map<String, dynamic> : json;
    return AccountAuthResponse(
      accessToken: payload['access_token']?.toString() ?? '',
      refreshToken: payload['refresh_token']?.toString(),
      user: AccountUser.fromJson((payload['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }
}

class AccountUser {
  const AccountUser({
    this.id = 0,
    this.username = '',
    this.email = '',
    this.displayName = '',
    this.phone = '',
    this.bio = '',
    this.balance = 0,
    this.isAdmin = false,
    this.isVerified = false,
    this.isActive = true,
  });

  final int id;
  final String username;
  final String email;
  final String displayName;
  final String phone;
  final String bio;
  final double balance;
  final bool isAdmin;
  final bool isVerified;
  final bool isActive;

  String get name => displayName.isNotEmpty ? displayName : username;

  factory AccountUser.fromJson(Map<String, dynamic> json) {
    return AccountUser(
      id: _asInt(json['id']),
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? json['displayName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      balance: _asDouble(json['balance']),
      isAdmin: json['is_admin'] == true,
      isVerified: json['is_verified'] == true,
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'display_name': displayName,
      'phone': phone,
      'bio': bio,
      'balance': balance,
      'is_admin': isAdmin,
      'is_verified': isVerified,
      'is_active': isActive,
    };
  }
}

class AccountDashboard {
  const AccountDashboard({
    this.user = const AccountUser(),
    this.subscription,
    this.recentOrders = const [],
    this.totalSpent = 0,
  });

  final AccountUser user;
  final AccountSubscription? subscription;
  final List<AccountOrder> recentOrders;
  final double totalSpent;

  factory AccountDashboard.fromJson(Map<String, dynamic> json) {
    final userJson = (json['user'] as Map?)?.cast<String, dynamic>() ?? json;
    final subscriptionJson = (json['subscription'] as Map?)?.cast<String, dynamic>();
    final rawOrders = json['orders'];
    final statJson = (json['stat'] as Map?)?.cast<String, dynamic>();
    return AccountDashboard(
      user: AccountUser.fromJson(userJson),
      subscription: subscriptionJson == null ? null : AccountSubscription.fromJson(subscriptionJson),
      recentOrders: rawOrders is List
          ? rawOrders.whereType<Map<String, dynamic>>().map(AccountOrder.fromJson).toList()
          : const [],
      totalSpent: _asDouble(
        (json['statistics'] as Map?)?['total_spent'] ?? statJson?['total_spent'] ?? json['total_spent'],
      ),
    );
  }
}

class AccountSubscription {
  const AccountSubscription({
    this.id = 0,
    this.packageName = '',
    this.subscriptionUrl = '',
    this.universalUrl = '',
    this.clashUrl = '',
    this.expireTime = '',
    this.remainingDays = 0,
    this.status = '',
    this.deviceLimit = 0,
    this.currentDevices = 0,
    this.onlineDevices = 0,
    this.isActive = false,
  });

  final int id;
  final String packageName;
  final String subscriptionUrl;
  final String universalUrl;
  final String clashUrl;
  final String expireTime;
  final int remainingDays;
  final String status;
  final int deviceLimit;
  final int currentDevices;
  final int onlineDevices;
  final bool isActive;

  String get importUrl {
    if (universalUrl.contains('/subscriptions/universal/')) {
      return universalUrl;
    }
    if (subscriptionUrl.contains('/subscriptions/universal/')) {
      return subscriptionUrl;
    }
    return '';
  }

  bool get canImport {
    if (!isActive || importUrl.isEmpty) {
      return false;
    }
    if (remainingDays < 0) {
      return false;
    }
    final parsedExpireTime = DateTime.tryParse(expireTime.replaceFirst(' ', 'T'));
    if (parsedExpireTime != null && parsedExpireTime.isBefore(DateTime.now())) {
      return false;
    }
    return true;
  }

  factory AccountSubscription.fromJson(Map<String, dynamic> json) {
    return AccountSubscription(
      id: _asInt(json['id'] ?? json['subscription_id']),
      packageName: json['package_name']?.toString() ?? '',
      subscriptionUrl: json['subscription_url']?.toString() ?? '',
      universalUrl: json['universalUrl']?.toString() ?? json['universal_url']?.toString() ?? '',
      clashUrl: json['clashUrl']?.toString() ?? json['clash_url']?.toString() ?? '',
      expireTime: json['expire_time']?.toString() ?? json['expiryDate']?.toString() ?? '',
      remainingDays: _asInt(json['remaining_days'] ?? json['days_until_expire']),
      status: json['status']?.toString() ?? '',
      deviceLimit: _asInt(json['device_limit'] ?? json['maxDevices']),
      currentDevices: _asInt(json['current_devices'] ?? json['currentDevices']),
      onlineDevices: _asInt(json['online_devices'] ?? json['currentDevices']),
      isActive: json['is_active'] == true || json['status'] == 'active',
    );
  }
}

class AccountPackage {
  const AccountPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationDays,
    required this.deviceLimit,
    required this.isRecommended,
  });

  final int id;
  final String name;
  final String description;
  final double price;
  final int durationDays;
  final int deviceLimit;
  final bool isRecommended;

  factory AccountPackage.fromJson(Map<String, dynamic> json) {
    return AccountPackage(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '套餐',
      description: json['description']?.toString() ?? '',
      price: _asDouble(json['price']),
      durationDays: _asInt(json['duration_days']),
      deviceLimit: _asInt(json['device_limit']),
      isRecommended: json['is_recommended'] == true,
    );
  }
}

class PaymentMethod {
  const PaymentMethod({required this.id, required this.key, required this.name});

  final int id;
  final String key;
  final String name;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: _asInt(json['id']),
      key: json['key']?.toString() ?? json['pay_type']?.toString() ?? '',
      name: json['name']?.toString() ?? '支付方式',
    );
  }
}

class AccountOrder {
  const AccountOrder({
    required this.id,
    required this.orderNo,
    required this.packageName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.paymentUrl,
  });

  final int id;
  final String orderNo;
  final String packageName;
  final double amount;
  final String status;
  final String createdAt;
  final String? paymentUrl;

  factory AccountOrder.fromJson(Map<String, dynamic> json) {
    return AccountOrder(
      id: _asInt(json['id']),
      orderNo: json['order_no']?.toString() ?? '',
      packageName: json['package_name']?.toString() ?? (json['package'] as Map?)?['name']?.toString() ?? '套餐',
      amount: _asDouble(json['final_amount'] ?? json['amount'] ?? json['order_amount']),
      status: json['status']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      paymentUrl: json['payment_url']?.toString(),
    );
  }
}

class AccountOrderStatus {
  const AccountOrderStatus({
    this.orderNo = '',
    this.status = '',
    this.amount = 0,
    this.finalAmount = 0,
    this.type = '',
  });

  final String orderNo;
  final String status;
  final double amount;
  final double finalAmount;
  final String type;

  bool get isPaid => status == 'paid';

  bool get isFinished => switch (status) {
    'paid' || 'cancelled' || 'failed' || 'expired' || 'refunded' => true,
    _ => false,
  };

  factory AccountOrderStatus.fromJson(Map<String, dynamic> json) {
    return AccountOrderStatus(
      orderNo: json['order_no']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      amount: _asDouble(json['amount']),
      finalAmount: _asDouble(json['final_amount'] ?? json['amount']),
      type: json['type']?.toString() ?? '',
    );
  }
}

class OrderResult {
  const OrderResult({
    this.id = 0,
    this.orderNo = '',
    this.status = '',
    this.amount = 0,
    this.paymentUrl,
    this.paymentQrCode,
  });

  final int id;
  final String orderNo;
  final String status;
  final double amount;
  final String? paymentUrl;
  final String? paymentQrCode;

  factory OrderResult.fromJson(Map<String, dynamic> json) {
    return OrderResult(
      id: _asInt(json['id'] ?? json['transaction_id']),
      orderNo: json['order_no']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      amount: _asDouble(json['final_amount'] ?? json['amount']),
      paymentUrl: json['payment_url']?.toString(),
      paymentQrCode: json['payment_qr_code']?.toString(),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

double _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}
