import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/app_update/data/github_release_parser.dart';

void main() {
  group("GithubReleaseParser", () {
    test("parses MoneyFly automated build releases", () {
      final release = GithubReleaseParser.parse({
        "tag_name": "moneyfly-build-12345",
        "prerelease": false,
        "html_url": "https://github.com/moneyfly004/cboard/releases/tag/moneyfly-build-12345",
        "published_at": "2026-06-18T00:00:00Z",
        "assets": [
          {
            "name": "MoneyFly-Android-universal.apk",
            "browser_download_url": "https://example.com/MoneyFly-Android-universal.apk",
          },
          {
            "name": "MoneyFly-macOS-universal.dmg",
            "browser_download_url": "https://example.com/MoneyFly-macOS-universal.dmg",
          },
          {
            "name": "MoneyFly-Windows-x64-Setup.exe",
            "browser_download_url": "https://example.com/MoneyFly-Windows-x64-Setup.exe",
          },
          {
            "name": "MoneyFly-Linux-x64.AppImage",
            "browser_download_url": "https://example.com/MoneyFly-Linux-x64.AppImage",
          },
        ],
      });

      expect(release.version, "0.0.0");
      expect(release.buildNumber, "12345");
      expect(release.releaseTag, "moneyfly-build-12345");
      expect(release.automatedBuildNumber, 12345);
      expect(release.presentVersion, "Build 12345");
      expect(release.downloadUrl, isNotNull);
      expect(release.updateUrl, contains("MoneyFly-"));
    });

    test("keeps semantic version release parsing", () {
      final release = GithubReleaseParser.parse({
        "tag_name": "v4.1.3+40103.dev",
        "prerelease": false,
        "html_url": "https://github.com/moneyfly004/cboard/releases/tag/v4.1.3+40103.dev",
        "published_at": "2026-06-18T00:00:00Z",
        "assets": [],
      });

      expect(release.version, "4.1.3");
      expect(release.buildNumber, "40103");
      expect(release.flavor, Environment.dev);
      expect(release.automatedBuildNumber, isNull);
      expect(release.updateUrl, release.url);
    });

    test("parses MoneyFly semantic release version", () {
      final release = GithubReleaseParser.parse({
        "tag_name": "v1.0.1",
        "prerelease": false,
        "html_url": "https://github.com/moneyfly004/cboard/releases/tag/v1.0.1",
        "published_at": "2026-06-18T00:00:00Z",
        "assets": [
          {
            "name": "MoneyFly-Android-universal.apk",
            "browser_download_url": "https://example.com/MoneyFly-Android-universal.apk",
          },
          {
            "name": "MoneyFly-macOS-universal.dmg",
            "browser_download_url": "https://example.com/MoneyFly-macOS-universal.dmg",
          },
          {
            "name": "MoneyFly-Windows-x64-Setup.exe",
            "browser_download_url": "https://example.com/MoneyFly-Windows-x64-Setup.exe",
          },
          {
            "name": "MoneyFly-Linux-x64.AppImage",
            "browser_download_url": "https://example.com/MoneyFly-Linux-x64.AppImage",
          },
        ],
      });

      expect(release.version, "1.0.1");
      expect(release.buildNumber, "");
      expect(release.releaseTag, "v1.0.1");
      expect(release.flavor, Environment.prod);
      expect(release.automatedBuildNumber, isNull);
      expect(release.presentVersion, "1.0.1");
      expect(release.downloadUrl, isNotNull);
      expect(release.updateUrl, contains("MoneyFly-"));
    });
  });
}
