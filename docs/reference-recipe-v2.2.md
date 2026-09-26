# 配方模拟 V2.2：ColorSpace

本阶段把 V2.1 已通过测试的 RGB/HSL 和色相环计算抽到独立模块。没有实现颜色映射，也没有改渲染。

## 1. 修改文件

新增：

- `photos/AIPhotoStudio/Core/Imaging/ColorSpace.swift`
- `photos/AIPhotoStudioTests/ColorSpaceTests.swift`

修改：

- `photos/AIPhotoStudio/Core/Imaging/RecipePaletteAnalyzer.swift`：改为调用 `ColorSpace`，不再自己实现 HSL 和环形距离。
- `photos/AIPhotoStudio.xcodeproj/project.pbxproj`：把新文件加入编译。

删除：无。

`Recipe` 字段、`RecipeStore`、`EditState`、`EditorSession`、`RenderPipeline`、`ColorProcessor`、`LightProcessor`、`CoreImageRenderEngine`、`RecipeEngine`、`RecipeView` 都没有改。

## 2. ColorSpace API

```swift
ColorSpace.RGBColor
ColorSpace.HSLColor
ColorSpace.hsl(from:)
ColorSpace.rgb(from:)
ColorSpace.circularHueDistance(_:_:)
ColorSpace.circularHueMean(_:)
ColorSpace.circularHueMean(sumSin:sumCos:)
ColorSpace.normalizeHue(_:)
```

色相范围是 `0...1`。`RecipePaletteAnalyzer.circularHueDistance` 仍保留，内部转到 `ColorSpace`，所以 V2.1 的测试调用不用改。

## 3. V2.1 重构说明

从 `RecipePaletteAnalyzer` 移走的是：

- RGB → HSL，算法与原来相同：`L = (max + min) / 2`，饱和度按亮度是否大于 0.5 分两种除法，色相按最大通道折回 `0...1`。
- 环形距离 `min(|h1 - h2|, 1 - |h1 - h2|)`。
- 由 `sumSin` / `sumCos` 得到的环形均值。

新补上的是 HSL → RGB。V2.1 原来没有反向转换。

仍留在 `RecipePaletteAnalyzer` 的是色板统计本身：8 个固定色相中心、软归属、`pixelRatio` 归一化、方差累加。半宽和饱和度阈值没有改。

## 4. 测试结果

| 测试集 | 结果 |
|---|---|
| ColorSpaceTests | PASS |
| RecipePaletteTests | PASS |
| RecipeAnalyzerTests | PASS |
| RecipeEngineTests | PASS |
| RecipeStoreTests | PASS |

`RecipePaletteTests` 覆盖的 gray、red、orange、orange-yellow、hue wrap、blue、ratio normalization、variance 全部通过。

## 5. 数值一致性

色板测试锁定的比例、重叠和方差方向与抽取前一致，没有出现需要解释的字段变化。

环形均值对已经落在 `(-0.5, 0.5]` 的 `atan2` 结果，归一化方式和原来的“小于 0 就加 1”相同。色相距离在 `0...1` 内与原来相同；`1` 会先归一成 `0`，`0` 和 `1` 的距离仍然是 0。

## 6. 半宽确认

当前代码：

- `hueHalfWidth = 40.0 / 360.0`，即 40°
- `minimumChroma = 0.05`

与 V2.1 报告一致，没有改这两个值。

## 7. 下一阶段

可以进入 V2.3 Color Mapping Model。`ColorSpace` 已经能做 RGB → HSL、映射后再 HSL → RGB，以及环形距离和环形均值。本阶段没有实现映射模型。
