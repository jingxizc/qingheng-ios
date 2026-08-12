# 轻衡 · QingHeng

一款现代、本地优先的 iOS 体重与饮食记录 App：自动同步兼容的蓝牙体重秤，用照片记录每一餐，并可选使用 Qwen3.7 Flash 生成饮食分析、热量区间和行为教练建议。

A modern, local-first iOS weight and meal tracker. It syncs compatible Bluetooth scales, keeps a photo-based food diary, and can optionally use Qwen3.7 Flash for meal analysis, calorie ranges, and behavior-focused coaching.

[中文](#中文) · [English](#english)

许可证 / License：[MIT](LICENSE)

---

## 中文

### 主要功能

- SwiftData 本地保存体重、饮食记录和照片
- 自动发现并连接兼容的 BLE 体重秤
- 5 分钟称重会话合并，以中位数过滤波动和异常跳值
- 必须手动绑定体重秤，并结合近期个人基线拒绝其他人的异常读数
- 按日期组织的照片饮食日记，支持份量选择和手动纠正
- Qwen3.7 Flash 识别食物、餐盘结构、热量区间及不确定项
- 人工修正食物和份量后，可锁定确认内容并让 Qwen 重新估算热量
- Apple Vision 本机饮食分析作为无网络降级方案
- 昨日复盘 AI 教练与 7 日周报，每次聚焦一个可执行行动
- 可选读取 Apple 健康中的步数、活动能量、锻炼时长和睡眠，生成次日晨间复盘
- Apple Foundation Models 可用时提供端侧教练表达，本地规则始终兜底
- 可选的次日晨报提醒；iOS 会尽力在后台用最新健康摘要更新内容
- 7 / 30 / 90 天体重趋势
- 写入 Apple 健康，支持历史补同步和同步标识去重

### 系统要求

- macOS 与 Xcode 15 或更高版本
- iOS 17 或更高版本
- 蓝牙和相机功能需要真机
- Apple Foundation Models 需要 iOS 26、支持 Apple Intelligence 的设备与已下载的系统模型
- Qwen 云端分析需要千问 AI 平台按量付费 API Key

### 本地构建

1. 克隆仓库并进入目录：

   ```bash
   git clone <repository-url>
   cd qingheng-ios
   ```

2. 创建只在本机使用的签名配置：

   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

3. 编辑 `Config/Local.xcconfig`：

   ```text
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = com.example.qingheng
   TEST_PRODUCT_BUNDLE_IDENTIFIER = com.example.qingheng.tests
   ```

   `Local.xcconfig` 已被 Git 忽略，不会上传开发者 Team ID 或个人 Bundle ID。

4. 用 Xcode 打开 `Diet.xcodeproj`，选择自己的 Team 和真机，然后运行。

5. 首次启动时按需允许蓝牙、相机、通知和 Apple 健康写入权限。

### 安全生成 Qwen 配置二维码

不要把 API Key 写进源码、README、`.env`、终端命令参数或在线二维码网站。

1. 在千问 AI 平台的 **API Keys → 按量付费** 页面创建或复制完整的 `sk-...` API Key。页面中的数字 ID 只是记录编号，不是 Workspace ID。

2. 北京按量付费接口使用：

   ```text
   https://dashscope.aliyuncs.com/compatible-mode/v1
   ```

   此模式不需要 Workspace ID。

3. 在项目目录运行本地脚本：

   ```bash
   ./Scripts/make-qwen-qr
   ```

4. 在终端输入完整 API Key。输入过程不会回显，也不会进入 shell 历史。脚本使用 macOS Core Image 在内存窗口中生成二维码，不写入磁盘，也不调用任何二维码网站。

5. 在 App 中进入 **我的 → 云端 AI**，扫描二维码。App 会先发送一个不含体重和照片的最小测试请求；验证成功后，配置才会保存到仅限本设备、仅解锁时可访问的 iOS Keychain。

6. 扫描完成后关闭二维码窗口。二维码本身等同于密钥，请勿截图或分享。

### 数据与隐私

| 数据 | 默认位置 | 是否离开设备 |
| --- | --- | --- |
| 体重、饮食记录、照片 | 本机 SwiftData | 默认不会 |
| 蓝牙体重秤广播 | 本机处理 | 不会 |
| Qwen API Key | iOS Keychain，`WhenUnlockedThisDeviceOnly` | 仅作为请求鉴权发送给千问 |
| 饮食照片 | 本机；连接 Qwen 后按需上传 | 仅在主动分析时上传至千问 |
| 教练上下文 | 本机生成的最小摘要 | 连接 Qwen 后会发送体重、目标、饮食以及用户授权的运动与睡眠文字摘要 |
| Apple 健康体重 | Apple HealthKit | 仅在用户授权后写入 Apple 健康 |

项目没有自建服务器、用户账号、广告 SDK 或分析 SDK。Qwen 不可用时，饮食分析自动回退 Apple Vision，教练自动回退 Apple Foundation Models 或本地规则。

### 蓝牙体重秤说明

当前覆盖标准 BLE Weight Scale（`181D / 2A9D`）以及常见小米 `MI SCALE`、`MI SCALE2`、`MIBCS`、`MIBFS` 广播数据。不同代际的加密米家设备可能需要额外鉴权或设备 Token；此时仍可使用手动称重。

### 测试

```bash
xcodebuild test \
  -project Diet.xcodeproj \
  -scheme Diet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

模拟器可以运行数据解析与业务逻辑测试，但无法验证真实蓝牙秤、相机和 Apple 健康授权。

### 重要说明

- 照片热量是图像与份量推断出的区间估算；隐藏的油、糖、酱料和容器深度都会造成误差。
- AI 建议用于行为反馈，不替代医生、注册营养师或其他专业医疗建议。
- 云端请求会产生千问按量付费费用，请在平台的用量分析中设置预算与告警。
- 本项目采用 [MIT License](LICENSE)；使用、修改或分发时请保留版权与许可证声明。

---

## English

### Features

- Local persistence for weight records, meals, and photos with SwiftData
- Automatic discovery and connection for compatible BLE scales
- Five-minute weigh-in session merging with median-based noise and outlier rejection
- Explicit scale binding plus personal-baseline checks to reject another person's readings
- A date-based photo food diary with portion selection and manual corrections
- Qwen3.7 Flash food recognition, plate composition, calorie ranges, and uncertainty notes
- Qwen calorie re-estimation after manual food and portion corrections, without overriding confirmed facts
- On-device Apple Vision meal analysis as the offline fallback
- A previous-day AI coach and seven-day review focused on one actionable next step
- Optional Apple Health steps, active energy, exercise time, and sleep summaries for the next morning's review
- Apple Foundation Models copy generation when available, with deterministic local rules as fallback
- Optional next-morning coaching notifications, refreshed with the latest health summary when iOS background delivery runs
- 7 / 30 / 90-day weight trends
- Apple Health weight export, historical backfill, and sync identifier deduplication

### Requirements

- macOS with Xcode 15 or later
- iOS 17 or later
- A physical iPhone for Bluetooth and camera features
- iOS 26, a supported Apple Intelligence device, and downloaded system models for Apple Foundation Models
- A pay-as-you-go API key from the Qwen AI platform for cloud analysis

### Local setup

1. Clone and enter the repository:

   ```bash
   git clone <repository-url>
   cd qingheng-ios
   ```

2. Create a machine-local signing configuration:

   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

3. Edit `Config/Local.xcconfig`:

   ```text
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = com.example.qingheng
   TEST_PRODUCT_BUNDLE_IDENTIFIER = com.example.qingheng.tests
   ```

   `Local.xcconfig` is ignored by Git, so your Apple Team ID and personal bundle identifier are not committed.

4. Open `Diet.xcodeproj` in Xcode, select your team and a physical iPhone, then run the app.

5. Grant Bluetooth, camera, notification, and Apple Health write access as needed.

### Generate the Qwen QR configuration safely

Never place an API key in source code, documentation, `.env` files, shell command arguments, or an online QR generator.

1. Open **API Keys → Pay-as-you-go** in the Qwen AI platform and create or copy the full `sk-...` key. The numeric row ID is not a Workspace ID.

2. The Beijing pay-as-you-go endpoint is:

   ```text
   https://dashscope.aliyuncs.com/compatible-mode/v1
   ```

   This endpoint does not require a Workspace ID.

3. Run the local helper from the repository root:

   ```bash
   ./Scripts/make-qwen-qr
   ```

4. Enter the full API key. Input is hidden and is not added to shell history. The script uses macOS Core Image to render the QR code in an in-memory window. It writes no QR image to disk and never calls a QR website.

5. In the app, open **Settings → Cloud AI** and scan the QR code. The app first sends a minimal connection test containing no weight or photo data. It saves the configuration only after validation, using an iOS Keychain item restricted to the unlocked device.

6. Close the QR window after scanning. Treat the QR code as a credential: do not screenshot or share it.

### Data and privacy

| Data | Default storage | Leaves the device? |
| --- | --- | --- |
| Weight, meal records, and photos | Local SwiftData store | No, by default |
| Bluetooth scale advertisements | Processed locally | No |
| Qwen API key | iOS Keychain, `WhenUnlockedThisDeviceOnly` | Used only to authenticate Qwen requests |
| Meal photos | Local; uploaded on demand when Qwen is connected | Only during an explicit analysis |
| Coaching context | Minimal summary created on device | Weight, target, meal, and user-authorized activity/sleep text summaries are sent when Qwen is connected |
| Apple Health weight samples | Apple HealthKit | Written only after user authorization |

The project has no custom backend, user accounts, advertising SDKs, or analytics SDKs. When Qwen is unavailable, meal analysis falls back to Apple Vision and coaching falls back to Apple Foundation Models or deterministic local rules.

### Bluetooth scale compatibility

The parser supports the standard BLE Weight Scale service (`181D / 2A9D`) and common broadcasts from Xiaomi `MI SCALE`, `MI SCALE2`, `MIBCS`, and `MIBFS` devices. Newer encrypted Mi Home devices may require additional authentication or a device token; manual weight entry remains available.

### Tests

```bash
xcodebuild test \
  -project Diet.xcodeproj \
  -scheme Diet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

The simulator covers parsers and business logic, but it cannot validate a physical Bluetooth scale, the camera, or Apple Health authorization.

### Important notes

- Photo-based calories are interval estimates. Hidden oil, sugar, sauces, and container depth can materially change the result.
- AI coaching is for behavioral feedback and is not medical or nutritional advice.
- Cloud calls incur Qwen pay-as-you-go charges. Configure usage budgets and alerts in the platform console.
- This project is available under the [MIT License](LICENSE). Keep the copyright and license notices when using, modifying, or distributing it.
