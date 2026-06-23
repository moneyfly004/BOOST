import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/app_update/data/github_release_parser.dart';

void main() {
  group("GithubReleaseParser", () {
    test("parses BOOST automated build releases", () {
      final release = GithubReleaseParser.parse({
        "tag_name": "boost-build-12345",
        "prerelease": false,
        "html_url":
            "https://github.com/moneyfly004/boost/releases/tag/boost-build-12345",
        "published_at": "2026-06-18T00:00:00Z",
        "assets": [
          {
            "name": "BOOST-Android-universal.apk",
            "browser_download_url":
                "https://example.com/BOOST-Android-universal.apk",
          },
          {
            "name": "BOOST-macOS-universal.dmg",
            "browser_download_url":
                "https://example.com/BOOST-macOS-universal.dmg",
          },
          {
            "name": "BOOST-Windows-x64-Setup.exe",
            "browser_download_url":
                "https://example.com/BOOST-Windows-x64-Setup.exe",
          },
          {
            "name": "BOOST-Linux-x64.AppImage",
            "browser_download_url":
                "https://example.com/BOOST-Linux-x64.AppImage",
          },
        ],
      });

      expect(release.version, "0.0.0");
      expect(release.buildNumber, "12345");
      expect(release.releaseTag, "boost-build-12345");
      expect(release.automatedBuildNumber, 12345);
      expect(release.presentVersion, "Build 12345");
      expect(release.downloadUrl, isNotNull);
      expect(release.updateUrl, contains("BOOST-"));
    });

    test("keeps semantic version release parsing", () {
      final release = GithubReleaseParser.parse({
        "tag_name": "v4.1.3+40103.dev",
        "prerelease": false,
        "html_url":
            "https://github.com/moneyfly004/boost/releases/tag/v4.1.3+40103.dev",
        "published_at": "2026-06-18T00:00:00Z",
        "assets": [],
      });

      expect(release.version, "4.1.3");
      expect(release.buildNumber, "40103");
      expect(release.flavor, Environment.dev);
      expect(release.automatedBuildNumber, isNull);
      expect(release.updateUrl, release.url);
    });

    test("parses BOOST semantic release version", () {
      final release = GithubReleaseParser.parse({
        "tag_name": "v1.0.0",
        "prerelease": false,
        "html_url": "https://github.com/moneyfly004/boost/releases/tag/v1.0.0",
        "published_at": "2026-06-18T00:00:00Z",
        "assets": [
          {
            "name": "BOOST-Android-universal.apk",
            "browser_download_url":
                "https://example.com/BOOST-Android-universal.apk",
          },
          {
            "name": "BOOST-macOS-universal.dmg",
            "browser_download_url":
                "https://example.com/BOOST-macOS-universal.dmg",
          },
          {
            "name": "BOOST-Windows-x64-Setup.exe",
            "browser_download_url":
                "https://example.com/BOOST-Windows-x64-Setup.exe",
          },
          {
            "name": "BOOST-Linux-x64.AppImage",
            "browser_download_url":
                "https://example.com/BOOST-Linux-x64.AppImage",
          },
        ],
      });

      expect(release.version, "1.0.0");
      expect(release.buildNumber, "");
      expect(release.releaseTag, "v1.0.0");
      expect(release.flavor, Environment.prod);
      expect(release.automatedBuildNumber, isNull);
      expect(release.presentVersion, "1.0.0");
      expect(release.downloadUrl, isNotNull);
      expect(release.updateUrl, contains("BOOST-"));
    });
  });
}
