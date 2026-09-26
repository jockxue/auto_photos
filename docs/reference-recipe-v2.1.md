# 配方模拟 V2.1：Reference Palette Analyzer

本阶段只增加样片色板分析，不改变 V1 配方的生成、套用、预览和导出。

## 1. 修改文件

新增文件：

- `photos/AIPhotoStudio/Core/Imaging/RecipePaletteAnalyzer.swift`
- `photos/AIPhotoStudioTests/RecipePaletteTests.swift`
- `photos/AIPhotoStudio/Domain/Recipe.swift` 中新增 `ReferencePalette` 和 `PaletteBin`，没有改 `Recipe` 字段

修改文件：

- `photos/AIPhotoStudio/Core/Imaging/RecipeAnalyzer.swift`：`rasterize` 从 `private` 改为模块内可见，供色板分析复用。`analyze()` 的返回值和计算没有改。
- `photos/AIPhotoStudio.xcodeproj/project.pbxproj`：把新源文件和测试加入编译。

删除文件：无。

没有修改：

- `RenderPipeline`
- `CoreImageRenderEngine`
- `ColorProcessor`
- `LightProcessor`
- `EditorSession`
- `RecipeEngine`
- `RecipeStore`
- `EditState`
- `Recipe` 的持久化字段

## 2. 实现说明

- RGB → HSL：按标准 HSL。`L = (max + min) / 2`。`S` 在 `L > 0.5` 时为 `delta / (2 - max - min)`，否则为 `delta / (max + min)`。色相按最大通道折回 `0...1`。这不是 V1 的 `(max - min) / max`。
- 环形距离：`min(|h1 - h2|, 1 - |h1 - h2|)`，单位是 `0...1`。350° 和 10° 的距离是 20°。
- 环形均值：`atan2(Σ sin(h)·w, Σ cos(h)·w)`，只用于方差，不替换固定的 `hueCenter`。
- 软归属：半宽 40°。`weight = max(0, 1 - distance / halfWidth)`。正好落在色相中心的橙色会以约 0.25 的权重同时进入红和黄，避免 30° 硬切成 0。
- `pixelRatio`：各色相区权重除以全部彩色像素的权重合计，八个区之和为 1。灰色不进入合计。
- 方差：相对该区的加权均值，权重归一。色相方差使用环形距离的平方。
- 灰色：`S < 0.05` 不参与任何色相区。阈值是分析器内部常量 `minimumChroma`。没有彩色像素时，八个 `pixelRatio` 都是 0，其余统计也是 0。
- 256 缩放：`analyze(image:)` 调用现有 `RecipeAnalyzer.rasterize`，其中最长边已经限制为 256。
- 后台线程：`analyze(image:)` 使用 `Task.detached`，与 V1 相同。单元测试走同步的 `analyze(samples:)`，不读图。

调试摘要 `debugSummary` 只在 `DEBUG` 编译里存在，分析过程不会打印。

## 3. 测试结果

| 测试 | 结果 |
|---|---|
| gray | PASS |
| red | PASS |
| orange | PASS |
| orange-yellow | PASS |
| hue wrap | PASS |
| blue | PASS |
| ratio normalization | PASS |
| variance | PASS |

同时重跑了 V1 的 `RecipeAnalyzerTests`、`RecipeEngineTests`、`RecipeStoreTests`，全部 PASS。

## 4. V1 回归结果

`RecipeAnalyzer.analyze()`、`RecipeEngine`、`RecipeStore`、`EditorSession`、`RenderPipeline` 的行为没有改变。

唯一的代码改动是 `rasterize` 的访问级别，从私有变为模块内可见。输入、缩放、像素读取和 `Recipe` 输出与原来相同。

## 5. V2.2 建议

可以进入 V2.2，把这里的 RGB↔HSL、环形距离和环形均值抽到 `ColorSpace.swift`。

进入前没有必须先修的正确性缺陷。抽离时保持半宽 40° 和 `minimumChroma = 0.05` 这两个常量的语义，不要改回硬边界。
