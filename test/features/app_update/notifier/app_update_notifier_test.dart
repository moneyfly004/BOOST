import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app_update/data/app_update_data_providers.dart';
import 'package:hiddify/features/app_update/data/app_update_repository.dart';
import 'package:hiddify/features/app_update/model/app_update_failure.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('isRemoteVersionNewer', () {
    test(
      'does not report an update for the same semantic version and build number',
      () {
        final remoteVersion = RemoteVersionEntity(
          version: '1.0.0',
          buildNumber: '25',
          releaseTag: 'v1.0.0+25',
          preRelease: false,
          url: 'https://github.com/moneyfly004/boost/releases/tag/v1.0.0+25',
          publishedAt: DateTime(2026, 6, 20),
          flavor: Environment.prod,
        );

        expect(
          isRemoteVersionNewer(
            remote: remoteVersion,
            currentVersion: '1.0.0',
            currentBuildNumber: '25',
          ),
          isFalse,
        );
      },
    );

    test('reports an update only when the remote build number is greater', () {
      final remoteVersion = RemoteVersionEntity(
        version: '1.0.0',
        buildNumber: '26',
        releaseTag: 'v1.0.0+26',
        preRelease: false,
        url: 'https://github.com/moneyfly004/boost/releases/tag/v1.0.0+26',
        publishedAt: DateTime(2026, 6, 20),
        flavor: Environment.prod,
      );

      expect(
        isRemoteVersionNewer(
          remote: remoteVersion,
          currentVersion: '1.0.0',
          currentBuildNumber: '25',
        ),
        isTrue,
      );
    });

    test('reports an update when the remote patch version is greater', () {
      final remoteVersion = RemoteVersionEntity(
        version: '1.0.1',
        buildNumber: '',
        releaseTag: 'v1.0.1',
        preRelease: false,
        url: 'https://github.com/moneyfly004/boost/releases/tag/v1.0.1',
        publishedAt: DateTime(2026, 6, 22),
        flavor: Environment.prod,
      );

      expect(
        isRemoteVersionNewer(
          remote: remoteVersion,
          currentVersion: '1.0.0',
          currentBuildNumber: '10000',
        ),
        isTrue,
      );
    });

    test(
      'uses the compiled BOOST build number when package build metadata is stale',
      () {
        final remoteVersion = RemoteVersionEntity(
          version: '1.0.0',
          buildNumber: '25',
          releaseTag: 'v1.0.0+25',
          preRelease: false,
          url: 'https://github.com/moneyfly004/boost/releases/tag/v1.0.0+25',
          publishedAt: DateTime(2026, 6, 20),
          flavor: Environment.prod,
        );

        expect(
          isRemoteVersionNewer(
            remote: remoteVersion,
            currentVersion: '1.0.0',
            currentBuildNumber: '1',
            compiledBuildNumber: 25,
          ),
          isFalse,
        );
      },
    );
  });

  test(
    'check reports an available update for a newer semantic build number',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final remoteVersion = RemoteVersionEntity(
        version: '1.0.0',
        buildNumber: '15',
        releaseTag: 'v1.0.0+15',
        preRelease: false,
        url: 'https://github.com/moneyfly004/boost/releases/tag/v1.0.0+15',
        publishedAt: DateTime(2026, 6, 18),
        flavor: Environment.prod,
        downloadUrl:
            'https://github.com/moneyfly004/boost/releases/latest/download/BOOST-macOS-universal.dmg',
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => preferences),
          appInfoProvider.overrideWith(
            () => _FakeAppInfo(
              const AppInfoEntity(
                name: 'BOOST',
                version: '1.0.0',
                buildNumber: '14',
                release: Release.general,
                operatingSystem: 'macos',
                operatingSystemVersion: 'Version 15.0',
                environment: Environment.prod,
              ),
            ),
          ),
          appUpdateRepositoryProvider.overrideWith(
            (ref) => _FakeAppUpdateRepository(remoteVersion),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appInfoProvider.future);
      await container.read(sharedPreferencesProvider.future);
      final state = await container
          .read(appUpdateNotifierProvider.notifier)
          .check();

      expect(state, isA<AppUpdateStateAvailable>());
      expect(
        (state as AppUpdateStateAvailable).versionInfo.releaseTag,
        'v1.0.0+15',
      );
      expect(state.versionInfo.presentVersion, '1.0.0 (15)');
    },
  );
}

class _FakeAppInfo extends AppInfo {
  _FakeAppInfo(this.info);

  final AppInfoEntity info;

  @override
  Future<AppInfoEntity> build() async => info;
}

class _FakeAppUpdateRepository implements AppUpdateRepository {
  const _FakeAppUpdateRepository(this.version);

  final RemoteVersionEntity version;

  @override
  TaskEither<AppUpdateFailure, RemoteVersionEntity> getLatestVersion({
    bool includePreReleases = false,
    Release release = Release.general,
  }) {
    return TaskEither.right(version);
  }
}
