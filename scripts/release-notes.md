## 安装

1. 单独安装并启动 [Atoll](https://github.com/Ebullioscopic/Atoll/releases)。
2. 下载并解压本 release 的 `atoll-being-bridge-*-macos-universal.zip`。
3. 双击 `install.command`，或在解压目录运行 `zsh install.sh`。
4. 在 Atoll 的 **Being** tab 粘贴 Loom 中的完整 Being URL（URL 已带 token），点击
   **保存并连接**。

此归档只包含 Atoll Being Bridge，不包含、也不替换 Atoll。它使用预编译 universal
binary，支持 Apple Silicon 和 Intel Mac，不需要 Xcode。

## Beta 边界

官方 Atoll 的 420pt extension-tab 高度修复尚未上游合并；本 beta 不承诺所有官方
Atoll 版本都不会裁切长回复面板。请先安装最新 Atoll 并实测，遇到裁切不要靠重装
bridge 解决。

## 本版内容

- Soul 的回复、发送、草稿恢复和收起时的高层状态显示。
- 鼠标离开面板时会先保存未发送草稿、再释放网页焦点，Atoll 会恢复成实时状态药丸。
- Being tab 选中图标改为与 Atoll 原生 tab 一致的白色；状态色仅保留在活动药丸。
- URL 只在本机 owner-only 文件中保存；没有 OpenRouter 配置。

完整前置条件、Atoll Extensions 开关和兼容性边界见归档内的 README。
