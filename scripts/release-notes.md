## 安装

1. 单独安装并启动 [Atoll](https://github.com/Ebullioscopic/Atoll/releases)；在
   `Settings → Extensions` 开启第三方扩展、extension notch experiences、extension
   tabs 和 interactive web content。
2. 下载并解压本 release 的 `atoll-being-bridge-*-macos-universal.zip`，双击一次
   `install.command`（无需 Xcode 或 sudo）。
3. 在 Atoll 的 **Being** tab 粘贴 Loom 中的完整 Being URL（URL 已带 token），点击
   **保存并连接**。

此归档只包含 Atoll Being Bridge，不包含、也不替换 Atoll。它使用预编译 universal
binary，支持 Apple Silicon 和 Intel Mac，不需要 Xcode。Atoll 是独立宿主，因此不能
把两者打成一个静默安装包；装好 Atoll 后，Bridge 本身只需上述一次双击安装。

## Beta 边界

官方 Atoll 的 420pt extension-tab 高度修复尚未上游合并；本 beta 不承诺所有官方
Atoll 版本都不会裁切长回复面板。请先安装最新 Atoll 并实测，遇到裁切不要靠重装
bridge 解决。

## 本版内容

- Soul 的回复、发送、草稿恢复和收起时的高层状态显示。
- Soul 现在是独立的 `atoll-{beingName}` Loom scene：不会混入 Desktop / Workbench
  对话；旧的无 scene 消息和自主呼吸仍按 Loom 兼容规则显示。
- `scene_id` 与 Atoll 的 scene metadata 由本机 bridge 注入，token 不进入 Atoll
  页面或上游消息 body。
- 被 202 排队的消息会以 2 秒至 30 秒退避核对 active stream / history，最长 5 分钟；
  system marker 显示为分隔提示。
- 鼠标离开面板时会先保存未发送草稿、再释放网页焦点，Atoll 会恢复成实时状态药丸。
- Being tab 选中图标改为与 Atoll 原生 tab 一致的白色；状态色仅保留在活动药丸。
- URL 只在本机 owner-only 文件中保存；没有 OpenRouter 配置。

完整前置条件、Atoll Extensions 开关和兼容性边界见归档内的 README。
