import 'package:dio/dio.dart';

const kBoostApiBaseUrl = 'https://new.moneyfly.top/api/v1';

class AccountApiException implements Exception {
  AccountApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AccountApi {
  AccountApi({Dio? dio, String baseUrl = kBoostApiBaseUrl})
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
  String? _csrfToken;
  Future<String>? _csrfTokenRequest;

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
    final data = await _post('/auth/verification/send', data: {'email': email, 'purpose': 'register'});
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
      data: {'email': email, 'code': verificationCode, 'password': newPassword},
    );
    return _messageFromData(data, fallback: '密码已更新');
  }

  Future<AccountUser> getProfile(String token) async {
    final data = await _get('/users/me', token: token);
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
      data: {'old_password': oldPassword, 'new_password': newPassword},
    );
    return _messageFromData(data, fallback: '密码已修改');
  }

  Future<AccountDashboard> getDashboard(String token) async {
    final results = await Future.wait<Map<String, dynamic>>([
      _get('/users/dashboard-info', token: token),
      _get('/users/me', token: token),
      _get('/subscriptions/user-subscription', token: token).catchError((Object error) {
        if (error is AccountApiException && error.statusCode == 404) {
          return const <String, dynamic>{'data': null};
        }
        throw error;
      }),
    ]);
    return AccountDashboard.fromBackend(user: _payload(results[1]), subscription: _nullablePayload(results[2]));
  }

  Future<List<AccountPackage>> getPackages() async {
    final data = await _get('/packages');
    return _listPayload(data).map(AccountPackage.fromJson).toList();
  }

  Future<List<PaymentMethod>> getPaymentMethods() async {
    final data = await _get('/payment/methods');
    final payload = _payload(data);
    final methods = ((payload['methods'] as List?) ?? const [])
        .whereType<Map>()
        .map((method) => PaymentMethod.fromJson(method.cast<String, dynamic>()))
        .toList();
    if (_asBool(payload['balance_enabled'])) {
      return [PaymentMethod.balance(), ...methods];
    }
    return methods;
  }

  Future<OrderResult> createOrder({required String token, required int packageId}) async {
    final data = await _post('/orders', token: token, data: {'package_id': packageId});
    return OrderResult.fromJson(_payload(data));
  }

  Future<List<AccountOrder>> getOrders(String token) async {
    final data = await _get('/orders', token: token, queryParameters: const {'page': 1, 'page_size': 20});
    final payload = _payload(data);
    final orders = payload['items'];
    if (orders is List) {
      return orders.whereType<Map>().map((order) => AccountOrder.fromJson(order.cast<String, dynamic>())).toList();
    }
    return const [];
  }

  Future<AccountOrderStatus> getOrderStatus({required String token, required String orderNo}) async {
    final data = await _get('/orders/$orderNo/status', token: token);
    return AccountOrderStatus.fromJson(_payload(data));
  }

  Future<OrderResult> createPayment({
    required String token,
    required int orderId,
    required int paymentMethodId,
    bool isMobile = false,
  }) async {
    final data = await _post(
      '/payment',
      token: token,
      data: {'order_id': orderId, 'payment_method_id': paymentMethodId, 'is_mobile': isMobile},
    );
    return OrderResult.fromJson(_payload(data));
  }

  Future<OrderResult> payOrder({required String token, required String orderNo, required String paymentMethod}) async {
    final data = await _post('/orders/$orderNo/pay', token: token, data: {'payment_method': paymentMethod});
    final payload = _payload(data);
    return OrderResult.fromJson({
      ...payload,
      'order_no': payload['order_no'] ?? orderNo,
      'status': payload['status'] ?? 'paid',
    });
  }

  Future<AccountDevicesResult> getDevices(String token) async {
    final data = await _get('/subscriptions/devices', token: token);
    return AccountDevicesResult.fromJson(data);
  }

  Future<String> deleteDevice({required String token, required int id}) async {
    final data = await _delete('/subscriptions/devices/$id', token: token);
    return _messageFromData(data, fallback: '设备已删除');
  }

  Future<String> updateDeviceRemark({required String token, required int id, required String remark}) async {
    final data = await _put('/subscriptions/devices/$id/remark', token: token, data: {'remark': remark.trim()});
    return _messageFromData(data, fallback: '备注已更新');
  }

  Future<Map<String, dynamic>> _get(String path, {String? token, Map<String, dynamic>? queryParameters}) {
    return _request(
      () => _dio.get<Map<String, dynamic>>(path, queryParameters: queryParameters, options: _options(token)),
    );
  }

  Future<Map<String, dynamic>> _post(String path, {Object? data, String? token}) {
    return _request(
      () => _withCsrf(token, (options) => _dio.post<Map<String, dynamic>>(path, data: data, options: options)),
    );
  }

  Future<Map<String, dynamic>> _put(String path, {Object? data, String? token}) {
    return _request(
      () => _withCsrf(token, (options) => _dio.put<Map<String, dynamic>>(path, data: data, options: options)),
    );
  }

  Future<Map<String, dynamic>> _delete(String path, {String? token}) {
    return _request(() => _withCsrf(token, (options) => _dio.delete<Map<String, dynamic>>(path, options: options)));
  }

  Options _options(String? token) {
    return Options(headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'});
  }

  Future<Map<String, dynamic>> _request(Future<Response<Map<String, dynamic>>> Function() run) async {
    try {
      final response = await run();
      return _checkedData(response.data);
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

  Map<String, dynamic> _checkedData(Map<String, dynamic>? data) {
    final checked = data ?? const {};
    final code = checked['code'];
    if (code is num && code != 0) {
      throw AccountApiException(_messageFromData(checked, fallback: '请求失败'), statusCode: code.toInt());
    }
    return checked;
  }

  Future<Response<Map<String, dynamic>>> _withCsrf(
    String? token,
    Future<Response<Map<String, dynamic>>> Function(Options options) run,
  ) async {
    final options = await _mutationOptions(token);
    try {
      final response = await run(options);
      if (token != null && token.isNotEmpty) {
        _csrfToken = null;
      }
      return response;
    } on DioException catch (error) {
      if (error.response?.statusCode != 403 || token == null || token.isEmpty) {
        rethrow;
      }
      _csrfToken = null;
      final retryOptions = await _mutationOptions(token);
      final response = await run(retryOptions);
      _csrfToken = null;
      return response;
    }
  }

  Future<Options> _mutationOptions(String? token) async {
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      final csrfToken = await _getCsrfToken(token);
      if (csrfToken.isNotEmpty) {
        headers['X-CSRF-Token'] = csrfToken;
      }
    }
    return Options(headers: headers);
  }

  Future<String> _getCsrfToken(String token) {
    if (_csrfToken case final csrfToken? when csrfToken.isNotEmpty) {
      return Future.value(csrfToken);
    }
    final existingRequest = _csrfTokenRequest;
    if (existingRequest != null) {
      return existingRequest;
    }
    final request = _dio
        .get<Map<String, dynamic>>('/csrf-token', options: _options(token))
        .then((response) => _payload(_checkedData(response.data))['csrf_token']?.toString() ?? '');
    _csrfTokenRequest = request;
    return request
        .then((csrfToken) {
          _csrfToken = csrfToken;
          return csrfToken;
        })
        .whenComplete(() {
          if (identical(_csrfTokenRequest, request)) {
            _csrfTokenRequest = null;
          }
        });
  }

  Map<String, dynamic> _payload(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    return data;
  }

  Map<String, dynamic>? _nullablePayload(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    return null;
  }

  List<Map<String, dynamic>> _listPayload(Map<String, dynamic> data) {
    final payload = data['data'];
    if (payload is List) {
      return payload.whereType<Map<String, dynamic>>().toList();
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
    this.balance = 0,
    this.isAdmin = false,
    this.isActive = true,
  });

  final int id;
  final String username;
  final String email;
  final String displayName;
  final double balance;
  final bool isAdmin;
  final bool isActive;

  String get name => displayName.isNotEmpty ? displayName : username;

  factory AccountUser.fromJson(Map<String, dynamic> json) {
    return AccountUser(
      id: _asInt(json['id']),
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['nickname']?.toString() ?? '',
      balance: _asDouble(json['balance']),
      isAdmin: json['is_admin'] == true,
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'nickname': displayName,
      'balance': balance,
      'is_admin': isAdmin,
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

  factory AccountDashboard.fromBackend({required Map<String, dynamic> user, Map<String, dynamic>? subscription}) {
    return AccountDashboard(
      user: AccountUser.fromJson(user),
      subscription: subscription == null ? null : AccountSubscription.fromJson(subscription),
      totalSpent: _asDouble(user['total_consumption']),
    );
  }
}

class AccountSubscription {
  const AccountSubscription({
    this.id = 0,
    this.packageName = '',
    this.tokenUrl = '',
    this.clashUrl = '',
    this.hiddifyUrl = '',
    this.singboxUrl = '',
    this.universalUrl = '',
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
  final String tokenUrl;
  final String clashUrl;
  final String hiddifyUrl;
  final String singboxUrl;
  final String universalUrl;
  final String expireTime;
  final int remainingDays;
  final String status;
  final int deviceLimit;
  final int currentDevices;
  final int onlineDevices;
  final bool isActive;

  List<String> get importUrls {
    return _uniqueImportableSubscriptionUrls([
      clashUrl,
      _typedVariant(tokenUrl, 'clash'),
      _typedVariant(universalUrl, 'clash'),
      tokenUrl,
      hiddifyUrl,
      universalUrl,
    ]);
  }

  String get importUrl {
    final urls = importUrls;
    return urls.isEmpty ? '' : urls.first;
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

  bool get hasImportUrl => importUrl.isNotEmpty;

  factory AccountSubscription.fromJson(Map<String, dynamic> json) {
    return AccountSubscription(
      id: _asInt(json['id']),
      packageName: json['package_name']?.toString() ?? '',
      tokenUrl: json['token_url']?.toString() ?? '',
      clashUrl: json['token_clash_url']?.toString() ?? '',
      hiddifyUrl: json['token_hiddify_url']?.toString() ?? '',
      singboxUrl: json['token_singbox_url']?.toString() ?? '',
      universalUrl: json['universal_url']?.toString() ?? '',
      expireTime: json['expire_time']?.toString() ?? '',
      remainingDays: _asInt(json['days_remaining']),
      status: json['status']?.toString() ?? '',
      deviceLimit: _asInt(json['device_limit']),
      currentDevices: _asInt(json['current_devices']),
      onlineDevices: _asInt(json['online_devices']),
      isActive: _asBool(json['is_active']) || json['status'] == 'active',
    );
  }
}

class AccountDevicesResult {
  AccountDevicesResult({this.devices = const [], int? total, int? online, int? mobile, int? desktop})
    : total = total ?? devices.length,
      online = online ?? devices.where((device) => device.isRecentlySeen).length,
      mobile = mobile ?? devices.where((device) => device.isMobile).length,
      desktop = desktop ?? devices.where((device) => device.isDesktop).length;

  final List<AccountDevice> devices;
  final int total;
  final int online;
  final int mobile;
  final int desktop;

  factory AccountDevicesResult.fromJson(Map<String, dynamic> json) {
    final payload = json['data'];
    final rawDevices = payload is List ? payload : const [];
    final devices = rawDevices
        .whereType<Map>()
        .map((device) => AccountDevice.fromJson(device.cast<String, dynamic>()))
        .toList();
    return AccountDevicesResult(devices: devices);
  }
}

class AccountDevice {
  const AccountDevice({
    required this.id,
    this.subscriptionId = 0,
    this.deviceName = '',
    this.deviceType = '',
    this.deviceModel = '',
    this.deviceBrand = '',
    this.ipAddress = '',
    this.location = '',
    this.userAgent = '',
    this.softwareName = '',
    this.softwareVersion = '',
    this.osName = '',
    this.osVersion = '',
    this.subscriptionType = '',
    this.isActive = true,
    this.isAllowed = true,
    this.firstSeen = '',
    this.lastAccess = '',
    this.lastSeen = '',
    this.accessCount = 0,
    this.remark = '',
  });

  final int id;
  final int subscriptionId;
  final String deviceName;
  final String deviceType;
  final String deviceModel;
  final String deviceBrand;
  final String ipAddress;
  final String location;
  final String userAgent;
  final String softwareName;
  final String softwareVersion;
  final String osName;
  final String osVersion;
  final String subscriptionType;
  final bool isActive;
  final bool isAllowed;
  final String firstSeen;
  final String lastAccess;
  final String lastSeen;
  final int accessCount;
  final String remark;

  String get displayName {
    for (final value in [deviceName, deviceModel, softwareName, remark]) {
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return id > 0 ? '设备 #$id' : '未知设备';
  }

  String get softwareLabel {
    return [softwareName, softwareVersion].where((value) => value.isNotEmpty).join(' ');
  }

  String get osLabel {
    return [osName, osVersion].where((value) => value.isNotEmpty).join(' ');
  }

  String get modelLabel {
    if (deviceModel.isEmpty) {
      return deviceBrand;
    }
    if (deviceBrand.isEmpty || deviceBrand == 'Apple') {
      return deviceModel;
    }
    return '$deviceModel ($deviceBrand)';
  }

  String get accessLabel => lastSeen.isNotEmpty ? lastSeen : lastAccess;

  bool get isMobile => deviceType == 'mobile' || deviceType == 'tablet';

  bool get isDesktop => deviceType == 'desktop' || deviceType == 'server';

  bool get isRecentlySeen {
    final raw = accessLabel;
    if (raw.isEmpty) {
      return false;
    }
    final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed == null) {
      return false;
    }
    return DateTime.now().difference(parsed).inHours < 24;
  }

  factory AccountDevice.fromJson(Map<String, dynamic> json) {
    return AccountDevice(
      id: _asInt(json['id']),
      subscriptionId: _asInt(json['subscription_id']),
      deviceName: json['device_name']?.toString() ?? '',
      deviceType: json['device_type']?.toString() ?? '',
      deviceModel: json['device_model']?.toString() ?? '',
      deviceBrand: json['device_brand']?.toString() ?? '',
      ipAddress: json['ip_address']?.toString() ?? '',
      location: json['region']?.toString() ?? '',
      userAgent: json['user_agent']?.toString() ?? '',
      softwareName: json['software_name']?.toString() ?? '',
      softwareVersion: json['software_version']?.toString() ?? '',
      osName: json['os_name']?.toString() ?? '',
      osVersion: json['os_version']?.toString() ?? '',
      subscriptionType: json['subscription_type']?.toString() ?? '',
      isActive: _asBool(json['is_active'], fallback: true),
      isAllowed: _asBool(json['is_allowed'], fallback: true),
      firstSeen: json['first_seen']?.toString() ?? '',
      lastAccess: json['last_access']?.toString() ?? '',
      lastSeen: json['last_seen']?.toString() ?? '',
      accessCount: _asInt(json['access_count']),
      remark: json['remark']?.toString() ?? '',
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
      isRecommended: json['is_featured'] == true,
    );
  }
}

class PaymentMethod {
  const PaymentMethod({required this.id, required this.key, required this.name});

  factory PaymentMethod.balance() {
    return const PaymentMethod(id: 0, key: 'balance', name: '余额支付');
  }

  final int id;
  final String key;
  final String name;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: _asInt(json['id']),
      key: json['pay_type']?.toString() ?? '',
      name: json['name']?.toString() ?? _paymentName(json['pay_type']?.toString() ?? ''),
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
      packageName: json['package_name']?.toString() ?? '套餐',
      amount: _asDouble(json['final_amount'] ?? json['amount']),
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

  bool get isPaid => status == 'paid' || status == 'completed';

  bool get isFinished => switch (status) {
    'paid' || 'completed' || 'cancelled' || 'failed' || 'expired' || 'refunded' => true,
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
      id: _asInt(json['id']),
      orderNo: json['order_no']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      amount: _asDouble(json['final_amount'] ?? json['amount']),
      paymentUrl: json['payment_url']?.toString(),
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

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return fallback;
}

bool _isImportableSubscriptionUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.isScheme('https') || uri.isScheme('http')) &&
      uri.host.isNotEmpty &&
      (uri.queryParameters['token']?.isNotEmpty ?? false);
}

List<String> _uniqueImportableSubscriptionUrls(Iterable<String> urls) {
  final seen = <String>{};
  final result = <String>[];
  for (final rawUrl in urls) {
    final url = rawUrl.trim();
    if (!_isImportableSubscriptionUrl(url)) {
      continue;
    }
    final uri = Uri.parse(url);
    final normalizedQuery = Map<String, String>.of(uri.queryParameters);
    final normalized = uri
        .replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase(), queryParameters: normalizedQuery)
        .toString();
    if (seen.add(normalized)) {
      result.add(url);
    }
  }
  return result;
}

String _typedVariant(String url, String type) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.host.isEmpty ||
      !(uri.isScheme('https') || uri.isScheme('http')) ||
      !(uri.queryParameters['token']?.isNotEmpty ?? false)) {
    return url;
  }
  final queryParameters = Map<String, String>.of(uri.queryParameters);
  queryParameters['type'] = type;
  return uri.replace(queryParameters: queryParameters).toString();
}

String _paymentName(String payType) {
  return switch (payType) {
    'balance' => '余额支付',
    'alipay' => '支付宝',
    'epay' => '易支付',
    'wxpay' => '微信支付',
    'qqpay' => 'QQ 支付',
    'stripe' => 'Stripe',
    'crypto' => 'USDT',
    'codepay' => '码支付',
    'codepay_alipay' => '码支付支付宝',
    'codepay_wxpay' => '码支付微信',
    _ => payType.isEmpty ? '支付方式' : payType,
  };
}
