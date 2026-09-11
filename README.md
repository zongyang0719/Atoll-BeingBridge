# Atoll Being Bridge

把 Being / Soul 放进 Atoll 刘海的本地桥接：收起时显示 Loom 同级的状态，hover
后可查看回复、发送消息；未发送的草稿在收起后仍会保留。

This is a local bridge for the [Atoll](https://github.com/Ebullioscopic/Atoll)
host. It is not an Atoll fork and does not install a second settings app.

## 安装（推荐：下载发布包）

1. 先从 [Atoll Releases](https://github.com/Ebullioscopic/Atoll/releases) 安装并启动
   Atoll。它是刘海宿主，**不能**由本桥接替代或随包分发。
2. 在 Atoll 的 `Settings → Extensions` 中开启：`Enable third-party extensions`、
   `Allow extension notch experiences`、`Show extension tabs` 和
   `Allow interactive web content`。
3. 从本仓库的 [Releases](https://github.com/zongyang0719/Atoll-BeingBridge/releases)
   下载最新的 `atoll-being-bridge-*-macos-universal.zip`，解压后双击
   `install.command`；也可在该目录运行：

   ~~~sh
   zsh install.sh
   ~~~

   不要使用 `sudo`：Bridge 必须注册到当前登录用户的 Atoll 会话。

4. 打开 Atoll 刘海中的 **Being** tab，粘贴 Loom 里复制的完整 Being URL（URL
   后缀自带 token），点 **保存并连接**。

发布包已含 Apple Silicon 和 Intel 的预编译二进制，不需要 Xcode。第一次从网络
下载的未公证命令行二进制如被 macOS 拦截，请在“系统设置 → 隐私与安全性”选择
“仍要打开”，再运行一次安装脚本。

### 只需要配置什么？

只需要完整 Being URL；没有单独的 token、用户名、OpenRouter 或独立设置页。
桥接会从 Being 状态接口自动读取名称。

- **测试连接**：只验证 URL 能否连上 Being，不保存。
- **保存并连接**：同样会验证，成功后才保存并打开 Soul；因此可以直接点它。

## 功能与边界

- 收起刘海时显示“在思考 / 在行动 / 在回复”等高层状态，不显示推理原文。
- 选中 Being tab 的导航图标与 Atoll 原生 tab 一样使用白色；状态颜色仅用于
  思考药丸和内容状态。
- 输入框内容在 hover 收起、WebView 重建后会恢复；bridge 重启前不会写入 Being。
- OpenRouter 不在本项目范围内，也不会被读取或配置。

## 安全与本地数据

完整 URL（含 token）只保存在当前用户的：

~~~text
~/.being-notch/being-url
~~~

该文件权限为仅当前用户可读。token 不会进入 Atoll descriptor、嵌入页面、日志或
仓库；非敏感渲染设置单独存于 `~/.being-notch/config.json`。

网页只访问 `127.0.0.1` 本地 bridge，由它代为请求 Being。URL 在成功保存后会从
输入框清空，永远不会进入 Atoll descriptor。

## 兼容性

- 需要 macOS 14 或更新版本，以及能运行 Atoll 的 Mac。
- Atoll 是独立项目，会自行更新。这个发布包不替换、不重签官方 Atoll。
- Atoll 的扩展 tab 理论范围是 160–420pt；若某个官方 Atoll 版本仍把 420pt tab
  截成约 200pt，这是宿主侧问题，不是桥接可通过重新安装解决的问题。当前本机的
  高度修复尚未上游合并，公开使用前请先用最新 Atoll 实测长回复面板。

## 从源码构建

~~~sh
zsh scripts/verify-public.sh
zsh install.sh
~~~

`build.sh` 只生成 universal binary；`install.sh` 才会把它安装成当前用户的
LaunchAgent。

## License and notices

Atoll Being Bridge is MIT licensed. Third-party runtime and protocol notices
are in [NOTICE](NOTICE).
