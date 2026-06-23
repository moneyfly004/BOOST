import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:uuid/uuid.dart';

void main() {
  const validBaseUrl = "https://example.com/configurations/user1/filename.yaml";
  const validExtendedUrl = "https://example.com/configurations/user1/filename.yaml?test#b";
  const validSupportUrl = "https://example.com/support";

  group("parse", () {
    test("Should preserve indentation when preparing non-URL YAML lines for expansion", () {
      final lines = [
        'proxies:',
        '  - name: 香港-fxus4x9o',
        '    type: vmess',
        'proxy-groups:',
        '  - name: Auto',
        '    proxies:',
        '      - 香港-fxus4x9o',
        '  https://example.com/nested-url-is-yaml-value',
        'https://example.com/remote-profile',
      ];

      expect(ProfileParser.initialExpandedLinesForTesting(lines), [
        'proxies:',
        '  - name: 香港-fxus4x9o',
        '    type: vmess',
        'proxy-groups:',
        '  - name: Auto',
        '    proxies:',
        '      - 香港-fxus4x9o',
        '  https://example.com/nested-url-is-yaml-value',
        null,
      ]);
    });

    test("Should sanitize unsupported VLESS flow values in Clash inline YAML", () {
      const content = '''
proxies:
  - {name: bad-flow, type: vless, server: example.com, port: 443, uuid: id, flow: TSAR, tls: true}
  - {name: udp443-flow, type: vless, server: example.com, port: 443, uuid: id, flow: xtls-rprx-vision-udp443, tls: true}
  - {name: supported-flow, type: vless, server: example.com, port: 443, uuid: id, flow: xtls-rprx-vision, tls: true}
  - {name: non-vless, type: vmess, server: example.com, port: 443, flow: TSAR, tls: true}
''';

      final sanitized = ProfileParser.sanitizeUnsupportedSubscriptionOptionsForTesting(content);

      expect(sanitized, contains('{name: bad-flow, type: vless, server: example.com, port: 443, uuid: id, tls: true}'));
      expect(
        sanitized,
        contains(
          '{name: udp443-flow, type: vless, server: example.com, port: 443, uuid: id, flow: xtls-rprx-vision, tls: true}',
        ),
      );
      expect(sanitized, contains('flow: xtls-rprx-vision, tls: true}'));
      expect(sanitized, contains('{name: non-vless, type: vmess, server: example.com, port: 443, flow: TSAR'));
      expect(sanitized, isNot(contains('type: vless, server: example.com, port: 443, uuid: id, flow: TSAR')));
      expect(sanitized, isNot(contains('xtls-rprx-vision-udp443')));
    });

    test("Should sanitize unsupported VLESS flow values in Clash block YAML", () {
      const content = '''
proxies:
  - name: bad-flow
    type: vless
    server: example.com
    flow: TSAR
    tls: true
  - name: supported-flow
    type: vless
    server: example.com
    flow: xtls-rprx-vision
    tls: true
  - name: non-vless
    type: vmess
    server: example.com
    flow: TSAR
''';

      final sanitized = ProfileParser.sanitizeUnsupportedSubscriptionOptionsForTesting(content);

      expect(sanitized, contains('  - name: bad-flow\n    type: vless\n    server: example.com\n    tls: true'));
      expect(sanitized, contains('    flow: xtls-rprx-vision\n    tls: true'));
      expect(sanitized, contains('  - name: non-vless\n    type: vmess\n    server: example.com\n    flow: TSAR'));
      expect(sanitized, isNot(contains('bad-flow\n    type: vless\n    server: example.com\n    flow: TSAR')));
    });

    test("Should sanitize unsupported VLESS flow values in URI subscriptions", () {
      const content = '''
vless://00000000-0000-0000-0000-000000000000@example.com:443?security=reality&flow=TSAR&fp=chrome#bad
vless://00000000-0000-0000-0000-000000000000@example.com:443?security=reality&flow=xtls-rprx-vision-udp443&fp=chrome#udp443
vless://00000000-0000-0000-0000-000000000000@example.com:443?security=reality&flow=xtls-rprx-vision&fp=chrome#ok
''';

      final sanitized = ProfileParser.sanitizeUnsupportedSubscriptionOptionsForTesting(content);

      expect(sanitized, contains('security=reality&fp=chrome#bad'));
      expect(sanitized, contains('flow=xtls-rprx-vision&fp=chrome#udp443'));
      expect(sanitized, contains('flow=xtls-rprx-vision&fp=chrome#ok'));
      expect(sanitized, isNot(contains('flow=TSAR')));
      expect(sanitized, isNot(contains('xtls-rprx-vision-udp443')));
    });

    test("Should decode base64 URI subscriptions before sanitizing unsupported VLESS flow values", () {
      const decoded =
          'vless://00000000-0000-0000-0000-000000000000@example.com:443?security=reality&flow=TSAR&fp=chrome#bad';
      final encoded = base64.encode(utf8.encode(decoded));

      final sanitized = ProfileParser.sanitizeUnsupportedSubscriptionOptionsForTesting(encoded);

      expect(sanitized, contains('vless://'));
      expect(sanitized, contains('security=reality&fp=chrome#bad'));
      expect(sanitized, isNot(contains('flow=TSAR')));
      expect(sanitized, isNot(equals(encoded)));
    });

    test("Should use filename in url with no headers and fragment", () {
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validBaseUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("filename"));
            expect(rp.url, equals(validBaseUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use fragment in url with no headers", () {
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validExtendedUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("b"));
            expect(rp.url, equals(validExtendedUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use base64 title in headers", () {
      final headers = <String, List<String>>{
        "profile-title": ["base64:ZXhhbXBsZVRpdGxl"],
        "profile-update-interval": ["1"],
        "connection-test-url": [validBaseUrl],
        "remote-dns-address": [validBaseUrl],
        "subscription-userinfo": ["upload=0;download=1024;total=10240.5;expire=1704054600.55"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          tempFilePath: '',
          profile: ProfileEntity.remote(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validExtendedUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.name, equals("exampleTitle"));
              expect(rp.url, equals(validExtendedUrl));
              expect(rp.options, equals(const ProfileOptions(updateInterval: Duration(hours: 1))));
              expect(
                rp.subInfo,
                equals(
                  SubscriptionInfo(
                    upload: 0,
                    download: 1024,
                    total: 10240,
                    expire: DateTime.fromMillisecondsSinceEpoch(1704054600 * 1000),
                    webPageUrl: validBaseUrl,
                    supportUrl: validSupportUrl,
                  ),
                ),
              );
            },
            local: (lp) {},
          );
        });
      });
    });

    test("Should use infinite when given 0 for subscription properties", () {
      final headers = <String, List<String>>{
        "profile-title": ["title"],
        "profile-update-interval": ["1"],
        "subscription-userinfo": ["upload=0;download=1024;total=0;expire=0"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          tempFilePath: '',
          profile: RemoteProfileEntity(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validBaseUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.subInfo, isNotNull);
              expect(rp.subInfo!.total, equals(ProfileParser.infiniteTrafficThreshold + 1));
              expect(
                rp.subInfo!.expire,
                equals(DateTime.fromMillisecondsSinceEpoch(ProfileParser.infiniteTimeThreshold * 1000)),
              );
            },
            local: (lp) {},
          );
        });
      });
    });
  });
}
