import 'dart:convert';
import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

/// parse profile subscription url and headers for data
///
/// ***name parser hierarchy:***
/// - UserOverride.name
/// - `profile-title` header
/// - `content-disposition` header
/// - url fragment (example: `https://example.com/config#user`) -> name=`user`
/// - url filename extension (example: `https://example.com/config.json`) -> name=`config`
/// - if none of these methods return a non-blank string, switch(profileType)
/// - remote:  fallback to `Remote Profile`
/// - local: fallback to protocol, extracted from content by protocol()

class ProfileParser {
  static const infiniteTrafficThreshold = 920_233_720_368;
  static const infiniteTimeThreshold = 92_233_720_368;
  static const _supportedVlessFlow = 'xtls-rprx-vision';
  static const allowedOverrideConfigs = [
    'connection-test-url',
    'direct-dns-address',
    'remote-dns-address',
    'tls-tricks',
    'chain-status',
    'extra-security',
  ];
  static const allowedProfileHeaders = [
    'profile-title',
    'content-disposition',
    'subscription-userinfo',
    'profile-update-interval',
    'support-url',
    'profile-web-page-url',
    'enable-warp',
    'enable-fragment',
  ];

  final Ref _ref;
  final DioHttpClient _httpClient;

  ProfileParser({required Ref ref, required DioHttpClient httpClient}) : _ref = ref, _httpClient = httpClient;
  TaskEither<ProfileFailure, ProfileEntriesCompanion> addLocal({
    required String id,
    required String content,
    required String tempFilePath,
    required UserOverride? userOverride,
  }) {
    return TaskEither.tryCatch(() async {
          await expandRemoteLinesInParallel(
            tempFilePath: tempFilePath,
            httpClient: _httpClient,
            cancelToken: CancelToken(),
            ref: _ref,
          );
          await _sanitizeUnsupportedSubscriptionOptionsInFile(tempFilePath);
        }, (_, _) => const ProfileFailure.unexpected())
        .flatMap((_) => TaskEither.fromEither(populateHeaders(content: File(tempFilePath).readAsStringSync())))
        .flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: ProfileEntity.local(
                id: id,
                active: true,
                name: '',
                lastUpdate: DateTime.now(),
                userOverride: userOverride,
                populatedHeaders: populatedHeaders,
              ),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected)),
          ),
        );
  }

  TaskEither<ProfileFailure, ProfileEntriesCompanion> addRemote({
    required String id,
    required String url,
    required String tempFilePath,
    required UserOverride? userOverride,
    CancelToken? cancelToken,
  }) => _downloadProfile(url, tempFilePath, cancelToken).flatMap(
    (remoteHeaders) =>
        TaskEither.fromEither(
          populateHeaders(content: File(tempFilePath).readAsStringSync(), remoteHeaders: remoteHeaders),
        ).flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: ProfileEntity.remote(
                id: id,
                active: true,
                name: '',
                url: url,
                lastUpdate: DateTime.now(),
                userOverride: userOverride,
                populatedHeaders: populatedHeaders,
              ),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected)),
          ),
        ),
  );

  TaskEither<ProfileFailure, ProfileEntriesCompanion> updateRemote({
    required RemoteProfileEntity rp,
    required String tempFilePath,
    CancelToken? cancelToken,
  }) => _downloadProfile(rp.url, tempFilePath, cancelToken).flatMap(
    (remoteHeaders) =>
        TaskEither.fromEither(
          populateHeaders(content: File(tempFilePath).readAsStringSync(), remoteHeaders: remoteHeaders),
        ).flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: rp.copyWith(populatedHeaders: populatedHeaders),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected)),
          ),
        ),
  );

  Either<ProfileFailure, ProfileEntriesCompanion> offlineUpdate({
    required ProfileEntity profile,
    required String tempFilePath,
  }) =>
      Either.tryCatch(() {
            _sanitizeUnsupportedSubscriptionOptionsInFileSync(tempFilePath);
            return profile.map(
              remote: (rp) => parse(profile: rp, tempFilePath: tempFilePath),
              local: (lp) => parse(tempFilePath: tempFilePath, profile: lp),
            );
          }, ProfileFailure.unexpected)
          .flatMap((profile) => profile)
          .flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected));

  TaskEither<ProfileFailure, Map<String, dynamic>> _downloadProfile(
    String url,
    String tempFilePath,
    CancelToken? cancelToken,
  ) => TaskEither.tryCatch(() async {
    // if (url.startsWith("http://"))
    //   throw const ProfileFailure.invalidUrl('HTTP is not supported. Please use HTTPS for secure connection.');

    final rs = await _httpClient
        .download(
          url.trim(),
          tempFilePath,
          cancelToken: cancelToken,
          userAgent: _ref.read(ConfigOptions.useXrayCoreWhenPossible)
              ? _httpClient.userAgent.replaceAll("HiddifyNext", "HiddifyNextX")
              : null,
        )
        .catchError((err) {
          if (CancelToken.isCancel(err as DioException)) {
            throw const ProfileFailure.cancelByUser('HTTP request for getting profile content canceled by user.');
          }
          throw err;
        });
    await expandRemoteLinesInParallel(
      tempFilePath: tempFilePath,
      httpClient: _httpClient,
      cancelToken: cancelToken ?? CancelToken(),
      ref: _ref,
    );
    await _sanitizeUnsupportedSubscriptionOptionsInFile(tempFilePath);
    // fixing headers before return
    return rs.headers.map.map((key, value) {
      if (value.length == 1) return MapEntry(key, value.first);
      return MapEntry(key, value);
    });
  }, (err, st) => err is ProfileFailure ? err : ProfileFailure.unexpected(err, st));
  @visibleForTesting
  Future<void> expandRemoteLinesInParallel({
    required String tempFilePath,
    required DioHttpClient httpClient,
    required CancelToken cancelToken,
    required Ref ref,
    int parallelism = 4,
  }) async {
    final content = await File(tempFilePath).readAsString();
    final lines = content.split('\n');
    final results = _initialExpandedLines(lines);

    int index = 0;

    Future<void> worker() async {
      while (true) {
        if (cancelToken.isCancelled) return;

        final currentIndex = index++;
        if (currentIndex >= lines.length) return;

        final line = lines[currentIndex];

        final lineToExpand = _lineToExpand(line);
        if (lineToExpand == null) {
          continue;
        }

        try {
          final tmpPath = '$tempFilePath.$currentIndex';

          await httpClient.download(
            lineToExpand,
            tmpPath,
            cancelToken: cancelToken,
            userAgent: ref.read(ConfigOptions.useXrayCoreWhenPossible)
                ? httpClient.userAgent.replaceAll('HiddifyNext', 'HiddifyNextX')
                : null,
          );

          results[currentIndex] = (await File(tmpPath).readAsString()).trim();
        } catch (err) {
          if (err is DioException && CancelToken.isCancel(err)) {
            return;
          }
          results[currentIndex] = '';
        }
      }
    }

    // Start workers
    await Future.wait(List.generate(parallelism, (_) => worker()));

    if (results.any((e) => e != null)) {
      final newContent = results.join("\n");
      await File(tempFilePath).writeAsString(newContent);
    }
  }

  @visibleForTesting
  static List<String?> initialExpandedLinesForTesting(List<String> lines) => _initialExpandedLines(lines);

  static List<String?> _initialExpandedLines(List<String> lines) {
    return [for (final line in lines) _lineToExpand(line) == null ? line : null];
  }

  static String? _lineToExpand(String line) {
    if (line.startsWith('http://') || line.startsWith('https://')) {
      return line.trim();
    }
    return null;
  }

  @visibleForTesting
  static String sanitizeUnsupportedSubscriptionOptionsForTesting(String content) {
    return _sanitizeUnsupportedSubscriptionOptions(content);
  }

  static Future<void> _sanitizeUnsupportedSubscriptionOptionsInFile(String tempFilePath) async {
    final file = File(tempFilePath);
    final content = await file.readAsString();
    final sanitized = _sanitizeUnsupportedSubscriptionOptions(content);
    if (sanitized != content) {
      await file.writeAsString(sanitized);
    }
  }

  static void _sanitizeUnsupportedSubscriptionOptionsInFileSync(String tempFilePath) {
    final file = File(tempFilePath);
    final content = file.readAsStringSync();
    final sanitized = _sanitizeUnsupportedSubscriptionOptions(content);
    if (sanitized != content) {
      file.writeAsStringSync(sanitized);
    }
  }

  static String _sanitizeUnsupportedSubscriptionOptions(String content) {
    final decoded = _tryDecodeBase64Subscription(content);
    if (decoded != null) {
      final sanitizedDecoded = _sanitizeDecodedSubscriptionOptions(decoded);
      if (sanitizedDecoded != decoded) {
        return sanitizedDecoded;
      }
    }
    return _sanitizeDecodedSubscriptionOptions(content);
  }

  static String? _tryDecodeBase64Subscription(String content) {
    final compact = content.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8 || !RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(compact)) {
      return null;
    }
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(compact)));
      if (_looksLikeProxySubscription(decoded)) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool _looksLikeProxySubscription(String content) {
    return content.contains('vless://') ||
        content.contains('vmess://') ||
        content.contains('trojan://') ||
        content.contains('proxies:');
  }

  static String _sanitizeDecodedSubscriptionOptions(String content) {
    final lines = content.split('\n');
    final sanitizedLines = List<String?>.from(lines);
    var currentBlockIsVless = false;
    final pendingBlockFlowIndexes = <int>[];

    for (var index = 0; index < lines.length; index++) {
      var line = sanitizedLines[index] ?? lines[index];

      final inlineSanitized = _sanitizeInlineVlessYamlFlow(line);
      if (inlineSanitized != line) {
        sanitizedLines[index] = inlineSanitized;
        line = inlineSanitized;
      }

      final uriSanitized = _sanitizeVlessUriLine(line);
      if (uriSanitized != line) {
        sanitizedLines[index] = uriSanitized;
        line = uriSanitized;
      }

      if (_isYamlInlineMapLine(line)) {
        currentBlockIsVless = false;
        pendingBlockFlowIndexes.clear();
        continue;
      }

      if (_isYamlListItemLine(line)) {
        currentBlockIsVless = _containsYamlKeyValue(line, 'type', 'vless');
        pendingBlockFlowIndexes.clear();
      } else if (_isYamlTypeVlessLine(line)) {
        currentBlockIsVless = true;
        for (final pendingIndex in pendingBlockFlowIndexes) {
          sanitizedLines[pendingIndex] = _sanitizeBlockVlessFlowLine(lines[pendingIndex]);
        }
        pendingBlockFlowIndexes.clear();
      }

      if (_isYamlFlowLine(line)) {
        if (currentBlockIsVless) {
          sanitizedLines[index] = _sanitizeBlockVlessFlowLine(line);
        } else {
          pendingBlockFlowIndexes.add(index);
        }
      }
    }

    return sanitizedLines.whereType<String>().join('\n');
  }

  static String _sanitizeVlessUriLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('vless://')) {
      return line;
    }
    final uri = Uri.tryParse(trimmed);
    final flow = uri?.queryParameters['flow'];
    if (uri == null || flow == null || flow.isEmpty) {
      return line;
    }
    final normalizedFlow = _normalizeVlessFlow(flow);
    if (normalizedFlow == flow) {
      return line;
    }

    final queryParameters = <String, dynamic>{};
    for (final entry in uri.queryParametersAll.entries) {
      if (entry.key == 'flow') {
        if (normalizedFlow != null) {
          queryParameters[entry.key] = normalizedFlow;
        }
        continue;
      }
      queryParameters[entry.key] = entry.value.length == 1 ? entry.value.first : entry.value;
    }

    final sanitizedUri = uri.replace(queryParameters: queryParameters.isEmpty ? null : queryParameters).toString();
    return line.replaceFirst(trimmed, sanitizedUri);
  }

  static String _sanitizeInlineVlessYamlFlow(String line) {
    if (!_isYamlInlineMapLine(line) || !_containsYamlKeyValue(line, 'type', 'vless')) {
      return line;
    }
    var sanitized = line;
    final flowMatches = RegExp(r'flow:\s*([^,}\n]+)').allMatches(line).toList().reversed;
    for (final match in flowMatches) {
      final rawValue = match.group(1)!;
      final normalizedFlow = _normalizeVlessFlow(rawValue);
      if (normalizedFlow == _unquoteYamlScalar(rawValue)) {
        continue;
      }
      if (normalizedFlow != null) {
        sanitized = sanitized.replaceRange(match.start + 'flow:'.length, match.end, ' $normalizedFlow');
      } else {
        sanitized = _removeInlineYamlField(sanitized, match.start, match.end);
      }
    }
    return sanitized;
  }

  static String? _sanitizeBlockVlessFlowLine(String line) {
    final match = RegExp(r'''^(\s*)flow:\s*([^#\s]+|'[^']*'|"[^"]*")(\s*(?:#.*)?)$''').firstMatch(line);
    if (match == null) {
      return line;
    }
    final rawValue = match.group(2)!;
    final normalizedFlow = _normalizeVlessFlow(rawValue);
    if (normalizedFlow == _unquoteYamlScalar(rawValue)) {
      return line;
    }
    if (normalizedFlow == null) {
      return null;
    }
    return '${match.group(1)}flow: $normalizedFlow${match.group(3)}';
  }

  static String _removeInlineYamlField(String line, int start, int end) {
    var removeStart = start;
    while (removeStart > 0 && _isHorizontalWhitespace(line.codeUnitAt(removeStart - 1))) {
      removeStart--;
    }
    if (removeStart > 0 && line[removeStart - 1] == ',') {
      removeStart--;
      var removeEnd = end;
      while (removeEnd < line.length && _isHorizontalWhitespace(line.codeUnitAt(removeEnd))) {
        removeEnd++;
      }
      return line.replaceRange(removeStart, removeEnd, '');
    }

    var removeEnd = end;
    while (removeEnd < line.length && _isHorizontalWhitespace(line.codeUnitAt(removeEnd))) {
      removeEnd++;
    }
    if (removeEnd < line.length && line[removeEnd] == ',') {
      removeEnd++;
      while (removeEnd < line.length && _isHorizontalWhitespace(line.codeUnitAt(removeEnd))) {
        removeEnd++;
      }
    }
    return line.replaceRange(removeStart, removeEnd, '');
  }

  static bool _isHorizontalWhitespace(int codeUnit) {
    return codeUnit == 0x20 || codeUnit == 0x09;
  }

  static bool _isYamlInlineMapLine(String line) {
    return line.contains('{') && line.contains('}');
  }

  static bool _isYamlListItemLine(String line) {
    return RegExp(r'^\s*-\s+').hasMatch(line);
  }

  static bool _isYamlTypeVlessLine(String line) {
    return _containsYamlKeyValue(line, 'type', 'vless');
  }

  static bool _isYamlFlowLine(String line) {
    return RegExp(r'^\s*flow:\s*').hasMatch(line);
  }

  static bool _containsYamlKeyValue(String line, String key, String value) {
    final pattern = RegExp(
      '(^|[,{\\s-])$key:\\s*[\\\'"]?${RegExp.escape(value)}[\\\'"]?(?=\\s*(,|}|#|\$))',
      caseSensitive: false,
    );
    return pattern.hasMatch(line);
  }

  static String? _normalizeVlessFlow(String rawValue) {
    final flow = _unquoteYamlScalar(rawValue);
    if (flow.isEmpty || flow == _supportedVlessFlow) {
      return flow;
    }
    if (flow == 'xtls-rprx-vision-udp443') {
      return _supportedVlessFlow;
    }
    return null;
  }

  static String _unquoteYamlScalar(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        ((trimmed.startsWith("'") && trimmed.endsWith("'")) || (trimmed.startsWith('"') && trimmed.endsWith('"')))) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  static Either<ProfileFailure, Map<String, dynamic>> populateHeaders({
    required String content,
    Map<String, dynamic>? remoteHeaders,
  }) => Either.tryCatch(() {
    final contentHeaders = _parseHeadersFromContent(content);
    return _mergeAndValidateHeaders(contentHeaders, remoteHeaders ?? {});
  }, ProfileFailure.unexpected);

  static Map<String, dynamic> _mergeAndValidateHeaders(
    Map<String, dynamic> contentHeaders,
    Map<String, dynamic> remoteHeaders,
  ) {
    for (final entry in contentHeaders.entries) {
      if (!remoteHeaders.keys.contains(entry.key)) {
        remoteHeaders[entry.key] = entry.value;
      }
    }
    final headers = <String, dynamic>{};
    for (final entry in remoteHeaders.entries) {
      if (allowedProfileHeaders.contains(entry.key) && entry.value != null && entry.value.toString().isNotEmpty) {
        headers[entry.key] = entry.value;
      }
    }
    return headers;
  }

  static Map<String, dynamic> _parseHeadersFromContent(String content) {
    final headers = <String, dynamic>{};
    final content_ = safeDecodeBase64(content);
    final lines = content_.split("\n");
    final linesToProcess = lines.length < 10 ? lines.length : 10;
    for (int i = 0; i < linesToProcess; i++) {
      final line = lines[i];
      if (line.startsWith("#") || line.startsWith("//")) {
        final index = line.indexOf(':');
        if (index == -1) continue;
        final key = line.substring(0, index).replaceFirst(RegExp("^#|//"), "").trim().toLowerCase();
        final value = line.substring(index + 1).trim();
        headers[key] = value;
      }
    }
    return headers;
  }

  static SubscriptionInfo? _parseSubscriptionInfo(String subInfoStr) {
    final values = subInfoStr.split(';');
    final map = {for (final v in values) v.split('=').first.trim(): num.tryParse(v.split('=').second.trim())?.toInt()};
    if (map case {"upload": final upload?, "download": final download?, "total": final total, "expire": var expire}) {
      final total1 = (total == null || total == 0) ? infiniteTrafficThreshold + 1 : total;
      expire = (expire == null || expire == 0) ? infiniteTimeThreshold : expire;
      return SubscriptionInfo(
        upload: upload,
        download: download,
        total: total1,
        expire: DateTime.fromMillisecondsSinceEpoch(expire * 1000),
      );
    }
    return null;
  }

  @visibleForTesting
  static Either<ProfileFailure, ProfileEntity> parse({required String tempFilePath, required ProfileEntity profile}) =>
      Either.tryCatch(() {
        final headers = Map<String, dynamic>.from(profile.populatedHeaders ?? {});
        var name = '';
        if (profile.userOverride?.name case final String oName when oName.isNotEmpty) {
          name = oName;
        }

        if (headers['profile-title'] case final String titleHeader when name.isEmpty) {
          if (titleHeader.startsWith("base64:")) {
            name = utf8.decode(base64.decode(titleHeader.replaceFirst("base64:", "")));
          } else {
            name = titleHeader.trim();
          }
        }
        if (headers['content-disposition'] case final String contentDispositionHeader when name.isEmpty) {
          final regExp = RegExp('filename="([^"]*)"');
          final match = regExp.firstMatch(contentDispositionHeader);
          if (match != null && match.groupCount >= 1) {
            name = match.group(1) ?? '';
          }
        }
        if (profile case RemoteProfileEntity(:final url)) {
          if (Uri.parse(url).fragment case final fragment when name.isEmpty) {
            name = fragment;
          }
          if (url.split("/").lastOrNull case final part? when name.isEmpty) {
            final pattern = RegExp(r"\.(json|yaml|yml|txt)[\s\S]*");
            name = part.replaceFirst(pattern, "");
          }
        }
        if (name.isBlank) {
          switch (profile) {
            case RemoteProfileEntity():
              name = "Remote Profile";

            case LocalProfileEntity():
              name = protocol(File(tempFilePath).readAsStringSync());
          }
        }

        final isAutoUpdateDisable = profile.userOverride?.isAutoUpdateDisable ?? false;
        ProfileOptions? options;
        if (profile.userOverride?.updateInterval case final int updateInterval
            when updateInterval > 0 && !isAutoUpdateDisable) {
          options = ProfileOptions(updateInterval: Duration(hours: updateInterval));
        }
        if (headers['profile-update-interval'] case final String updateIntervalStr
            when options == null && !isAutoUpdateDisable) {
          final updateInterval = Duration(hours: int.parse(updateIntervalStr));
          options = ProfileOptions(updateInterval: updateInterval);
        }

        SubscriptionInfo? subInfo;
        if (headers['subscription-userinfo'] case final String subInfoStr) {
          subInfo = _parseSubscriptionInfo(subInfoStr);
        }

        if (subInfo != null) {
          if (headers['profile-web-page-url'] case final String profileWebPageUrl when isUrl(profileWebPageUrl)) {
            subInfo = subInfo.copyWith(webPageUrl: profileWebPageUrl);
          }
          if (headers['support-url'] case final String profileSupportUrl when isUrl(profileSupportUrl)) {
            subInfo = subInfo.copyWith(supportUrl: profileSupportUrl);
          }
        }

        return profile.map(
          remote: (rp) => rp.copyWith(name: name, lastUpdate: DateTime.now(), options: options, subInfo: subInfo),
          local: (lp) => lp.copyWith(name: name, lastUpdate: DateTime.now()),
        );
      }, ProfileFailure.unexpected);

  static String protocol(String content) {
    if (content.contains("[Interface]")) {
      return ProxyType.wireguard.label;
    }
    final lines = content.split('\n');
    String? name;
    for (final line in lines) {
      final uri = Uri.tryParse(line);
      if (uri == null) continue;
      final fragment = uri.hasFragment ? Uri.decodeComponent(uri.fragment.split(" -> ")[0]) : null;
      name ??= switch (uri.scheme) {
        'ss' => fragment ?? ProxyType.shadowsocks.label,
        'ssconf' => fragment ?? ProxyType.shadowsocks.label,
        'vmess' => ProxyType.vmess.label,
        'vless' => fragment ?? ProxyType.vless.label,
        'trojan' => fragment ?? ProxyType.trojan.label,
        'tuic' => fragment ?? ProxyType.tuic.label,
        'hy2' || 'hysteria2' => fragment ?? ProxyType.hysteria2.label,
        'hy' || 'hysteria' => fragment ?? ProxyType.hysteria.label,
        'ssh' => fragment ?? ProxyType.ssh.label,
        'wg' => fragment ?? ProxyType.wireguard.label,
        'awg' => fragment ?? ProxyType.awg.label,
        'shadowtls' => fragment ?? ProxyType.shadowtls.label,
        'mieru' => fragment ?? ProxyType.mieru.label,
        'warp' => fragment ?? ProxyType.warp.label,
        _ => null,
      };
    }
    return name ?? ProxyType.unknown.label;
  }

  static String profileOverrideHelper({required ProfileEntriesCompanion profile}) {
    final populatedHeaders = profile.populatedHeaders.value;

    Map<String, dynamic>? mPopulatedHeaders;
    if (populatedHeaders != null) {
      final m = jsonDecode(populatedHeaders) as Map;
      mPopulatedHeaders = m.cast<String, dynamic>();
    }

    return ProfileParser.profileOverride(
      populatedHeaders: mPopulatedHeaders,
      userOverride: UserOverride.fromStr(profile.userOverride.value),
    );
  }

  static String profileOverride({
    required Map<String, dynamic>? populatedHeaders,
    required UserOverride? userOverride,
  }) {
    final headers = Map<String, dynamic>.from(populatedHeaders ?? {});

    if (headers['enable-warp'].toString() == 'true' || userOverride?.enableWarp == true) {
      headers['chain-status'] = 'extra_security';
      headers['extra-security'] = {'mode': 'warp'};
    }

    if (headers['enable-fragment'].toString() == 'true' || userOverride?.enableFragment == true) {
      headers['tls-tricks'] = {'enable-fragment': true};
    }

    headers.removeWhere(
      (key, value) => !allowedOverrideConfigs.contains(key) || value == null || value.toString().isEmpty,
    );

    final profileOverrideStr = jsonEncode({for (final key in headers.keys) key: headers[key]});
    return profileOverrideStr;
  }

  static Map<String, dynamic> applyProfileOverride(Map<String, dynamic> main, String? profileOverride) {
    if (profileOverride == null) return main;
    if (profileOverride.contains("{")) {
      final profileOverrideMap = jsonDecode(profileOverride) as Map<String, dynamic>;
      return _mergeJson(main, profileOverrideMap);
    } else {
      return main;
    }
  }

  static Map<String, dynamic> _mergeJson(Map<String, dynamic> main, Map<String, dynamic> override) {
    override.forEach((key, value) {
      if (main.containsKey(key)) {
        if (main[key] is Map<String, dynamic> && value is Map<String, dynamic>) {
          main[key] = _mergeJson(main[key] as Map<String, dynamic>, value);
        } else {
          main[key] = value;
        }
      } else {
        main[key] = value;
      }
    });
    return main;
  }
}
