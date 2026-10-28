# UI 改造记录

阶段一在本目录建立之前已经提交，提交号 `8c04b28`：建立 FilmTone 主题，并更新公共按钮、滑杆、卡片和图标颜色。本文件从阶段二开始记录，不补写阶段一的详细报告。

## 阶段二：首页 UI

- 日期：2026-10-28
- 主要修改文件：`photos/AIPhotoStudio/Features/Home/HomeView.swift`，以及 `en`、`zh-Hans`、`zh-Hant` 的 `Localizable.strings`
- 核心变更：首页改为深色背景和 FilmTone 字体层级。测试图编辑器、系统选图和相册入口保留为可点卡片。最近编辑使用 `allProjects()` 的真实项目。未加底部个人中心，未加精选预设。
- 构建和测试：`AIPhotoStudio` Debug，iPhone 17 模拟器，部署目标 iOS 16.0。`xcodebuild test` 成功，99 个测试、0 失败。没有打开 App 看首页。
- 当前已知问题：导航栏隐藏后的返回路径未在模拟器确认。窄屏双列卡片未实测。没有和 Figma 做截图对比。
- 详细报告：`docs/ui-refactor/stage-02-home-report.md`
