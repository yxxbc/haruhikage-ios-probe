# 春日影 · iOS 探针

一个能跑的 iOS 音乐播放器，验证「桌面版的 Go 内核能不能搬到手机上」。

**结论：能。** 搜索、播放、缓存、队列、后台、锁屏、歌词、收藏、歌单，全在真机可跑。

## 从零开始

```bash
# 0. 这个仓库
git clone https://github.com/yxxbc/haruhikage-ios-probe.git
cd haruhikage-ios-probe

# 1. 主仓库要先在旁边（框架从这里取代码）
git clone https://github.com/yxxbc/haruhikage-app.git ../mygo-cloudmusic

# 2. 编 Go 框架（约 1 分钟，54 MB）
./build-framework.sh

# 3. 检查环境
./check-env.sh

# 4. 生成 Xcode 工程并打开
cd ProbeApp && xcodegen generate && open ProbeApp.xcodeproj
```

`go.mod` 里的 `replace` 指向 `../mygo-cloudmusic`：改成本机实际路径。

## 装到手机

见 [RUN-ON-DEVICE.md](RUN-ON-DEVICE.md)。要点是一次性选好 Team、改掉 Bundle ID。

## 代码在哪

| 路径 | 是什么 |
|---|---|
| `all/` | Go 侧：所有导出给 Swift 的函数，一个包 |
| `ProbeApp/ProbeApp/` | SwiftUI 界面 |
| `ProbeApp/ProbeAppTests/` | 测试，20 个 |
| `ProbeApp/Resources/` | 无 |

**为什么只有一个 Go 包**：gomobile 把整套 Go 运行时打进每个框架，两个框架同时链接会互相踩符号，表现为启动即段错误。所以 `all/` 是唯一入口。

## 这份代码的定位

它是**验证工程**，不是产品：界面能用但简单，功能覆盖核心但不完整。它证明的是「可行」，以及**踩过哪些坑**——那些写在 `COMPILE-REPORT.md` 里，比代码本身更值钱。

## 已知取舍

- 播放用 `AVPlayer`，没有无缝切歌和淡入淡出
- 缓存按 512 MB 上限删最久未播，不做分级
- 没有歌词逐字动画
- 界面是深色单主题
