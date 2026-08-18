# 轻衡 TestFlight 发布资料

## 基本信息

- App 名称：轻衡
- 平台：iOS
- 主要语言：简体中文
- 版本：1.0.0
- SKU 建议：`qingheng-ios-001`
- Bundle ID：使用本机 `Config/Local.xcconfig` 中的 `PRODUCT_BUNDLE_IDENTIFIER`
- 隐私政策 URL：启用 GitHub Pages 后使用 `https://jingxizc.github.io/qingheng-ios/privacy.html`

## Beta App Description

轻衡是一款本地优先的体重与饮食记录 App。它可连接兼容的蓝牙体重秤，自动合并稳定称重结果；通过照片记录饮食，并可选使用 Qwen 估算餐食热量、修正识别结果和生成结合体重、饮食、运动与睡眠的晨间建议。大部分数据默认保存在设备本机。

## What to Test

请重点体验：

1. 手动新增体重，以及连接兼容蓝牙体重秤后的自动同步与多次读数合并。
2. 拍摄或选择饮食照片、选择份量、修改识别到的食物并重新估算热量。
3. 授权 Apple 健康后同步体重，并可选读取前一天的运动与睡眠摘要。
4. 首页“昨日复盘 · AI 教练”和晨间提醒是否给出具体、温和、可执行的建议。
5. 设置页中的权限说明、Qwen 连接管理与本地降级行为。

反馈时请注明设备型号、iOS 版本、操作步骤和是否启用了 Qwen。请勿在反馈截图或文字中包含 API Key、配置二维码或敏感健康记录。

## Beta App Review Information

- 登录要求：无用户账号，无需登录。
- Qwen：可选；未配置时应用会使用 Apple Vision、端侧模型或本地规则，不影响主要流程测试。
- 蓝牙秤：审核人员可使用“手动记录体重”完整体验体重趋势；蓝牙功能需要兼容的 BLE 体重秤。
- HealthKit：所有读取和写入均由用户在系统授权界面逐项允许；拒绝权限后应用仍可使用。
- 医疗说明：热量为区间估算，教练建议不构成医疗诊断或专业营养建议。
- 联系邮箱：`<在 App Store Connect 中填写 Apple Developer 联系邮箱>`

## External Test Group

- Group name：轻衡体验用户
- 建议首批人数：10–20 人
- Public link tester limit：100
- 自动通知测试员：开启
