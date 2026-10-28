# 阶段二报告：首页 UI

## A. 阶段信息

- 阶段名称：首页 UI 改造。
- 完成状态：部分完成。
- 实际执行日期：2026-10-28。
- 本阶段目标：把 `HomeView` 改成 FilmTone 深色首页，保留已有入口和真实项目数据。不改编辑器、配方、导出和相册逻辑。
- 使用的设计参考：Figma 文件 `FilmTone【APP】`（`1ixm6AJ2cbIwrgNAi0qfJm`）画板 `01 首页`（`35:3`）；审查记录 `docs/filmtone-ui-audit.md`。
- 阶段一状态：已验证文件和提交存在。提交 `8c04b28` 新增 `FilmToneTheme.swift`，并让 `Components.swift` 使用该主题。本阶段没有重新做阶段一的模拟器外观验收。

代码已经写完并通过单元测试。首页没有在模拟器里打开，也没有和 Figma 截图并排对比。因此不能写成视觉验收已完成。

## B. 修改前检查

Git 工作区在开始时没有已跟踪文件的未提交修改。`main` 与阶段一提交 `8c04b28` 一致。未跟踪文件有：

- `.cursor/`
- `docs/filmtone-ui-audit.md`
- `photos/AIPhotoStudio.xcodeproj/project.xcworkspace/`

这些文件本阶段没有覆盖或删除。

阶段一文件存在：`photos/AIPhotoStudio/UIComponents/FilmToneTheme.swift`、`photos/AIPhotoStudio/UIComponents/Components.swift`。

修改前的首页在 `HomeView` 的 `NavigationStack` 里。背景是靛蓝到紫色的渐变。入口是：

- `NavigationLink` 打开无项目的 `EditorView()`，使用测试图。
- `SystemPhotoPicker` 导入照片，成功后打开编辑器 sheet。
- `NavigationLink` 进入 `PhotoManagementView`。
- `PhotoProjectRepository.allProjects()` 列出项目。仓库本身已按 `updatedAt` 降序返回。
- 点击项目调用既有 `open(_:)`。
- 长按菜单：版本、重命名、收藏、删除。
- 版本恢复在同文件的 `VersionHistoryView` sheet 中。

检查过的文件：

- `docs/filmtone-ui-audit.md`
- `photos/AIPhotoStudio/Features/Home/HomeView.swift`
- `photos/AIPhotoStudio/UIComponents/FilmToneTheme.swift`
- `photos/AIPhotoStudio/UIComponents/Components.swift`
- `photos/AIPhotoStudio/Core/Persistence/PhotoProjectRepository.swift` 的 `allProjects()`，只读，未改。
- `en`、`zh-Hans`、`zh-Hant` 的 `Localizable.strings`
- Figma 节点 `35:3`

预期修改范围就是上述首页和三份文案。实际修改与此一致。`docs/ui-refactor/` 是本阶段新增的报告，不是 App 代码。

## C. 文件变更清单

| 文件路径 | 操作类型 | 修改原因 | 具体变化 | 功能影响 | 风险 |
|---|---|---|---|---|---|
| `photos/AIPhotoStudio/Features/Home/HomeView.swift` | 修改 | 首页需要深色布局，并继续使用现有入口和项目数据 | 去掉渐变和靛蓝按钮。标题、两个创作卡、相册行、状态文字、最近编辑网格和空状态改为 FilmTone 颜色。项目格使用真实标题、缩略图、更新时间和收藏星。隐藏首页导航栏。`ProjectThumbnail` 从 54×54 改为宽撑满、高 108、圆角 12。导入、打开、重命名、收藏、删除、版本 sheet 的调用没有改 | 只影响首页外观和首页上的项目格尺寸。版本历史 sheet 的列表代码未改 | 双列卡片在窄宽度上可能显得挤。隐藏导航栏如果传递到下一级，编辑器或相册的返回会受影响。这次没有在模拟器里看 |
| `photos/AIPhotoStudio/en.lproj/Localizable.strings` | 修改 | 首页新文案需要英文键 | 增加 FilmTone、副标题、开始创作、最近编辑、空状态、导入说明、相册说明、无障碍尺寸格式 | 只影响这些新键的英文显示 | 无 |
| `photos/AIPhotoStudio/zh-Hans.lproj/Localizable.strings` | 修改 | 简体中文首页文案 | 同上 8 个键的简体翻译 | 简体界面的首页文案 | 无障碍格式使用 `%1$@`、`%2$lld`、`%3$lld`，未在运行中听 VoiceOver |
| `photos/AIPhotoStudio/zh-Hant.lproj/Localizable.strings` | 修改 | 繁体中文首页文案 | 同上 8 个键的繁体翻译 | 繁体界面的首页文案 | 同上 |
| `docs/ui-refactor/stage-02-home-report.md` | 新增 | 本阶段要求落盘报告 | 本文件 | 不影响 App | 无 |
| `docs/ui-refactor/CHANGELOG.md` | 新增 | 本阶段要求有阶段记录 | 从阶段二开始记。阶段一只有提交指针 | 不影响 App | 无 |
| `docs/ui-refactor/REGRESSION-CHECKLIST.md` | 新增 | 本阶段要求有回归清单 | 只把实际做过的检查标为通过 | 不影响 App | 无 |

`Components.swift`、`FilmToneTheme.swift`、工程配置、成像、持久化、Domain、编辑器和测试都没有改。

## D. UI 变化说明

修改前：浅色渐变背景，一张靛蓝主卡片，两个系统描边按钮，项目是横向信息行。主次层级靠系统字号，强调色是 indigo。

修改后：

- 页面背景使用 `FilmToneTheme.background`（`#121212`），铺到安全区外。内容仍在安全区内，没有画假状态栏。
- 标题 `FilmTone` 使用 `largeTitle`（28pt Semibold，`#F5F5F7`）。副标题使用 `body`（14pt Regular，`#8E8E93`）。区块标题使用 `sectionTitle`（16pt Semibold）。
- 左右边距 16。区块之间 28，区块内部 12。创作卡间距 10。最近编辑列间距 8、行间距 16。
- 创作区是两张 `AppCard`（`#1C1C1E`，圆角 16）加下面一条相册卡。图标沿用 `AppIcon` 的金色。卡片文字是 14pt Semibold 和 12pt Regular。
- 最近编辑用三列网格。缩略图高 108、圆角 12，空图底色是 `#2A2A2C`。标题最多两行，日期一行。收藏星使用 `#E2B56A`。
- 没有项目时，最近编辑区显示深色空状态，不写死数量，也不放假图。
- 长标题用 `lineLimit` 和换行，没有缩小全局字体。

与 Figma `01 首页` 的符合程度：背景、标题层级、左右边距、深色圆角卡和最近编辑的三列结构按画板做了。没有把画板截图当背景。

因现有功能或授权没有实现：

- 创作卡上的街道、森林照片没有打包。卡片用 SF Symbol 和深色底。
- 没有做「精选预设」和「查看全部 →」。预设名和日期是稿面占位，首页没有这份数据；「查看全部」没有独立页面，最近编辑已经列出 `allProjects()` 的全部结果。
- 没有做底部「首页 / 我的」。工程仍是根上的 `NavigationStack`，没有个人中心页面。不加无动作按钮，也不改成 `TabView`。
- 创作卡文案保持真实动作：打开测试图编辑器、系统选图、进入相册。没有写成「一键套用预设」或「一键复刻色彩」，因为那会指向尚未在首页存在的流程。
- 项目格没有再显示像素尺寸、格式和版本号，避免三列里溢出。尺寸仍在无障碍标签里。版本、重命名、收藏、删除仍在长按菜单。

仍然存在的视觉差异：稿面创作卡有照片和固定高度，实现是图标卡，高度随文案增长。稿面有底栏，实现没有。稿面最近编辑只有三张预览，实现是全部项目。卡片主色只用了主题里的 `#1C1C1E`，没有混用 `#1A1A1C` 和 `#1A1C1C`。

未提供截图。没有进行实际截图对比。

## E. 功能行为核对

| 功能 | 状态 | 依据 |
|---|---|---|
| 系统照片导入 | 仅完成代码检查 | `openPicker()`、`SystemPhotoPicker` 和 `importPhotos` 仍在，按钮仍调用 `openPicker`。未在模拟器里选图 |
| 测试图片入口 | 仅完成代码检查 | 左侧卡片仍是 `NavigationLink { EditorView() }`。未打开编辑器 |
| 照片管理入口 | 仅完成代码检查 | 仍 `NavigationLink` 到 `PhotoManagementView`，`onDisappear` 仍重新加载项目。未进入相册页 |
| 最近编辑列表 | 仅完成代码检查 | 仍 `repository.allProjects()`，空列表有空状态。未用真实项目数据看网格 |
| 打开项目 | 仅完成代码检查 | 项目格仍 `await open(project)`，编辑器 sheet 未改。未点击项目 |
| 重命名、收藏、删除 | 仅完成代码检查 | 长按菜单仍调用原来的 `rename`、`toggleFavorite`、`delete`。未操作 |
| 历史版本恢复 | 仅完成代码检查 | `versionProject` sheet 和 `VersionHistoryView` 代码未改。未打开 sheet |
| 导航返回与页面切换 | 未验证 | 首页隐藏了自己的导航栏。下一级是否仍能返回，没有运行确认 |
| 底部首页 / 我的 | 不适用 | 本阶段按约束不新增 |

## F. 测试和构建结果

1. Xcode 构建通过。测试动作在编译 App 后运行测试，进程退出码 0。
2. Scheme：`AIPhotoStudio`。配置：测试动作为 Debug。Destination：`platform=iOS Simulator,id=3DBD4097-E707-4FD9-9568-56062414E3CB`（本机的 iPhone 17 模拟器）。链接日志写明 `building for iOS-simulator-16.0`。没有 iOS 16 模拟器，运行系统新于部署目标。
3. 命令：`xcodebuild -project photos/AIPhotoStudio.xcodeproj -scheme AIPhotoStudio -destination 'platform=iOS Simulator,id=3DBD4097-E707-4FD9-9568-56062414E3CB' -derivedDataPath /tmp/AIPhotoStudio-phase2 ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES test`
4. 结果：`Executed 99 tests, with 0 failures (0 unexpected)`。日志没有单独列出跳过数。`** TEST SUCCEEDED **`。
5. 没有单独启动 App 做人工浏览。
6. 没有在运行中的界面上检查首页、导入或打开项目。
7. 警告：`PhotoManagementView.swift` 仍有原有的 actor 隔离警告，本阶段未改该文件。测试目标链接 XCTest 时提示 XCTest 由更新的 17.0 构建、当前按 iOS 16.0 模拟器链接。另有 AppIntents metadata 跳过提示。`HomeView.swift` 没有编译错误。

`ENABLE_TESTABILITY=YES` 是命令行参数。工程文件里的部署版本和 Bundle ID 没有改。

## G. 回归风险和未完成事项

- 首页导航栏被隐藏。如果该修饰符影响到 push 或 sheet 里的栏，返回按钮可能不可见。需要在模拟器里从首页进入编辑器和相册再返回。
- 两列卡片在很窄的宽度上，说明文字会换很多行。没有在小屏尺寸上运行。
- 三列缩略图不再展示像素和版本。这些信息只在无障碍标签和长按流程中间接保留。
- 精选预设、底栏和个人中心留给后续阶段。做底栏前需要真正的「我的」页面，不能先放空按钮。
- 没有超出本阶段的业务代码修改。未跟踪的审查文档、`.cursor/` 和 `project.xcworkspace/` 仍保持原样。

## I. 底栏补做（2026-10-28）

用户确认首页需要按效果图放上底栏，「我的」里还没有的功能可以后补。

Figma 节点 `35:12`：宽 390、高 84、填充 `#0C0C0C`。顶部分隔线 `#FFFFFF` 约 8% 透明。图标 23×23。文字 10pt Medium。选中「首页」为 `#E2B56A`，未选中「我的」为 `#6A6A6E`。图标在稿里是图片填充，实现用 SF Symbols `house` 和 `person`，没有打包切图。Home 指示条仍由系统绘制。

实现留在 `HomeView` 内部切换，没有把根导航改成 `TabView`。点「我的」会进入同风格的占位页，文案是「这个页面稍后完善。」

构建：`xcodebuild build`，Scheme `AIPhotoStudio`，iPhone 17 模拟器，部署目标 iOS 16.0，退出码 0。没有重新跑单元测试，也没有截图对比。

## H. 最终结论

本阶段的首页代码改造已落地，视觉和手动流程没有验收，状态是部分完成。

不建议在模拟器看过首页之前进入阶段三。进入前至少确认：深色首页在 iPhone 宽度上不溢出，三个入口都能打开原来的页面，项目格能打开项目，长按菜单仍可用，从子页面可以返回。

下一阶段若按审查计划做编辑器外观，范围应限在 `EditorView` 的控件外观，不改 `EditorSession`、画布手势和渲染。

## Figma 设计还原

- 本轮成功读取 Figma。MCP 会话读取了节点 `35:3`。
- 实际参考画板：`01 首页`。`02 选择照片`、`07 最近编辑`、`10 我的` 只沿用审查报告里的风格结论，没有实现这些页面。
- 使用的设计资源：Figma 返回的画板尺寸、背景色、`layoutMode` 和文字样式；加上 `docs/filmtone-ui-audit.md`。`DesignHandoff/` 没有导出的图片或切图。没有下载占位照片。
- 已还原的主要视觉元素：`#121212` 背景，28pt 标题，16pt 区块标题，14/12pt 正文和辅助文字，`#F5F5F7` 与 `#8E8E93`，16pt 圆角深色卡，16pt 边距，金色图标和收藏星，最近编辑三列。
- 未还原的内容：占位照片、精选预设、两个「查看全部」、底部「首页 / 我的」、假状态栏和 Home 指示条。
- 仍然存在的视觉差异见 D 节。
- 是否进行了实际截图对比：未执行。
