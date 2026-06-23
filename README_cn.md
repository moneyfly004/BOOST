# BOOST

BOOST 是对接 `https://new.moneyfly.top` 的跨平台代理与 VPN 客户端。

当前仓库：

- API: `https://new.moneyfly.top/api/v1`
- 发布页: `https://github.com/moneyfly004/BOOST/releases`
- 源码: `https://github.com/moneyfly004/BOOST`

## 版本

BOOST 客户端版本从 `1.0.0` 开始。

## 账号集成

客户端账号模块直接使用新后端 API。旧接口和旧本地账号存储键已删除。

## 构建

只使用 GitHub Actions 构建。推送到 `main`，或在 GitHub Actions 页面手动运行
`BOOST Build` workflow。

源码仓库不保存生成出来的构建产物；安装包和校验文件由 workflow 生成并发布到
GitHub Releases。
