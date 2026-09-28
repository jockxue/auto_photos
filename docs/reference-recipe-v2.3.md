# 配方模拟 V2.3：Color Mapping Model

本阶段只根据两套色板生成纯数据映射。没有生成颜色立方体，也没有改渲染、`EditState` 或 `RecipeStore`。

## 1. 修改文件

新增：

- `photos/AIPhotoStudio/Domain/ColorMapping.swift`
- `photos/AIPhotoStudioTests/ColorMappingTests.swift`

修改：

- `photos/AIPhotoStudio/Core/Imaging/ColorSpace.swift`：增加 `signedCircularHueDelta(from:to:)`。环形距离改为这条有符号短弧的绝对值，数值与原来一致。
- `photos/AIPhotoStudio.xcodeproj/project.pbxproj`：把新文件加入编译。

删除：无。

`Recipe`、`RecipeStore`、`EditState`、`EditorSession`、`RecipeEngine`、`RecipeView`、`RenderPipeline`、`ColorProcessor`、`LightProcessor`、`CoreImageRenderEngine` 都没有改。

## 2. ColorMapping 数据模型

```swift
struct ColorMapping {
    var bins: [ColorMappingBin]
}

struct ColorMappingBin {
    var hueCenter: Double
    var sourceHue: Double
    var sourceSaturation: Double
    var sourceLuminance: Double
    var targetHue: Double
    var targetSaturation: Double
    var targetLuminance: Double
    var hueDelta: Double
    var saturationDelta: Double
    var luminanceDelta: Double
    var mappingWeight: Double
}
```

入口是 `ColorMappingBuilder.build(reference:target:)`。8 个区按数组下标对应，不按最近色相重新配对。

## 3. Mapping 方向

- `source` 是正在编辑的照片，也就是参数 `target` 里的色板。
- `target` 是样片，也就是参数 `reference` 里的色板。
- 方向是照片颜色 → 样片颜色。

色相、饱和度、亮度都取 `PaletteBin.hueCenter`、`saturation`、`luminance`。

## 4. Hue Delta

支持 350° → 10°。实际结果是 `+20/360`，约 `+0.0556`，不是 `-340°`。

`ColorSpace.signedCircularHueDelta(from:to:)` 的范围是 `-0.5...0.5`。10° → 350° 是 `-20°`。

当前分析器写进 `PaletteBin.hueCenter` 的仍是固定色相中心，不是像素的环形平均色相。因此两张真实照片生成的色板，色相差目前是 0。饱和度和亮度差是真实统计值。测试里的 18°、28°、350°、10° 是直接写在 `hueCenter` 上的。进入 V2.4 之前，需要先把测得的平均色相存进色板，否则立方体不会移动色相。

## 5. Presence Function

`pixelRatio` 从 0.02 到 0.08 用 smoothstep：

| pixelRatio | presence |
|---|---|
| 0.02 | 0 |
| 0.05 | 0.5 |
| 0.08 | 1 |

低于 0.02 是 0，高于 0.08 是 1。中间是连续的。

## 6. Hue Confidence

`hueVariance` 是环形距离平方的加权平均。距离 1 表示一整圈，最大距离是半圈，所以方差范围是 0 到 0.25，不是角度，也不是已经归一化的 0 到 1。

先除以 0.25 得到 0...1，再计算：

```text
hueConfidence = 1 / (1 + hueVariance / 0.25)
```

任一侧更分散，就用较大的那个方差。

```text
mappingWeight = targetPresence × referencePresence × hueConfidence
```

结果限制在 0...1。任一侧 `pixelRatio` 为 0 时，权重是 0，差值也是 0。

## 7. 测试结果

| 测试集 | 结果 |
|---|---|
| ColorMappingTests | PASS |
| RecipePaletteTests | PASS |
| ColorSpaceTests | PASS |
| RecipeAnalyzerTests | PASS |
| RecipeEngineTests | PASS |
| RecipeStoreTests | PASS |

## 8. V1 回归

V1 的配方生成、套用、存储和渲染没有变化。

低饱和度仍由 V2.1 的 `minimumChroma = 0.05` 在色板统计时排除。V2.3 没有再加一套阈值。

## 9. 下一阶段

映射模型可以交给 V2.4 生成 `CIColorCube`。在此之前应先把色板里的实测平均色相存下来。否则真实样片的 `hueDelta` 会一直是 0，立方体只能改变饱和度和亮度。本阶段没有实现 V2.4。
