import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account/data/account_api.dart';

void main() {
  test('AccountDevicesResult parses subscription device list response', () {
    final result = AccountDevicesResult.fromJson({
      'data': {
        'devices': [
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
            'last_access': '2026-06-18 12:00:00',
            'is_active': true,
            'is_allowed': true,
            'access_count': 3,
            'remark': 'work laptop',
          },
          {'id': 13, 'device_name': 'Pixel', 'device_type': 'mobile', 'is_active': 1, 'is_allowed': 'true'},
        ],
        'total': 8,
        'total_online': 2,
        'total_mobile': 5,
        'total_desktop': 3,
      },
    });

    expect(result.total, 8);
    expect(result.online, 2);
    expect(result.mobile, 5);
    expect(result.desktop, 3);
    expect(result.devices, hasLength(2));
    expect(result.devices.first.id, 12);
    expect(result.devices.first.displayName, 'MacBook Pro');
    expect(result.devices.first.softwareLabel, 'Hiddify 3.0.0');
    expect(result.devices.first.osLabel, 'macOS 15.0');
    expect(result.devices.first.modelLabel, 'MacBookPro18,3');
    expect(result.devices.last.isMobile, isTrue);
  });

  test('AccountDevicesResult accepts legacy raw list response', () {
    final result = AccountDevicesResult.fromJson({
      'data': [
        {'id': 1, 'device_type': 'desktop'},
        {'id': 2, 'device_type': 'tablet'},
      ],
    });

    expect(result.total, 2);
    expect(result.mobile, 1);
    expect(result.desktop, 1);
  });
}
