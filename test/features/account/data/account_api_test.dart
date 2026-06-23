import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account/data/account_api.dart';

void main() {
  test('AccountSubscription parses backend Clash URL and orders import fallbacks', () {
    final subscription = AccountSubscription.fromJson({
      'id': 7,
      'package_name': 'VIP',
      'token_url': 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token',
      'token_clash_url': 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash',
      'token_singbox_url': 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox',
      'status': 'active',
      'days_remaining': 30,
      'is_active': true,
    });

    expect(subscription.importUrls, [
      'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash',
      'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token',
    ]);
    expect(subscription.importUrl, 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash');
    expect(subscription.canImport, isTrue);
  });

  test('AccountSubscription does not import sing-box subscriptions', () {
    final subscription = AccountSubscription.fromJson({
      'id': 7,
      'token_singbox_url': 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox',
      'status': 'active',
      'days_remaining': 30,
      'is_active': true,
    });

    expect(subscription.importUrls, isEmpty);
    expect(subscription.canImport, isFalse);
  });

  test('AccountSubscription parses numeric active flag from backend', () {
    final subscription = AccountSubscription.fromJson({
      'id': 7,
      'token_url': 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token',
      'status': 'enabled',
      'days_remaining': 30,
      'is_active': 1,
    });

    expect(subscription.isActive, isTrue);
    expect(subscription.canImport, isTrue);
    expect(subscription.importUrl, 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash');
  });

  test('AccountDevicesResult parses subscription device list response', () {
    final result = AccountDevicesResult.fromJson({
      'data': [
        {
          'id': 12,
          'subscription_id': 7,
          'device_name': 'MacBook Pro',
          'device_type': 'desktop',
          'software_name': 'Hiddify',
          'software_version': '3.0.0',
          'os_name': 'macOS',
          'os_version': '15.0',
          'device_model': 'MacBookPro18,3',
          'device_brand': 'Apple',
          'ip_address': '203.0.113.10',
          'last_access': DateTime.now().toIso8601String(),
          'is_active': true,
          'is_allowed': true,
          'access_count': 3,
          'remark': 'work laptop',
        },
        {'id': 13, 'device_name': 'Pixel', 'device_type': 'mobile', 'is_active': 1, 'is_allowed': 'true'},
      ],
    });

    expect(result.total, 2);
    expect(result.online, 1);
    expect(result.mobile, 1);
    expect(result.desktop, 1);
    expect(result.devices, hasLength(2));
    expect(result.devices.first.id, 12);
    expect(result.devices.first.displayName, 'MacBook Pro');
    expect(result.devices.first.softwareLabel, 'Hiddify 3.0.0');
    expect(result.devices.first.osLabel, 'macOS 15.0');
    expect(result.devices.first.modelLabel, 'MacBookPro18,3');
    expect(result.devices.last.isMobile, isTrue);
  });

  test('AccountSubscription parses v2 backend subscription urls', () {
    final subscription = AccountSubscription.fromJson({
      'id': 7,
      'package_name': 'VIP',
      'clash_url': 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash',
      'universal_url': 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token',
      'singbox_url': 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=singbox',
      'status': 'active',
      'days_remaining': 30,
      'is_active': true,
      'current_devices': 1,
      'device_limit': 3,
    });

    expect(subscription.importUrl, 'https://new.moneyfly.top/api/v1/client/subscribe?token=account-token&type=clash');
    expect(subscription.currentDevices, 1);
    expect(subscription.canImport, isTrue);
  });

  test('AccountDevicesResult parses paginated v2 device response', () {
    final result = AccountDevicesResult.fromJson({
      'data': {
        'items': [
          {
            'id': 12,
            'device_name': 'BOOST macOS',
            'device_type': 'desktop',
            'software_name': 'Hiddify',
            'os_name': 'macOS',
            'last_access': DateTime.now().toIso8601String(),
          },
        ],
        'total': 3,
        'online_devices': 1,
      },
    });

    expect(result.total, 3);
    expect(result.online, 1);
    expect(result.devices.single.displayName, 'BOOST macOS');
  });

  test('AccountPackage and AccountOrder parse v2 backend fields', () {
    final package = AccountPackage.fromJson({
      'id': 2,
      'name': 'Pro',
      'description': '30 days',
      'price': 9.9,
      'duration_days': 30,
      'device_limit': 5,
      'is_featured': true,
    });
    final order = AccountOrder.fromJson({
      'id': 8,
      'order_no': 'ORD123',
      'package_name': 'Pro',
      'final_amount': 8.8,
      'status': 'pending',
      'created_at': '2026-06-23T10:00:00Z',
    });
    final method = PaymentMethod.fromJson({'id': 4, 'pay_type': 'alipay'});
    final payment = OrderResult.fromJson({
      'order_no': 'ORD123',
      'transaction_id': 'PAY123',
      'amount': 8.8,
      'pay_type': 'alipay',
      'payment_url': 'https://pay.example/checkout',
    });

    expect(package.name, 'Pro');
    expect(package.deviceLimit, 5);
    expect(package.isRecommended, isTrue);
    expect(order.orderNo, 'ORD123');
    expect(order.packageName, 'Pro');
    expect(method.name, '支付宝');
    expect(payment.orderNo, 'ORD123');
    expect(payment.paymentUrl, 'https://pay.example/checkout');
  });
}
