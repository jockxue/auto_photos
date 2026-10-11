# 配方模拟 V2.4-A：ColorMapping LUT 构建器

本阶段只把 `ColorMapping` 转成 `CIColorCube` 可用的 33³ RGBA 数据，并通过单元测试验证。没有创建滤镜，也没有接入渲染管线。

## 1. 新增和修改的文件

新增：

- `photos/AIPhotoStudio/Core/Imaging/RecipeColorCubeBuilder.swift`
- `photos/AIPhotoStudioTests/RecipeColorCubeBuilderTests.swift`

修改：

- `photos/AIPhotoStudio.xcodeproj/project.pbxproj`：把新文件加入编译。

`ColorProcessor`、`RenderPipeline`、`CoreImageRenderEngine`、`EditorSession`、`RecipeEngine`、`RecipeStore`、`EditState`、界面和导出都没有改。

## 2. 处理流程

```text
ColorMapping
    ↓
每个 RGB 采样点（0...1）
    ↓
ColorSpace.hsl
    ↓
按 sourceHue 做环形距离平滑插值
    ↓
H / S / L 偏移
    ↓
ColorSpace.rgb
    ↓
RGBA Float，Alpha = 1
```

单点映射 `map(_:through:)` 和整张 LUT 使用同一套 `shift` 计算。

## 3. 插值算法

插值锚点是 `sourceHue`，也就是正在编辑照片该区域的实测色相。`hueCenter` 是样片区域的实测平均色相，不拿来当插值中心，也不使用固定的 8 个分类中心。

40° 半宽内用 smoothstep 衰减：

```text
spatial = smoothstep(1 - circularDistance / (40° / 360°))
effective = spatial × mappingWeight
偏移 = Σ(delta × effective) / Σ(spatial)
```

分母只用空间权重，所以单个正中区域的偏移等于 `delta × mappingWeight`。多个区域按空间权重平均，不会把完整偏移直接相加。区域间隔不相等，权重只看环形距离。

## 4. 色相环绕

色相差使用已有的 `signedCircularHueDelta`，范围是 `-0.5...0.5`。350° 加 `+20°` 会归一化到 10°；10° 加 `-20°` 会到 350°。空间权重同样走 `circularHueDistance`，0° 和 360° 是连续的。

## 5. 低饱和度、空映射和异常值

饱和度从 0.02 到 0.08 平滑打开色相和饱和度偏移。灰色、黑色、白色不会因为不稳定色相被染色。亮度偏移仍受 `mappingWeight` 控制，但不受这个色相门限影响。

`mappingWeight <= 0` 的区域不进入分子和分母。没有任何有效空间权重时返回原色。非有限的 RGB 和 delta 当成 0。输出的色相会归一化，饱和度和亮度限制在 0...1。

## 6. Cube 数据

| 项目 | 值 |
|---|---|
| 维度 | 33 |
| 采样点 | 35,937 |
| Float 数量 | 143,748 |
| 字节 | 574,992（Float32） |
| 顺序 | 红色变化最快，然后绿色，然后蓝色 |
| 通道 | R、G、B、A，A 为 1 |

这与现有 `CurveRenderer` 写入 `CIColorCube` 的顺序一致。本阶段只生成数组，不创建滤镜。

## 7. 新增测试

`RecipeColorCubeBuilderTests` 全部通过，覆盖尺寸、恒等映射、零权重、+20° 色相迁移、0/0.5/1 权重、短弧环绕、相邻区域连续性和中性色边界。

## 8. V1 相关测试

| 测试集 | 结果 |
|---|---|
| RecipeColorCubeBuilderTests | PASS |
| RecipePaletteTests | PASS |
| ColorSpaceTests | PASS |
| RecipeAnalyzerTests | PASS |
| RecipeEngineTests | PASS |
| RecipeStoreTests | PASS |
| ColorMappingTests | PASS |

## 9. 与设计的差异

`ColorMappingBin.hueCenter` 在 V2.3.1 之后是样片区域的实测平均色相，和 `targetHue` 相同。LUT 因此锚在 `sourceHue`，否则 18° 的像素会对着 38° 的样片中心，权重会变小。

`mappingWeight` 已经包含 presence 和 hue confidence。构建器不再重算这些，只把它当作 0...1 的可信度。

## 10. 尚未完成

没有把 LUT 交给 `ColorProcessor` 或 `RenderPipeline`。没有预览、导出、缓存、肤色保护或进一步的自适应映射。这些不属于 V2.4-A。
