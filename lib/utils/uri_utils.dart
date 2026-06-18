import 'dart:io';

import 'package:hiddify/utils/custom_loggers.dart';
import 'package:loggy/loggy.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

abstract class UriUtils {
  static final loggy = Loggy<InfraLogger>("UriUtils");

  static Future<bool> tryShareOrLaunchFile(Uri uri, {Uri? fileOrDir}) async {
    if (Platform.isWindows || Platform.isLinux) {
      return tryLaunch(fileOrDir ?? uri);
    }
    return tryShareFile(uri);
  }

  static Future<bool> tryLaunch(Uri uri) async {
    try {
      loggy.debug("launching [$uri]");
      if (!await canLaunchUrl(uri)) {
        loggy.warning("can't launch [$uri]");
        return false;
      }
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, stackTrace) {
      loggy.warning("error launching [$uri]", e, stackTrace);
      return false;
    }
  }

  static Future<bool> tryOpenDirectory(Directory dir) async {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      if (Platform.isMacOS) {
        return _tryRunOpenCommand("/usr/bin/open", [dir.path]);
      }
      if (Platform.isWindows) {
        return _tryRunOpenCommand("explorer.exe", [dir.path]);
      }
      if (Platform.isLinux) {
        return _tryRunOpenCommand("xdg-open", [dir.path]);
      }

      return tryLaunch(dir.uri);
    } catch (e, stackTrace) {
      loggy.warning("error opening directory [${dir.path}]", e, stackTrace);
      return false;
    }
  }

  static Future<bool> _tryRunOpenCommand(String executable, List<String> arguments) async {
    try {
      loggy.debug("running [$executable ${arguments.join(' ')}]");
      final result = await Process.run(executable, arguments);
      if (result.exitCode == 0) return true;
      loggy.warning("failed running [$executable], exitCode: ${result.exitCode}, stderr: ${result.stderr}");
      return false;
    } catch (e, stackTrace) {
      loggy.warning("error running [$executable]", e, stackTrace);
      return false;
    }
  }

  static Future<bool> tryShareFile(Uri uri, {String? mimeType}) async {
    try {
      loggy.debug("sharing [$uri]");
      final file = XFile(uri.path, mimeType: mimeType);
      final result = await Share.shareXFiles([file]);
      loggy.debug("share result: ${result.raw}");
      return result.status == ShareResultStatus.success;
    } catch (e, stackTrace) {
      loggy.warning("error sharing file [$uri]", e, stackTrace);
      return false;
    }
  }
}
