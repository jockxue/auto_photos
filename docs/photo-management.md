# 系统相册照片管理

独立的全屏浏览页面，直接读取 iPhone 系统相册。不进入现有编辑器，也不修改配方和渲染。

## 1. 新增和修改的文件

新增：

- `Features/PhotoManagement/PhotoManagementView.swift`
- `Features/PhotoManagement/PhotoLibraryViewModel.swift`
- `Features/PhotoManagement/PhotoBrowseController.swift`
- `AIPhotoStudioTests/PhotoBrowseControllerTests.swift`

修改：

- `Features/Home/HomeView.swift`：增加入口。
- 三份 `Localizable.strings`。
- `project.pbxproj`。

没有改 `EditState`、`EditorSession`、`Recipe`、渲染管线或导出。

## 2. 导航入口

首页「从照片中选择」下面新增「照片管理」。它在现有 `NavigationStack` 里推入新页面，左上角返回。

## 3. 授权

使用 `PHPhotoLibrary.requestAuthorization(for: .readWrite)`。已有 `NSPhotoLibraryUsageDescription`，没有新增权限键。

- 未决定、拒绝、受限：显示说明。未决定时可请求授权，已拒绝则打开系统设置。
- 完全访问和有限访问：读取当前可见的照片。有限访问会提示只能看到已选照片。

## 4. 手势

一次拖动结束时判断方向。水平位移超过 72 且大于垂直位移时，左滑下一张，右滑上一张。上滑超过 88 且大于水平位移时，立即删除当前照片。轻微拖动不触发。删除进行中不响应浏览手势。第一张和最后一张不会越界。

## 5. 删除

上滑达到距离后，立即用当时记录的 `localIdentifier` 调用 `PHPhotoLibrary.performChanges` 和 `PHAssetChangeRequest.deleteAssets`。应用内不再显示删除确认框。PhotoKit 仍会弹出系统自己的删除确认，这一步不能绕过。同一次删除进行中再次上滑会被忽略。只有系统返回成功才从列表移除：中间照片显示原来的下一张，最后一张显示上一张，唯一一张则进入空状态。失败或系统取消时保留原列表，并在页面底部显示错误。

## 6. 编辑和缩略图

右上角网格按钮打开三列缩略图。点一张会切到那张并回到大图。删除进行中不能换图。

右上角编辑按钮把当前系统照片导入一份项目，再用现有 `EditorView` 打开。照片管理页不改编辑状态、配方或渲染。返回首页后项目列表会刷新。

大图仍用 `PHCachingImageManager` 按 1600 像素加载当前张，并预缓存相邻一张。切换时取消上一次请求。离开页面后停止监听和加载。

## 7. 编译和测试

`PhotoBrowseControllerTests` 覆盖左右切换、边界、删除中间/最后/唯一一张、删除进行中忽略第二次删除、删除失败保留照片、缩略图选中索引，以及拒绝权限需要提示。测试没有删除系统相册里的真实照片。

## 8. 尚未完成

有限访问不能在页内改选照片，需要去系统设置。应用内确认已去掉。PhotoKit 的系统删除确认仍然会出现，公开接口没有关闭它的参数。
