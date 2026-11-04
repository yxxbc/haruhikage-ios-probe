# iOS 最小验证：结论

验证工程在 `/Users/mac/Projects/haruhikage-ios-probe/`，2026-11-05 跑通。

## 验证到什么

| 环节 | 结论 | 证据 |
|---|---|---|
| Go 代码编到 iOS | **可行** | `gomobile bind` 出 arm64 + 模拟器双架构 xcframework |
| 网易 eapi 加密 | **iOS 上正确** | 搜索拿到真实结果 |
| HTTP + 自定义 UA | **被接受** | 同上 |
| deviceId 持久化 | **可行** | 写入 cache 目录，iOS 有 |
| 取播放地址 | **可行** | 拿到 `m701.music.126.net` 的 320k mp3 |
| **音频播放** | **可行** | 模拟器里 2.5 秒时播放位置到 1.43 秒 |

**一句话：核心链路（搜索 → 取地址 → 播放）在 iOS 上完全可跑。**

## 三个必须知道的坑

### 1. gomobile 的 PATH 问题

`gomobile bind` 报「gobind was not found. Please run gomobile init」，但 init 已经跑过。真正原因是它从 `PATH` 找 gobind：

```bash
PATH="$(go env GOPATH)/bin:$PATH" gomobile bind -target ios -o X.xcframework .
```

### 2. gomobile 只绑定有限类型

第一版导出 `Search(q string) ([]string, error)`，结果头文件里只有：

```
// skipped function Search with unsupported parameter or return types
```

**整个框架是空的，而编译不会报错。** 只支持字符串、数字、布尔、字节，以及它们组成的 struct。

**这对移植影响大**：`internal/netease` 返回的 `*Track`、`[]Playlist` 全要拍平成文本或 JSON 字符串，粗略估计 500–800 行适配代码。

**必须检查产物**：每次 bind 后看头文件里有没有 `FOUNDATION_EXPORT`，没有就是没导出。

### 3. Xcode 里要显式 import

`xcodegen` 配好 framework 依赖后，Swift 里还得写 `import Probe`，否则「cannot find X' in scope」。

## 已经验证的代码结构

`probe.go` 里的 eapi 是照抄 `internal/netease/eapi.go` 的，只有两处改动：

- `mygo.App.Path` → `os.UserCacheDir()`（iOS 有）
- `mygo.Secrets` → 没有用到（未登录场景）

**加密函数 `eapiEncrypt` 是逐行照抄的**，包括 `md5("nobody"+path+"use"+text+"md5forencrypt")` 和大写十六进制。这一点很重要：如果自己凭印象写，会错得很难发现。

## 还没验证的

| 项 | 难度 | 说明 |
|---|---|---|
| 登录（扫码 / Cookie） | 中 | `mygo.Secrets` 要换成 iOS Keychain，接口设计已确认 |
| 音频播放器完整能力 | 中 | 现在只有 `AVPlayer` 最基础的播放，无缝、淡入淡出、缓存都没有 |
| 本地缓存 | 低 | `mygo.App.Path` → iOS 沙盒目录 |
| 播客字幕 | **高** | sherpa-onnx 的 dylib 要自己编 iOS 静态库 |
| 界面 | **最高** | 17k 行 MyGo UI 全部重写，SwiftUI 版约 1 万行 |

## 建议的下一步顺序

1. **登录 + Cookie 持久化**（验证 Keychain 与登录态恢复）
2. **播放器封装**（队列、缓存、进度，把 `AVPlayer` 包成接近 `internal/player` 的接口）
3. **歌词**（`internal/lyrics` 是纯 Go，直接复用，只需拍平接口）
4. **界面**（最后做，因为要先定下来有哪些能力）

前三步做完，就是一个能用的命令行式内核；界面是让普通人能用。

## 重新跑验证的命令

```bash
cd /Users/mac/Projects/haruhikage-ios-probe

# 1. 编框架
PATH="$(go env GOPATH)/bin:$PATH" gomobile bind -target ios -o Probe.xcframework .

# 2. 确认有导出（空的话说明类型不支持）
grep FOUNDATION_EXPORT Probe.xcframework/ios-arm64/Probe.framework/Headers/Probe.objc.h

# 3. 编 App
cd ProbeApp
xcodegen generate
xcodebuild -project ProbeApp.xcodeproj -scheme ProbeApp \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# 4. 装到模拟器并看结果
xcrun simctl boot "iPhone 18 Pro" || true
APP=$(find ~/Library/Developer/Xcode/DerivedData/ProbeApp-*/Build/Products/Debug-iphonesimulator -name "ProbeApp.app" -maxdepth 1 | head -1)
xcrun simctl install "iPhone 18 Pro" "$APP"
xcrun simctl launch "iPhone 18 Pro" dev.yxxbc.probe
xcrun simctl io "iPhone 18 Pro" screenshot /tmp/play.png
```

## 一个注意事项

模拟器能出声并推进播放位置，说明解码与播放链路是通的。但**真机的音频会话行为不同**（后台播放、耳机拔出、来电打断），这些要真机验。你有 iPhone，之后可以自己跑一次；需要的话我可以配好真机签名步骤。
