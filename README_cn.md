# BOOST

BOOST 是对接 `https://new.moneyfly.top` 的跨平台代理与 VPN 客户端。

当前仓库：

- API: `https://new.moneyfly.top/api/v1`
- 发布页: `https://github.com/moneyfly004/boost/releases`
- 源码: `https://github.com/moneyfly004/boost`

## 版本

BOOST 客户端版本从 `1.0.0` 开始。

## 账号集成

客户端账号模块直接使用新后端 API。旧接口和旧本地账号存储键已删除。

## 构建

按 Flutter 标准流程构建目标平台：

```sh
flutter pub get
flutter build apk
flutter build macos
flutter build windows
flutter build linux
```
