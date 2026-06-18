import 'package:dartx/dartx.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/utils/platform_utils.dart';

abstract class GithubReleaseParser {
  static RemoteVersionEntity parse(Map<String, dynamic> json) {
    final fullTag = json['tag_name'] as String;
    final automatedBuildNumber = _parseAutomatedBuildNumber(fullTag);
    final versionParts = automatedBuildNumber == null ? fullTag.removePrefix("v").split("-").first.split("+") : null;
    var version = versionParts?.firstOrNull ?? "0.0.0";
    var buildNumber = versionParts?.elementAtOrElse(1, (index) => "") ?? automatedBuildNumber.toString();
    var flavor = Environment.prod;
    for (final env in Environment.values) {
      final suffix = ".${env.name}";
      if (version.endsWith(suffix)) {
        version = version.removeSuffix(suffix);
        flavor = env;
        break;
      } else if (buildNumber.endsWith(suffix)) {
        buildNumber = buildNumber.removeSuffix(suffix);
        flavor = env;
        break;
      }
    }
    final preRelease = json["prerelease"] as bool;
    final publishedAt = DateTime.parse(json["published_at"] as String);
    final assets = (json["assets"] as List? ?? const []).whereType<Map<String, dynamic>>();
    final downloadUrl = _selectDownloadUrl(assets);
    return RemoteVersionEntity(
      version: version,
      buildNumber: buildNumber,
      releaseTag: fullTag,
      preRelease: preRelease,
      url: json["html_url"] as String,
      publishedAt: publishedAt,
      flavor: flavor,
      downloadUrl: downloadUrl,
      automatedBuildNumber: automatedBuildNumber,
    );
  }

  static int? _parseAutomatedBuildNumber(String tag) {
    final match = RegExp(r'^moneyfly-build-(\d+)$').firstMatch(tag);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String? _selectDownloadUrl(Iterable<Map<String, dynamic>> assets) {
    final namedUrls = {
      for (final asset in assets)
        if (asset["name"] case final String name)
          if (asset["browser_download_url"] case final String url) name: url,
    };

    String? firstMatching(List<String> patterns) {
      for (final pattern in patterns) {
        final match = namedUrls.entries.firstOrNullWhere((entry) => entry.key.contains(pattern));
        if (match != null) return match.value;
      }
      return null;
    }

    if (PlatformUtils.isAndroid) {
      return firstMatching(["Android-universal.apk", "Android-arm64-v8a.apk", "Android"]);
    }
    if (PlatformUtils.isWindows) {
      return firstMatching(["Windows-x64-Setup.exe", "Windows-x64-Portable.zip", "Windows"]);
    }
    if (PlatformUtils.isMacOS) {
      return firstMatching(["macOS-universal.dmg", "macOS-universal.pkg", "macOS"]);
    }
    if (PlatformUtils.isLinux) {
      return firstMatching(["Linux", "AppImage", ".deb", ".rpm"]);
    }
    return null;
  }
}
