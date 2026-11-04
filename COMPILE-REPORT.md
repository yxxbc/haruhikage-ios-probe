# iOS 移植：能编到 iOS 到什么程度

2026-11-05，用 `GOOS=ios GOARCH=arm64 CGO_ENABLED=1 go build` 实测。

## 结论

**整个项目都能编到 iOS，但窗口层跑不起来。**

| 包 | 编到 iOS | 说明 |
|---|---|---|
| `internal/lyrics` | ✓ 无需 cgo | 纯 Go |
| `internal/netease` | ✓ 需 cgo | 只因 `mygo/internal/darwin` 用 purego |
| `internal/player` | ✓ 需 cgo | 同上 |
| `internal/speech` | ✓ 需 cgo | 同上 |
| `internal/app` | ✓ 需 cgo | 同上 |

**关键：`CGO_ENABLED=1` 是必须的。** 默认 `CGO_ENABLED=0` 时，`purego` 在 iOS 上报：

```
is_ios.go:13:9: undefined: _PUREGO_REQUIRES_CGO_ON_IOS
```

纯 Go 的包则不受影响，`lyrics` 在两种设置下都能编。

## 编译通过 ≠ 能运行

这是最重要的一条。

`mygo/ui` 的绘制、布局、Metal 渲染都是平台无关的，**这部分能在 iOS 上跑**。但：

| 层 | iOS 状况 |
|---|---|
| `ui` 的布局与绘制 | ✓ 与平台无关 |
| `ui/gpu_darwin.go` → `internal/gpu/metal` | ✓ iOS 也有 CAMetalLayer，理论可用 |
| `internal/darwin`（13276 行，50 个文件） | ✗ **macOS 的 NSWindow / NSApp / NSMenu** |

`internal/darwin` 用 `NSApplication`、`NSWindow`、`NSPanel` 这些 **AppKit** API，iOS 没有 AppKit，只有 UIKit。所以：

- 编译能过，是因为 purego 是动态调用，编译期不检查符号
- 运行时一旦碰窗口，就会是找不到符号或行为错乱

## 这意味着什么

**不需要重写整个 UI 框架。** 需要替换的是「谁创建窗口、谁分发输入、谁画到屏幕」这一层，约 1.3 万行，且是 `mygo` 的内部包，不是你项目里的代码。

可行的做法：

1. **Fork `mygo`**，给 `internal/darwin` 加 iOS 分支，用 UIKit 的 `UIView` + `CAMetalLayer` 替代 NSWindow
2. 或者**不 fork**：在你的 app 里自己起一个 Metal 层，直接调 `ui` 包内部的绘制（但它不是公开 API，风险高）

第一条路更干净，代价是维护一个 fork。

## 与最小验证的关系

`haruhikage-ios-probe` 里已经证明：搜索、取播放地址、AVPlayer 播放都能在 iOS 上跑。那部分是纯 Go + iOS 原生 SwiftUI 界面。

**所以现在有两条路：**

| 路线 | 界面 | 代价 |
|---|---|---|
| A：Fork mygo 补 iOS 窗口层 | 复用现有 17k 行 `internal/app` | 维护 fork，写 UIKit 窗口桥接 |
| B：Go 内核 + SwiftUI 界面 | 重写界面约 1 万行 | 不用碰 mygo |

**路线 A 的隐藏风险**：`internal/app` 那 17k 行大量用了窗口、菜单栏、托盘、刘海这些**桌面概念**，即使窗口层补好了，很多页面在手机上没有意义（刘海播放器、菜单栏图标、托盘菜单）。所以 A 省下的可能只是「布局与绘制的写法」，而不是全部界面。

## 建议

**先做 B 的骨架，但复用 A 的思路**：

1. 用 gomobile 把 `netease` + `lyrics` 编成框架（已验证可行）
2. SwiftUI 写界面
3. 播放用 `AVAudioEngine`
4. `internal/app` 里的**业务逻辑**（如何时刷新、队列规则、离线缓存策略）读代码移植，而不是复制文件

这样不用维护 mygo fork，也不用碰 UIKit 桥接这种底层活。

## 待验证

- [ ] 登录（Cookie + Keychain）
- [ ] 真机（模拟器的音频行为与真机不同）
- [ ] `internal/lyrics` 通过 gomobile 导出（纯 Go，应该没问题，但要试）
- [ ] 后台播放、锁屏控制（`MPNowPlayingInfoCenter`）

---

# 追加：两个决定架构的发现

## 1. 一个 App 只能链接一个 Go 框架

先做了 `Probe.xcframework`（网络 + 播放）和 `Lyrics.xcframework`（歌词）两个，App 里都链接。

**结果：启动即崩溃**，`EXC_BAD_ACCESS at 0x30`。

原因：gomobile 把**整个 Go 运行时打进每个框架**。实测两个框架各含近 2000 个 `runtime.*` / `_cgo_*` 符号，同时加载必然冲突。

```
Probe    1982 个 runtime/_cgo 符号
Lyrics   1864 个 runtime/_cgo 符号
```

**解法：所有导出都合到一个包、一个框架。** 现在 `all` 包导出六个函数：

```
AllVersion
AllSearch(q, limit)
AllSongURL(id, level)
AllParseLyrics(lrc, translation)
AllRomaji(text)
AllIsCredit(text)
```

这一条对架构的影响很大：**不能按模块拆框架**，`netease`、`lyrics`、`player` 的导出必须放在同一个 Go 包里，或至少同一个 bind 目标。

## 2. `internal` 包不能被外部模块引用

想在自己的探针工程里 `import ".../internal/lyrics"`，Go 直接拒绝：

```
use of internal package github.com/yxxbc/haruhikage-app/internal/lyrics not allowed
```

**含义：iOS 工程不能直接复用 `internal/` 下的代码。** 三个选择：

| 做法 | 代价 |
|---|---|
| 把包移出 `internal/`（如 `pkg/lyrics`） | 改主项目结构，但一次到位 |
| iOS 工程放进同一个 module | 可行，但两个平台混在一起 |
| 复制代码 | 双份维护，最差 |

**推荐第一条**：把将来要共享的包移到 `pkg/`，桌面端自己 import 新的路径。改动只在 import 行，`go build` 会全部指出来。

## 现在验证过的完整清单

| 能力 | 状态 |
|---|---|
| Go 编到 iOS（含 cgo） | ✓ |
| 搜索 | ✓ |
| 取播放地址 | ✓ |
| AVPlayer 播放 | ✓ 位置真实推进 |
| 歌词解析（时间/原文/翻译） | ✓ |
| 罗马音（含中文不误转） | ✓ |
| 单框架多模块 | ✓ |

## 还没做

- 登录（Cookie + iOS Keychain）
- 真机（模拟器音频行为与真机不同）
- 队列、缓存、进度持久化
- 界面（现在是最土的 SwiftUI 列表）

---

# 追加：登录与 Keychain

## 验证到

- 二维码登录：`QRKey` 拿到 key，`QRLoginURL` 生成网址，`QRCheck` 轮询到 801（等待扫码）
- Cookie 在 Go 侧可读出（`Session`）与写回（`Restore`）
- **iOS Keychain 读写成功**，会话能跨启动保留

## 第三个坑：Keychain 需要签名

不签名直接跑，`SecItemAdd` 返回 **-34018**（`errSecMissingEntitlement`）。

模拟器上不签名也能启动，所以很容易以为 Keychain 坏了。真正原因是没有 `keychain-access-groups`。

**解法**：工程里加 entitlements 并开 ad-hoc 签名。

```xml
<!-- ProbeApp/ProbeApp.entitlements -->
<key>keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)dev.yxxbc.probe</string></array>
```

```
CODE_SIGNING_ALLOWED: YES
CODE_SIGN_IDENTITY: "-"          # ad-hoc，模拟器够用
CODE_SIGN_ENTITLEMENTS: ProbeApp/ProbeApp.entitlements
```

**注意**：`codesign -d --entitlements -` 在模拟器产物上可能显示空的 `[Dict]`，这不代表失败——以运行时有没有 -34018 为准。

## Keychain 的职责划分

Go 侧在 iOS 上没有 Keychain 访问能力（`mygo.Secrets` 是 macOS 的），所以：

| 方向 | 谁做 |
|---|---|
| 登录成功 → 拿到 cookie | Go（`Session()` 返回 `"name=value; …"`） |
| 存进 Keychain | **Swift**（`SecItemAdd`） |
| 启动时读出来 → 交给 Go | **Swift** 读，`Restore(cookie)` 交给 Go |
| 判断是否已登录 | Go 问服务器（`LoggedIn()`） |

**这个分工必须在架构里定下来**：会话的保存归界面侧，业务判断归 Go 侧。

---

# 追加：完整闭环

**登录 → 搜索 → 列表 → 播放 → 歌词滚动，全部在 iOS 上跑通。**

截图证据（模拟器，真实网络数据）：

| 屏 | 显示 |
|---|---|
| 搜索 | 「晴天 周杰伦」20 条结果，当前曲目旁有喇叭图标 |
| 播放 | 底部进度到 9 秒，暂停图标亮着 |
| 歌词 | 随播放加粗当前行（「合声编写：周杰伦」），进度 13 秒 |

## 框架的最终接口（17 个导出）

```
AllVersion()                      框架版本
AllSearch(q, limit)               搜索，"id\t歌名"
AllSongURL(id, level)             播放地址，"url\t类型\t音质"
AllLyricsFor(id)                  取并解析歌词
AllParseLyrics(lrc, translation)  解析本地 LRC
AllRomaji(text)                   假名转罗马音
AllIsCredit(text)                 判断是否制作信息行
AllQRKey()                        取二维码 key
AllQRLoginURL(key)                生成登录网址
AllQRCheck(key)                   轮询登录状态
AllSession()                      读当前 cookie
AllRestore(cookie)                恢复 cookie
AllLoggedIn()                     问服务器当前用户
AllQRWaiting/Scanned/Confirmed/Expired  状态常量
```

## 数据传递的固定约定

所有跨语言的数据都是**制表符分隔的文本**：

| 数据 | 格式 |
|---|---|
| 搜索结果 | `id\t歌名`，一行一条 |
| 播放地址 | `url\t类型\t音质` |
| 歌词 | `毫秒\t原文\t翻译\t罗马音`，一行一条 |
| 登录状态 | `code\tnickname\tavatar` |
| 失败 | 以 `ERR: ` 开头 |

**Swift 侧统一按 `\t` 切分**，不要引入 JSON：切分比解码简单，且能直接看出问题。

## 集成时踩到的

**`List` 里的 `Button` 会撑满整行**，`buttonStyle(.plain)` 才不显示蓝色。这是界面细节，但一开始会疑惑为什么点哪儿都触发。

## 现在可以做什么

`ProbeApp` 已经是一个能用的最小播放器：

1. 启动读 Keychain 恢复登录
2. 搜索并列出结果
3. 点一首播放，进度实时
4. 歌词随播放高亮

**它离「日常能用」还差：**

- 真正的二维码显示（现在只显示 URL 字符串）
- 歌曲列表要显示歌手和专辑封面
- 播放队列与切歌
- 缓存（重复播放不重新下载）
- 锁屏控制与后台播放
- 界面设计

## 建议的下一步

**优先做缓存与队列**，因为它们决定「用起来顺不顺」；界面设计可以最后做，那时能力已经定型。

缓存的做法：`AllSongURL` 已经把 URL 给了 Swift，Swift 用 `URLSession.downloadTask` 存到 Caches 目录，下次同一个 id 直接读本地。这一层完全在 Swift，不需要改 Go。

---

# 追加：可扫的二维码

**iOS 上现在能真的扫码登录了。**

## 做法

二维码的编码在 Go 侧，用桌面版同一个库（`rsc.io/qr`），所以两个平台画出的是同一个码：

```go
qr.Encode(QRLoginURL(key), qr.M)   // 37×37 模块
```

矩阵作为文本过桥：

```
37
0111011011…   ← 每行 37 个字符，1 = 深色
…（共 37 行）
```

Swift 收到后自己画（`Canvas`），不是传位图。**好处**：任意尺寸都清晰，不用处理像素。

## 怎么验的

不靠肉眼。用 macOS 的 Vision 框架（`VNDetectBarcodesRequest`）扫模拟器截图：

```
$ /tmp/dq /tmp/qr.png
https://music.163.com/login?codekey=603e1905-be6d-40dd-a7f1-c7e7c64867c4
```

**解出来的 URL 与 `AllQRLoginURL` 返回的完全一致**，说明编码、传输、绘制三步都对。

这个验证办法值得留着：以后改了二维码的绘制，用它确认还能扫，而不是看着像就行。

## 登录流程现在完整了

1. 「扫码登录」→ Go 取 key
2. Go 生成 37×37 矩阵 → Swift 画出来
3. 用户用网易云 App 扫
4. Swift 每 2 秒问一次状态
5. 803 时把 cookie 存进 Keychain，界面切到已登录
6. 下次启动从 Keychain 恢复，不用再扫

---

# 追加：缓存与队列

## 做到

**缓存**：播过的歌存在 `Library/Caches/songs/`，下次直接读本地，不再联网。

- 文件名 `id-音质.格式`，如 `2668397359-exhigh.mp3`
- 下载先写 `.part` 再改名，所以半截文件能被识别并丢弃
- 超过 512MB 时按最久未播放删除

**队列**：点一首歌，把列表从它开始到末尾、再从开头到它之前，排成队列。

- 一首播完自动下一首（`AVPlayerItemDidPlayToEndTime`）
- 上一首 / 下一首按钮
- 底部显示「队列 1/20：歌名」

## 第四个坑，也是最隐蔽的一个

**缓存命中后，播放不动，进度停在 0，而且没有任何报错。**

文件是完好的：

```
$ file 2668397359-exhigh.audio
Audio file with ID3 version 2.4.0, contains:
MPEG ADTS, layer III, v1, 320 kbps, 48 kHz, Stereo
```

大小 10.8MB，ID3 头正常。

**原因：扩展名。** 原来叫 `.audio`，`AVPlayer` 靠扩展名判断格式，认不出就不播——**静默失败，`rate` 为 0，`error` 为 nil**。

改成 `.mp3`（用接口返回的 format 字段）后立刻正常，播放推进到 13 秒。

**教训**：`AVPlayer` 读本地文件时，扩展名不是装饰。任何「文件明明在但播不出来」的情况，先查扩展名。

## 现在的状态

| 能力 | 状态 |
|---|---|
| 扫码登录 + Keychain | ✓ |
| 搜索 | ✓ |
| 缓存（播过的不再下载） | ✓ |
| 队列（播完自动下一首） | ✓ |
| 歌词 + 罗马音随播放高亮 | ✓ |

**已经是一个能日常听的播放器了。**

---

# 追加：后台播放与锁屏控制

## 做到

- `UIBackgroundModes: audio`，切到后台音频继续
- 锁屏 / 控制中心显示曲名、歌手、专辑、时长、进度
- 远程命令：播放、暂停、上下一首、拖动进度
- 播放状态用 `timeControlStatus` 判断，不是 `rate`

## 两个坑

### 1. `rate` 在 `play()` 之后仍是 0

`p.play()` 返回后立刻读 `player.rate` 得到 0，因为 item 还在准备。

用 `rate` 判断「是否在播」，会在播放起始的几百毫秒里认为没播——锁屏就收不到「正在播放」，控件直接不出现。

**正确做法**：`player.timeControlStatus`

| 值 | 含义 |
|---|---|
| `.paused` | 真的暂停 |
| `.waitingToPlayAtSpecifiedRate` | 等着播（缓冲中） |
| `.playing` | 在播 |

后两种都算「在播」。

### 2. 只有 `MPNowPlayingInfoCenter` 不够，要 `MPNowPlayingSession`

只往 `MPNowPlayingInfoCenter.default().nowPlayingInfo` 写数据，`mediaremoted` 会**注册一瞬间然后立刻移除**：

```
Removing nowPlayingClient dev.yxxbc.probe (75130) ProbeApp
setting inferredNowPlayingClient from dev.yxxbc.probe to (null)
```

结果是锁屏和控制中心什么都不显示。

**正确做法**：用 `MPNowPlayingSession(players: [player])`，并 `becomeActiveIfPossible`：

```swift
let s = MPNowPlayingSession(players: [player])
s.automaticallyPublishesNowPlayingInfo = false
s.becomeActiveIfPossible()
```

之后系统日志才出现：

```
Set: dev.yxxbc.probe ... setting nowPlayingItem to 晴天 / PlaybackRate: 1.000000
```

## 怎么验证的

模拟器的主屏幕不显示播放控件，所以**看截图判断不了**。用系统日志：

```bash
xcrun simctl spawn "iPhone 18 Pro" log show --last 30s \
  --predicate 'process == "mediaremoted"' | grep -i probe
```

出现 `setting nowPlayingItem to <曲名>` 就是注册成功；出现 `Removing nowPlayingClient` 就是失败。

**这个方法比看界面可靠**，因为界面在模拟器上不完整，而 mediaremoted 是同一套逻辑。

---

# 追加：界面

## 做到

- 封面：搜索列表、播放条、播放页都有专辑图
- 背景：整个界面是封面色的深色模糊
- 歌词：当前行放大加粗，自动滚动跟随
- 播放页：大封面、曲名、可拖动进度条、播放控制、歌词
- 过滤制作信息（作词：xxx 这类）

## 三个坑

### 1. `scaledToFill` 的图会把整个视图撑宽

这是最隐蔽的一个。背景图用 `scaledToFill` 铺满时，它按自身比例放大到超出屏幕，**而 `ignoresSafeArea` 之后它仍参与父视图的尺寸计算**——整个 ZStack 被撑成图片的宽度，里面的文字跟着右移出屏。

表现是「歌词跑到了屏幕右边」，看起来像滚动问题，实际是背景图的锅。

**正确做法**：用 `GeometryReader` 拿到屏幕尺寸，给图固定的 `frame` 再加 `.clipped()`：

```swift
GeometryReader { geo in
    img.resizable().scaledToFill()
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped()
}
```

### 2. 竖着滚的 ScrollView 也会横向平移

`proxy.scrollTo(id, anchor: .center)` 的 anchor 同时作用于两个轴。内容比容器宽时，`anchor: .center` 会把内容横向居中，看起来就往右偏了。

**用 `UnitPoint(x: 0, y: 0.5)`** 把横向钉在左边。

### 3. 搜索接口不给封面地址

`search/get` 返回的 `al` 只有 `id` 和 `name`，**没有 `picUrl`**。

要再调一次 `/api/v3/song/detail`，整批一次请求（不是每条一次），返回里才有 `al.picUrl`。

**不要自己拼图片 URL**。我试过 `p1.music.126.net/album/{id}.jpg`，是错的；真实地址在 `p4.music.126.net/…/1099….jpg` 这种带哈希的路径上，只能由接口给。

### 顺带：制作信息要过滤

歌词里「作词：周杰伦」「编曲：周杰伦」是带时间的行，和正文混在一起。框架里的 `AllIsCredit` 就是干这个的，一条一条问它。

## 现在

**一个能日常用的 iOS 播放器**：登录、搜索、播放、缓存、队列、后台、锁屏、歌词。

界面还是简洁风格，但已经不是「能用但难看」的程度了。

---

# 追加：按桌面版的布局重做首页

## 现在的界面

| 区域 | 内容 |
|---|---|
| 顶栏 | 「春日影」+ 搜索 + 登录/二维码 |
| 首页 | 每日推荐，行内是封面、歌名、艺人、更多 |
| 播放条 | 封面、曲名、艺人、上一首/播放/下一首，顶部一条进度 |
| 播放页 | 大封面、曲名、可拖进度、控制、歌词 |

和桌面版一致的地方：封面在左、信息在右的行式布局，深色背景，粉色作强调色。

## 新加的接口

`DailyJSON(limit)` —— 每日推荐。未登录时返回空字符串而不是错误，因为「没登录」不是失败，界面显示提示就行。

## 离线播放

现在播过一遍的歌，**断网也能播**：

1. `SongCache.any(id:)` 先查有没有存过的文件，有就直接播，不问网络
2. 歌词也跟着存（`id.lrc`），断网时读本地

## 一个自己挖的坑

`any(id:)` 用文件名前缀匹配，而歌词文件叫 `2668397359.lrc`——**没有连字符**，所以不会被误认成音频。但反过来，如果哪天改成 `2668397359-audio.lrc` 就会。加了 `pathExtension != "lrc"` 的排除，明确一点。

## 还差的

- 歌单页（需要登录后的接口）
- 搜索历史
- 界面细节：歌词页的旋转封面、播放页手势

---

# 追加：歌单

## 接口

| 函数 | 说明 |
|---|---|
| `AllPlaylists()` | 用户的歌单，`id\t名\t曲数\t封面` |
| `AllPlaylistSongs(id)` | 歌单里的歌，与搜索同格式 |

**歌单先问「我是谁」**：`/api/nuser/account/get` 拿到 userId，再用它调 `user/playlist`。未登录时返回空字符串，不是错误。

**超过 500 首要分页**：`playlist/detail` 只带前面一部分，剩下的用 `playlist/track/all` 一页 500 条补齐。没有这个，长歌单会只显示一半。

## 界面

- 首页每日推荐下面，歌单是双列封面卡
- 点开是歌单详情：封面、名称、曲数，然后是带序号的歌曲列表
- 未登录时显示「登录后显示你的歌单」，而不是留白

## 未登录时的行为

`Playlists()` 返回空字符串，`LoggedIn()` 也返回空。**这是有意的**：没登录不是失败，界面给提示就行，不该弹错误。

验证过：

```
$ go run ./cmd/probe
logged in: ""
playlists: (empty — 未登录)
```

---

# 追加：收藏与歌词偏移

## 收藏

| 函数 | 说明 |
|---|---|
| `AllLike(id, like)` | 收藏 / 取消，成功返回空串 |
| `AllLikedIDs()` | 已收藏的 id，一行一个 |

**歌单列表和收藏都以账号为准**，所以两个都要先问「我是谁」。抽出了 `userID()` 共用，避免两处各写一份。

**收藏失败要如实反映**：`AllLike` 返回错误时不改本地状态，界面提示「收藏失败」，不假装成功。

界面上有两个入口：列表每行右侧的心，播放页控制栏左侧的心。

## 歌词偏移

桌面版有这个，iOS 一开始漏了。

歌词和音乐错几百毫秒是常事，尤其是网易的 LRC 时间轴。做法和桌面版一致：

- 按曲目记，存在 `id.offset` 文件里（iOS 没有 Go 侧能访问的偏好文件）
- 范围 ±5 秒，正负各两档（0.1 / 0.5）
- 偏移只动歌词，不动播放位置

## 一个顺序上的教训

我先写了 `LikedIDs()` 用空 uid 调接口，看起来合理。**但真实实现是必须传 userId 的**——去读 `internal/netease/auth.go` 才发现。如果没查就接上去，登录后收藏列表会一直是空的，而代码看不出问题。

**照抄真实实现，别凭直觉写接口。** 这已经是第三次踩到了（前两次是 eapi 的 MD5 格式和歌词接口）。

---

# 追加：搜索历史与播放记录

## 存在哪

`UserDefaults`，不是 Keychain。

**理由**：这些不是秘密。Keychain 只放会话，混进别的东西会让它变慢，也会让「清空会话」变得不干净。

## 做了什么

- 搜索历史：最多 30 条，重复的不留两条，可单条删除或清空
- 播放记录：最多 30 条，最近在前，首页显示前 6 条
- 搜索历史的界面是标签流，点一下重新搜

## 验证方法

没有靠截图，直接读模拟器里的 plist：

```bash
plutil -p <容器>/Library/Preferences/dev.yxxbc.probe.plist
```

结果：

```
{
  "playedSongs" => {length = 968, bytes = ...},
  "searchHistory" => [ 0 => "周杰伦" ]
}
```

`playedSongs` 从 598 字节涨到 968，说明新播的歌确实被记了进去。

**这比看界面可靠**：界面可能因为「还没播」而不显示，但数据在不在是确定的。

## 一个细节

`Song` 加了 `Codable`。它是 `Hashable` 的纯值类型，编码成 JSON 存起来没有副作用。

## 界面位置

最近播放放在首页、每日推荐之后、我的歌单之前——顺序按「现在想听什么」排的。

---

# 追加：布局可调整性

## 为什么要做

「说不定要换布局」不是假设：手机横屏、iPad、把歌词放到封面旁边——每次换都会撞上散落各处的固定数字。

## 做法

新增 `Design.swift`，所有**决定大小和间距的数字**集中在这里：

```swift
enum Design {
    static let pageMargin: CGFloat = 20
    static let rowCover: CGFloat = 52
    static let heroCoverRatio: CGFloat = 0.78   // 按屏宽取比例，不写死
    static let sectionTitle = Font.system(size: 17, weight: .bold)
    ...
}
```

界面文件里不再出现「20」「52」这类数字，只有 `Design.pageMargin`、`Design.rowCover`。

## 一个关键点：用比例，不用固定尺寸

封面这类大元素用**屏宽的比例**：

```swift
side: g.size.width * Design.heroCoverRatio
```

而不是 `side: 300`。小屏不溢出，大屏不显小，横竖屏都不会突然放不下。

## 验证

改完后截图与改之前**逐像素一致**——说明令牌化没有动外观，只是把数字搬了家。这是重构该有的样子：行为不变，结构变好。

## 顺带修掉的架构隐患

`internal/lyrics` 移到了 `pkg/lyrics`。

**原因**：Go 规定 `internal/` 下的包只能被同一模块引用，而 iOS 工程在另一个 module。之前是**复制一份**到探针工程里——主仓库改了它不会跟着变，两份迟早分叉。

移出来后 iOS 工程可以直接 `require` 主仓库，不用复制。16 处 import 更新，主项目测试全过。

---

# 追加：横屏布局

## 两种布局

| 方向 | 布局 |
|---|---|
| 竖屏 | 封面在上，标题、进度、控制，歌词在下 |
| 横屏 | 左边封面与全部控制，右边歌词 |

**横屏必须分栏**：竖向堆叠在横向的屏幕上会把歌词挤成两行，等于没有歌词。

判断写在 `Design.isWide(size)`：

```swift
static func isWide(_ size: CGSize) -> Bool { size.width > size.height * 1.05 }
```

**用传入的尺寸，不用设备方向**：iPad 分屏时窗口可能不比高度宽，那时堆叠才对。

## 验证方式

模拟器在这个环境里起不了界面，`simctl` 也没有旋转命令。所以改用测试：

- `testIsWide`：竖屏、横屏、iPad 两种、近正方形的分屏窗口，六种尺寸判断都对
- `testTokensAreSane`：所有尺寸令牌大于 0，封面比例在 0.4–1 之间
- `testBothOrientationsRender`：两个方向各渲染一次，确认都能出图

**为什么值得写测试**：`isWide` 判断错了，横屏会静默退回堆叠布局——**页面照样渲染，只是很难看**。截一张竖屏的图看不出来，截横屏的图也看不出「本该分栏」。

## 现在的测试

```
Test Case 'DesignTests.testIsWide' passed
Test Case 'DesignTests.testTokensAreSane' passed
Test Case 'LayoutRenderTests.testBothOrientationsRender' passed
```

---

# 追加：背景取色

## 问题

播放页背景是**灰褐色**，不是封面的颜色。封面明明是白色配金色，背景却是浑浊的深灰。

## 原因链

1. 原来用「封面模糊后压暗」做背景
2. 白色封面的模糊结果接近白，压暗后是灰
3. 灰再加一点封面的暖色，就成了灰褐

**模糊等于平均，而平均会让浅色封面变脏。**

## 做法

照抄桌面版的 `dominantColor`：

- 缩小到 24×24
- 按色相分 18 个桶
- 每像素权重 = **饱和度² × 明度**
- 饱和度 < 0.15 或明度 < 0.15 的直接跳过
- 取权重最大的桶，用它的平均色

**权重是饱和度平方**，这就是为什么白底金边会取到金——白色饱和度为 0，完全不参与投票；金色哪怕只有一小块，也独占全部权重。

## 调试中发现的真问题

第一版照抄时保留了原实现里的 `weight[best] < 2` 判断，结果**背景还是灰的**。

那个判断的本意是「图里根本没有颜色就退回平均色」，但它用**权重总和**做阈值。白色封面的金色线条很少，总权重不到 2，于是被判成「没有颜色」，退回平均色——正是要避免的米色。

**改成 `weight[best] > 0`**：只要有一个像素有颜色，就用它。面积小不等于没有。

## 测试

```
ArtworkColorTests.testPlainColour               纯色取其色
ArtworkColorTests.testWhiteWithAGoldBand        白底金边取金，不取米色
ArtworkColorTests.testMostlyWhiteWithLittleGold 十分之一是金，仍然取金
ArtworkColorTests.testGraySleeve                全灰取平均，不编造色相
```

第三条是专门为这个 bug 写的：**面积小不等于没有**。

## 亮度也调过

只改取色还不够。压到 `brightness 0.42` 时，金色看起来仍近黑。提到 0.52，并把饱和度下限从 0.4 提到 0.45，色调才看得出来。

**背景要深到白字能读，但不能深到看不出颜色**，这个平衡是调出来的，不是算出来的。

---

# 追加：修掉一个会烧电的死循环

## 问题

一首歌放不了时，代码调 `next()` 跳过它。而 `next()` 到队尾会绕回开头。

**断网且没有缓存时，整队列都放不了**——于是：失败 → next → 失败 → next → 绕回开头 → 永远循环。

后果是每秒几十次网络请求：**转圈、耗电、触发限流**，用户只看到界面卡住。

## 修法

抽出一个纯值 `QueueWalk`：

```swift
struct QueueWalk { var skipped: Int; var count: Int }

enum QueueStep { case advance(Int), stop }

func walkFail(_ w: QueueWalk) -> QueueStep {
    let next = w.skipped + 1
    if next >= max(1, w.count) { return .stop }
    return .advance(next)
}
```

失败累加，够了一轮就停，并提示「队列里的歌都放不了」。用户点上一首或选歌时，计数归零，可以重试。

## 为什么把这个逻辑单独抽出来

**死循环不能靠测试跑出来验证**——测试会一直跑到超时。

所以要把「走几步停」做成一个纯函数，测它：

```
testWalkSteps        三首歌：走两步、第三步停
testWalkEnds         跑循环，断言 100 步内停下
testSingleSong       一首歌失败一次就停，不绕回自己
testEmptyQueue       空队列立刻停，不做除法
```

最后一条是边界：`next >= count` 在 `count == 0` 时恒真，但要确认不会出现除零或负索引。

## 一个我先犯的错

第一版测试写的是：

```swift
func testFailedWalkEnds() {
    let m = model(3)
    XCTAssertEqual(m.queue.count, 3)   // ← 断言和标题无关
}
```

**标题说「walk ends」，测的是「队列有 3 首」。** 这种测试永远通过，也永远没用。

抽成纯函数后才写得出真正的测试。

---

# 追加：让它能装到手机上

## 之前的配置只能跑模拟器

`CODE_SIGN_IDENTITY: "-"` 是 ad-hoc 签名。模拟器接受，**真机不接受**：

```
error: "ProbeApp" requires a provisioning profile.
       Enable development signing and select a provisioning profile.
```

## 改成自动签名

```yaml
CODE_SIGN_STYLE: Automatic
DEVELOPMENT_TEAM: ""
```

模拟器照样能构建，真机则提示「Select a development team」——这正是需要做的唯一一步操作。

## 两份说明

**`RUN-ON-DEVICE.md`**：从连手机到信任开发者证书的完整步骤，含免费账号的限制（7 天过期、最多 3 个应用）。

**`check-env.sh`**：检查 Xcode、模拟器、真机连接、签名证书、框架是否就绪。

在本机跑出来：

```
Xcode                  ✓ 27.2
模拟器                 ✓ 7 台 iPhone 可用
真机                   未连接（插上数据线并点信任）
签名证书               ✓ 1 个可用
框架                   ✓ All.xcframework 已构建
```

**本机已经有 1 个开发证书**，所以签名这步是通的。

**`build-framework.sh`**：重建 Go 框架。脚本里写明了为什么只能有一个框架——两套 Go 运行时会互相踩符号，表现为启动即段错误。

## 一个提醒

免费 Apple ID 签的应用 **7 天过期**。这不是 bug，是苹果的限制。如果这个探针要长期用，要么每星期重新装一次，要么买开发者账号。

---

# 追加：字段转义

## 问题

所有数据以制表符分隔过桥：`id \t 歌名 \t 歌手 \t 专辑 \t 封面`。

**歌名里如果含制表符，整行就多一列**，后面所有字段错位——歌手显示在专辑位置，专辑显示在封面位置。

实测确认过：

```
name has tab: true
fields after split: 6      ← 本来应该是 5
```

网易允许标题含各种字符，这不算罕见的边角。

## 修法

Go 侧对每个字段转义（`\` `\t` `\n` `\r`），Swift 侧解回。

关键点是**转义符自己也要转义**：`\\` 表示一个反斜杠，`\t` 表示制表符。不这么做的话，「字段里有 `\t` 这两个字符」和「字段里有制表符」会分不清。

## 测试

```
testFullRow          普通五字段
testMissingFields    缺封面、只有歌名
testTabInTheTitle    歌名含制表符：断言歌手没跑到专辑去
testNewlineInTheTitle 换行不会变成两首歌
testBackslash        反斜杠、结尾的孤立反斜杠
testErrorIsEmpty     ERR: 开头不是一首歌
testBlankLines       空行丢弃
testNoID             没 id 的不算歌
```

`testTabInTheTitle` 是核心：它断言的是**字段位置**，不是「没崩溃」。

## 顺带

原来的 `testTabInTheTitle` 是这样：

```swift
XCTAssertFalse(songs[0].name.isEmpty)   // 只验证「有名字」
```

那条在错位时也会通过。**改成验证 artist == "人" 之后，它才开始有意义。**
