# 配方模拟 V2.3.1：实测色相

`PaletteBin.hueCenter` 现在保存该颜色区域内有效像素的加权环形平均色相。固定的 8 个中心只用于把像素分到区域里。

## 1. 修改了哪些文件

修改：

- `photos/AIPhotoStudio/Core/Imaging/RecipePaletteAnalyzer.swift`
- `photos/AIPhotoStudioTests/RecipePaletteTests.swift`

没有改 `ColorMapping`、`Recipe`、`RecipeStore`、`EditState`、`EditorSession`、`RecipeEngine`、`RecipeView` 和渲染链路。

## 2. hueCenter 是否已是实际环形平均

是。有有效像素时，`hueCenter` 使用该区域已累计的 `sumSin` / `sumCos`，经 `ColorSpace.circularHueMean(sumSin:sumCos:)` 得到。没有有效像素时为 0，并且是有限数值。

## 3. 固定 8 个中心的用途

`0°、30°、60°、120°、180°、240°、270°、300°` 仍然只用于 soft assignment。半宽仍是 40°，`minimumChroma` 仍是 0.05。像素权重仍是原来的色相归属权重，没有另加一套饱和度权重。

## 4. Hue Mean 算法

```text
sumSin += sin(hue × 2π) × weight
sumCos += cos(hue × 2π) × weight
meanHue = normalizeHue(atan2(sumSin, sumCos) / 2π)
```

## 5. 350° 和 10°

红色区域内这两类像素的环形平均接近 0°，不是 180°。

## 6. ColorMapping 方向

没有改。`source` 仍是正在编辑的照片，`target` 仍是样片。方向是照片颜色 → 样片颜色。

## 7. 18° → 38°

样片橙色实测约 38°，目标照片橙色实测约 18° 时，`hueDelta` 约为 `+20°`。350° 的照片对 10° 的样片，短弧也是 `+20°`。

## 8. hueVariance

仍是相对这个环形平均色相的距离平方加权平均，单位和范围仍是 0 到 0.25。置信度公式没有改：

```text
hueConfidence = 1 / (1 + hueVariance / 0.25)
```

## 9. Presence

没有改。低于 0.02 为 0，0.05 为 0.5，0.08 及以上为 1。

## 10. 测试结果

| 测试集 | 结果 |
|---|---|
| RecipePaletteTests | PASS |
| ColorSpaceTests | PASS |
| RecipeAnalyzerTests | PASS |
| RecipeEngineTests | PASS |
| RecipeStoreTests | PASS |
| ColorMappingTests | PASS |

新增覆盖包括橙色实测 35°、350° 与 10° 的环形平均、18° 到 38° 的 `+20°` 映射、反向短弧，以及空区域不会产生非有限数值。

## 11. 渲染链路

没有修改。

## 12. 是否可以进入 V2.4

可以。真实 `hueCenter` 已经保存，V2.4 可以按 `source → target` 生成 `CIColorCube`。
