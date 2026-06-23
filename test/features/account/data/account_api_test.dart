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

  test('AccountDevicesResult ignores unsupported response shapes', () {
    final result = AccountDevicesResult.fromJson({
      'data': {'items': []},
    });

    expect(result.total, 0);
    expect(result.devices, isEmpty);
  });
}
