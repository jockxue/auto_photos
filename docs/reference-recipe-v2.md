# 配方模拟 V2 技术方案

本文件只审计现有 V1 代码并给出 V2 方案，不包含代码修改。

V1 的配方只改全局调整和一条 RGB 曲线，没有颜色分区，也没有 `version` 字段。V2 应把样片色板存进配方，套用时再按目标照片的颜色分布生成一张颜色立方体，仍交给现有的 `CIColorCube` 渲染。

## 1. V1 当前实际实现

分析入口是 `RecipeAnalyzer`。样片先由 `ImageSourceFactory.decode` 缩到最长边 256，再在后台光栅化成 sRGB 的 `RecipeSample`。亮度用 Rec.709 权重 `0.2126R + 0.7152G + 0.0722B`。这里的饱和度是 `(max - min) / max`，不是 HSL 饱和度。

### Tone

分位数来自全部像素亮度，取最近的排序下标。

| 参数 | 实际算法 | 限制 |
|---|---|---|
| Exposure | `log2(max(P50, 0.02) / 0.45)` | ±1 |
| Contrast | `(P90 - P10 - 0.55) / 0.55 × 40` | ±30 |
| Highlights | `(0.82 - P90) × 80` | ±50 |
| Shadows | `(P10 - 0.12) × 120` | ±50 |
| Whites | `(P99 - 0.92) × 80` | ±30 |
| Blacks | `(P1 - 0.02) × 400` | ±30 |

P5、P95 只算出来，没有参与赋值。亮度、降噪没有被分析器写入，保持 0。

### Color

平均饱和度低于 0.06，或没有饱和度大于 0.08 的像素时，色温、色调、饱和度、自然饱和度全部写 0。

否则只统计这些有色彩的像素：

| 参数 | 实际算法 | 限制 |
|---|---|---|
| Temperature | 平均 `(R - B) × 45` | ±25 |
| Tint | 平均 `-(G - (R + B) / 2) × 40` | ±20 |
| Saturation | `(平均饱和度 - 0.28) × 70` | ±40 |
| Vibrance | `(0.34 - 饱和度 P75) × 25` | ±15 |

没有平均色相，也没有色相直方图。

### Curve

只生成 RGB 曲线。红、绿、蓝保持 `ChannelCurve.identity`。

中间三点相对直线的偏移是：

- 0.25：`(P25 - 0.22) × 0.28`，限制在 ±0.06
- 0.50：`(P50 - 0.45) × 0.22`，限制在 ±0.05
- 0.75：`(P75 - 0.68) × 0.22`，限制在 ±0.05

端点固定为 `(0,0)` 和 `(1,1)`，然后强制单调，相邻点至少相差 0.01。

### Texture

有实际分析，不是固定常数。低于阈值时保持 0。

- Sharpness：4 邻域拉普拉斯绝对值的平均。大于 0.18 时 `(值 - 0.18) × 40`，上限 12。
- Clarity：同一指标大于 0.22 时 `(值 - 0.22) × 30`，上限 8。
- Grain：隔列的高频残差。大于 0.16 时 `(值 - 0.16) × 25`，上限 8。

宽或高不超过 2 像素时，这三个值都不改。

自动分析出来的 `filter` 固定是 `nil`。从当前编辑保存配方时，才会带上当时的滤镜。

套用公式是 `current + (recipe - current) × strength`。`geometry` 原样保留。强度为 0 时滤镜不变；为 1 时整段替换；中间值只在配方有滤镜时按标识符插值强度。

## 2. V1 可以直接复用的代码

- `RecipeAnalyzer.rasterize`：后台缩小并读取像素。目标照片的色板分析可以走同一条路径。
- `RecipeToneAnalyzer.percentile` 和 `LuminanceDistribution`：色板里的亮度分布还能用。
- `Recipe`、`RecipeStore`、`RecipeEngine` 的强度插值和几何保留。
- `EditorSession` 的 `beginRecipePreview`、`previewRecipe`、`commitRecipe`、`cancelRecipePreview`。一次撤销已经包住整份 `EditState`。
- `CurveRenderer` 的 33³ `CIColorCube`。颜色映射应生成另一张立方体，而不是新渲染器。
- `ColorProcessor` 末尾已经是曲线立方体的挂载点。映射立方体可以接在它后面，不增加 `RenderStage`。
- 预览仍是最长边 2048、60ms 防抖；导出仍是全尺寸、同一条管线。

## 3. V1 存在的技术限制

- 所有颜色被收成一组全局滑杆。橙色和蓝色不能分开移动。
- 色彩判断是 RGB 差值，不是色相。一张偏蓝的样片只会把整张目标片拉冷。
- 饱和度公式在低亮度像素上不稳定，也不区分色相环。
- 曲线只跟着整图亮度走，不能表达某个色相的明暗。
- 配方生成后与目标照片无关。样片里大量蓝色、目标片几乎没有蓝色时，V1 仍会改全局色温。
- `Recipe` 没有 `version`。`RecipeStore.load()` 对整个 `recipes.json` 做一次解码，任何一个配方解码失败，整个库都会变成 `readFailed`。
- 项目里没有 HSL、Lab、OKLab 转换，也没有 `CIHueAdjust`、`CIColorKernel`、`CIColorCubeWithColorSpace`。

## 4. V2 技术架构

```text
样片（最长边 256）
    ↓ 现有 rasterize
ToneAnalyzer（保留 V1）
PaletteAnalyzer
    ↓
Recipe V2（V1 字段 + 参考色板）

套用时：
当前原图缩到最长边 256
    ↓
TargetPaletteAnalyzer
    ↓
ColorMapping（参考色板 × 目标色板 × 强度 × 肤色保护）
    ↓
33³ CIColorCube，写入 EditState 的可选字段
    ↓
现有 ColorProcessor → CoreImageRenderEngine
    ↓
预览 2048 / 导出全尺寸
```

立方体只依赖颜色，不依赖输出分辨率。预览和导出用同一张立方体。不要为每帧、每个像素重算色板。

`RenderPipeline` 的阶段顺序保持不变。映射是 `ColorProcessor` 里曲线之后的一次 `CIColorCube`，和现在的 `CurveRenderer` 相同。

## 5. V2 数据模型

V1 现在的 JSON 只有这些字段，没有 `version`：

```text
Recipe
├── id
├── title
├── createdAt
├── adjustments
├── curves
└── filter
```

V2 在 `Recipe` 上增加可选字段，缺省时按 V1 解码：

```swift
struct Recipe {
    var schemaVersion: Int = 1          // 旧 JSON 没有这个键时当作 1
    var id: UUID
    var title: String
    var createdAt: Date
    var adjustments: Adjustments
    var curves: CurveAdjustment
    var filter: FilterConfig?
    var palette: ReferencePalette?      // V2 才有
}

struct ReferencePalette {
    var bins: [PaletteBin]              // 固定 8 个色相区
}

struct PaletteBin {
    var hueCenter: Double               // 0...1 色相环
    var saturation: Double
    var luminance: Double
    var pixelRatio: Double
    var hueVariance: Double
    var saturationVariance: Double
    var luminanceVariance: Double
}
```

八个色相中心：红 0°、橙 30°、黄 60°、绿 120°、青 180°、蓝 240°、紫 270°、品红 300°。每个像素按环形距离做软归属，可以同时落入相邻两档，所以橙和黄不会分成硬边界。

`ColorMapping` 不写入配方。它依赖目标照片，套用时计算，放进 `EditState` 的可选字段：

```swift
struct ColorMapState: Codable, Equatable {
    var cubeDimension: Int              // 33
    var cubeData: Data                  // RGBA float
    var recipeID: UUID
    var strength: Double
}
```

旧项目的 `EditState` 没有这个键，解码为 `nil`，渲染与现在一致。

## 6. V2 Color Mapping 算法

对每个色相区，只在样片和目标片都有足够像素时建立一对均值：

```text
目标区 (H, S, L) → 样片区 (H, S, L)
```

色相差用环形距离，取短弧，不从 350° 直接跳到 10°。饱和度和亮度按普通差值。

一个像素的映射是相邻色相区的加权平均。权重是：

```text
软归属 = max(0, 1 - 环形距离 / 半宽)
半宽约 30°，橙和黄重叠
最终权重再乘以该区的 mappingWeight
```

低饱和像素的色相不可靠，软归属再乘饱和度，接近灰色时不改色相。映射后的结果与原色按权重混合，避免一个区把邻近颜色拉出断层。

这不是用样片平均 RGB 替换目标像素。

## 7. V2 Adaptive Mapping 算法

每个色相区的强度：

```text
mappingWeight = targetPresence × referencePresence × hueConfidence
```

- `targetPresence`：目标片该区 `pixelRatio` 从 0.02 到 0.08 平滑升到 1。低于 2% 视为几乎没有这种颜色，权重为 0，不凭空制造蓝色。
- `referencePresence`：样片该区比例同样处理。样片里没有的颜色，不作为映射目标。
- `hueConfidence`：`1 / (1 + hueVariance)`。色相很散的区少拉动。

因此：样片有很多蓝、目标片几乎没有蓝时，蓝区权重接近 0，全局色温仍只来自 V1。目标片有样片没有的颜色时，该区没有样片目标，像素保持原色。

配方强度继续乘在 `mappingWeight` 上。0% 时立方体是恒等映射，当前调整和曲线仍走 V1 的插值。

## 8. Skin Tone Protection 方案

不用 Vision，也不用人脸框。在生成立方体时，用 HSL 判断源颜色像不像肤色：

- 色相大约在 15° 到 50°
- 饱和度大约在 0.15 到 0.65
- 亮度大约在 0.25 到 0.85

三个条件用平滑函数，不使用硬阈值切边。满足得越多，映射强度越低。

设计起点是普通颜色权重为 1，肤色区大约降到 0.4。这是可调参数，不是最终产品值。它只减弱色相和饱和度拉动，不禁止 V1 的整体曝光。皮肤高光和阴影仍跟着整图明暗走。

## 9. Core Image 实现方案

选择 **CPU 分析 + 现有 `CIColorCube`**。

| 方案 | 结论 |
|---|---|
| 只用现有全局滤镜 | 做不到分区映射 |
| `CIHueAdjust` | 只有整图色相旋转 |
| `CIColorKernel` | 能写逐像素逻辑，但项目里没有，也难把两张色板塞进 kernel |
| 新的 Metal shader | 明确不做 |
| CPU 分析 + `CIColorCube` | 与 `CurveRenderer` 相同，立方体与分辨率无关 |

分析用 256。实时预览继续 2048。导出继续全尺寸，只是多应用一张已经算好的立方体。不要在导出时重跑色板分析。

`CIColorCubeWithColorSpace` 现在没有使用。V2 第一版继续用现有 sRGB 立方体，避免同时改色彩管理。

## 10. V1 → V2 数据兼容方案

`Recipe` 改成自定义解码：

- 缺少 `schemaVersion` 时当作 1。
- 缺少 `palette` 时当作 `nil`。
- V1 的 `adjustments`、`curves`、`filter` 原样保留，套用行为不变。
- 只有 `schemaVersion >= 2` 且 `palette` 存在时，才生成映射立方体。

不需要单独的迁移器，也不要批量改写用户已有的 `recipes.json`。保存一份新配方时写 `schemaVersion = 2`。旧配方被用户再次保存时才升级。

`RecipeStore` 现在是整文件解码。V2 应逐条解码：坏掉的一条跳过并报告，不能让一条新字段错误清空整个库。

## 11. V2 分阶段开发计划

| 阶段 | 内容 | 输入 | 输出 | 与 V1 的关系 |
|---|---|---|---|---|
| V2.1 | 样片色板 | 256 像素 | 8 个 `PaletteBin` | 不改变现有配方结果 |
| V2.2 | HSL 工具 | RGB | 色相环、饱和度、亮度及反向转换 | 不改渲染 |
| V2.3 | 映射模型 | 两套色板 | 每区的源→目标差值 | 纯数据 |
| V2.4 | 映射立方体 | 映射模型 | 33³ 立方体 | 先不挂到预览 |
| V2.5 | 自适应权重 | 目标色板比例 | `mappingWeight` | 低比例区权重为 0 |
| V2.6 | 软过渡 | 相邻色相 | 重叠权重 | 消除橙/黄断层 |
| V2.7 | 肤色保护 | 源像素 HSL | 降低后的映射强度 | 仍不用 Vision |
| V2.8 | 版本解码 | 旧 `recipes.json` | V1 配方仍可读取 | 不改写旧文件 |
| V2.9 | 界面 | 现有配方页 | 显示色板和映射开关 | 复用强度滑杆和撤销 |
| V2.10 | 测试和性能 | 合成色块、旧 JSON | 正确性与耗时 | 预览分辨率不变 |

## 12. 每阶段预计修改的文件

- **V2.1** 新增 `Core/Imaging/RecipePaletteAnalyzer.swift`。不改 `RecipeAnalyzer` 的现有返回值，先让测试直接调用。
- **V2.2** 新增 `Core/Imaging/ColorSpace.swift`。
- **V2.3** 新增 `Domain/ColorMapping.swift`。
- **V2.4** 新增 `Core/Imaging/ColorMapRenderer.swift`，复用 `CIColorCube` 的数据布局。
- **V2.5、V2.6** 修改 `ColorMapping.swift` 和 `ColorMapRenderer.swift`。
- **V2.7** 新增 `Core/Imaging/SkinToneEstimator.swift`，由立方体查询调用。
- **V2.8** 修改 `Domain/Recipe.swift`、`RecipeStore.swift`，以及 `EditState` 的可选 `colorMap` 解码。`RenderPipeline.ColorProcessor` 只在该字段存在时多调用一次立方体。
- **V2.9** 修改 `RecipeView.swift`、`EditorSession.swift` 和三份本地化字符串。套用时先算目标色板，再生成立方体，然后走现有 `commitRecipe`。
- **V2.10** 新增 `RecipePaletteTests.swift`、`ColorMappingTests.swift`，并给 `EditStateTests` 加一条旧 JSON 解码。

`RenderEngine.swift`、`LightProcessor`、滤镜列表和阶段枚举不动。

## 13. 测试方案

- 纯灰图的八个色相区比例都接近 0，映射权重为 0。
- 只有蓝色的样片、只有橙色的目标片：蓝区权重为 0，橙色不被画成蓝色。
- 两边都有橙色：目标色相 18°、样片 28° 时，橙色像素向 28° 移动，黄色像素移动更少。
- 350° 和 10° 的色相差是 20°，不是 340°。
- 肤色范围的像素移动量小于同强度的非肤色像素。
- 强度 0 时立方体不改变颜色；强度 1 时等于完整映射。
- 没有 `palette` 的 V1 JSON 解码后，`schemaVersion == 1`，套用结果与现在一致。
- 一条损坏配方不会让 `fetchAll()` 整体失败。
- 几何、撤销和预览分辨率保持现有测试。

## 14. 性能方案

- 样片和目标片分析都限制在最长边 256，放在 `Task.detached`。
- 立方体 33³ 大约 3.6 万次映射，只在套用、改强度或更换配方时生成一次，并放进 `EditState`。
- 拖动强度时可以复用两套已算好的色板，只重建立方体，不重新读图。
- 预览和导出不再分析像素，只应用这张立方体。
- 如果 33³ 在拖动时仍超过一帧，先把强度更新节流到现有的 60ms 预览防抖，不提高立方体分辨率。

## 15. 潜在问题

- HSL 在低饱和度处色相不稳定。灰色必须退出映射。
- 肤色范围会包含橙色墙壁和日落。V2 只能降低这些颜色的映射，不能保证只保护人脸。
- 两张立方体串联会增加预览成本。曲线仍是恒等时，应继续跳过曲线立方体。
- `EditState` 若保存完整立方体，撤销快照会变大。33³ 的 RGBA float 大约 560KB，一次撤销可以接受；不要把它写进 `recipes.json`。
- 整文件解码的 `RecipeStore` 在兼容改造前，新增必填字段会让旧库全部读失败。所以新字段必须可选。

## 16. 第一阶段应该先做什么

先做 **V2.1：样片色板分析**。

它只新增色板统计和测试，不改已保存配方，也不改预览。确认八个色相区的比例、均值和方差之后，再做 HSL 工具和映射模型。
