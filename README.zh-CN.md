# 自动文件命名助手

[English](README.md)

供快捷指令调用的原生 macOS 文件命名助手。它会验证输入、默认保留扩展名、在高风险改名时要求确认，并使用不覆盖已有文件的移动方式。

## 构建与安装

```bash
./build_and_install.sh
```

应用安装到 `~/Applications/AutoFilenameHelper.app`；请让 `Auto Filename.shortcut` 将输入传给标准输入。

## 使用方法

1. 构建并安装应用。
2. 在快捷指令中导入 `Auto Filename.shortcut`，并用 `shortcut_shell_replacement.sh` 替换其执行步骤。
3. 在 Finder 中对文件运行快捷指令；出现原生确认窗口时检查后再确认。
4. 直接打开应用可调整语言、外观、改名阈值、扩展名保留和重名处理方式。

## 功能

- 验证路径，拒绝符号链接、隐藏/不安全名称、不支持的文件类型和未改变的名称。
- 默认保留原扩展名，遇到重名时不会覆盖文件。
- 名称含糊、置信度低、可执行文件或关闭自动改名时要求确认。
- 提供快速查看、在 Finder 中显示、复制路径、明暗外观及中英文设置。

## 快捷指令协议

应用从标准输入读取换行分隔的 `PATH_B64`、`INITIAL_QUALITY`、`suggestedFilename`、`confidence` 和 `reason`。快捷指令负责产生建议；应用只负责验证和执行改名。

## 要求与隐私

构建需要 macOS 13 及以上和 Xcode Command Line Tools。应用本身不发起网络请求；若快捷指令使用 AI 服务，请单独审查其隐私行为。
