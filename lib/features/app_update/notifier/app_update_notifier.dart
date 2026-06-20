import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/app_update/data/app_update_data_providers.dart';
import 'package:hiddify/features/app_update/model/app_update_failure.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:version/version.dart';

part 'app_update_notifier.g.dart';

const _moneyflyBuildNumber = int.fromEnvironment("moneyfly_build_number");

@visibleForTesting
bool isRemoteVersionNewer({
  required RemoteVersionEntity remote,
  required String currentVersion,
  required String currentBuildNumber,
  int compiledBuildNumber = _moneyflyBuildNumber,
}) {
  if (remote.automatedBuildNumber case final int automatedBuildNumber) {
    final installedAutomatedBuild = installedBuildNumber(currentBuildNumber, compiledBuildNumber: compiledBuildNumber);
    if (installedAutomatedBuild == null || installedAutomatedBuild <= 0) return true;
    return automatedBuildNumber > installedAutomatedBuild;
  }

  final latestVersion = Version.parse(remote.version);
  final installedVersion = Version.parse(currentVersion);
  if (latestVersion != installedVersion) return latestVersion > installedVersion;

  final latestBuild = int.tryParse(remote.buildNumber);
  final installedBuild = installedBuildNumber(currentBuildNumber, compiledBuildNumber: compiledBuildNumber);
  if (latestBuild != null && installedBuild != null) return latestBuild > installedBuild;
  return false;
}

@visibleForTesting
int? installedBuildNumber(String currentBuildNumber, {int compiledBuildNumber = _moneyflyBuildNumber}) {
  return compiledBuildNumber > 0 ? compiledBuildNumber : int.tryParse(currentBuildNumber);
}

@Riverpod(keepAlive: true)
class AppUpdateNotifier extends _$AppUpdateNotifier with AppLogger {
  @override
  AppUpdateState build() => const AppUpdateState.initial();

  PreferencesEntry<String?, dynamic> get _ignoreReleasePref => PreferencesEntry(
    preferences: ref.read(sharedPreferencesProvider).requireValue,
    key: 'ignored_release_tag',
    defaultValue: null,
  );

  Future<AppUpdateState> check() async {
    loggy.debug("checking for update");
    state = const AppUpdateState.checking();
    final appInfo = ref.watch(appInfoProvider).requireValue;
    if (!appInfo.release.allowCustomUpdateChecker) {
      loggy.debug("custom update checkers are not allowed for [${appInfo.release.name}] release");
      return state = const AppUpdateState.disabled();
    }
    return ref
        .watch(appUpdateRepositoryProvider)
        .getLatestVersion()
        .match(
          (err) {
            loggy.warning("failed to get latest version", err);
            return state = AppUpdateState.error(err);
          },
          (remote) {
            try {
              if (isRemoteVersionNewer(
                remote: remote,
                currentVersion: appInfo.version,
                currentBuildNumber: appInfo.buildNumber,
              )) {
                if (remote.ignoreKey == _ignoreReleasePref.read()) {
                  loggy.debug("ignored release [${remote.ignoreKey}]");
                  return state = AppUpdateState.ignored(remote);
                }
                loggy.debug("new version available: $remote");
                return state = AppUpdateState.available(remote);
              }
              loggy.info("already using latest version[${appInfo.presentVersion}], remote: [${remote.presentVersion}]");
              return state = const AppUpdateState.notAvailable();
            } catch (error, stackTrace) {
              loggy.warning("error parsing versions", error, stackTrace);
              return state = AppUpdateState.error(AppUpdateFailure.unexpected(error, stackTrace));
            }
          },
        )
        .run();
  }

  Future<void> ignoreRelease(RemoteVersionEntity version) async {
    loggy.debug("ignoring release [${version.ignoreKey}]");
    await _ignoreReleasePref.write(version.ignoreKey);
    state = AppUpdateStateIgnored(version);
  }
}
