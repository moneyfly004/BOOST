# BOOST

BOOST is a cross-platform proxy and VPN client backed by `https://new.moneyfly.top`.

This repository is the Flutter client for:

- API: `https://new.moneyfly.top/api/v1`
- Releases: `https://github.com/moneyfly004/boost/releases`
- Source: `https://github.com/moneyfly004/boost`

## Version

The BOOST client version starts at `1.0.0`.

## Account Integration

The account module uses the new backend API directly. Legacy endpoints and local account storage keys have been removed.

## Build

Use the normal Flutter workflow for the target platform:

```sh
flutter pub get
flutter build apk
flutter build macos
flutter build windows
flutter build linux
```
