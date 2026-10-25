# 配方模拟 V2.4-B：接入渲染

颜色区域迁移已经进入现有 `RenderPipeline`。没有启用时不会多加滤镜。曲线 LUT 和颜色 LUT 是连续的两个 `CIColorCube`，不会互相覆盖。

## 1. 实际新增和修改的文件

新增：

- `photos/AIPhotoStudioTests/RecipeColorRenderTests.swift`

修改：

- `Domain/Recipe.swift`：可选 `palette`。旧 JSON 没有这个字段时解码为 `nil`。
- `Domain/EditState.swift`：可选 `colorMapping`。没有这个字段时不启用颜色迁移。
- `Core/Imaging/RecipeAnalyzer.swift`：生成配方时附上参考色板。调整、曲线和滤镜的计算没有改。
- `Core/Imaging/RecipeColorCubeBuilder.swift`：增加 `apply(_:to:)`，用已有 LUT 数据创建 `CIColorCube`。
- `Core/Imaging/RenderPipeline.swift`：`ColorProcessor` 在曲线之后按需应用颜色 LUT。
- `Features/Editor/EditorSession.swift`：套用配方时分析当前照片色板，生成 `ColorMapping`，并按强度缩放权重。
- `project.pbxproj`：登记集成测试。

没有新渲染引擎，没有改 UI，没有改 `RecipeStore`。

## 2. 调用链

```text
参考样片
    ↓ RecipeAnalyzer（256 边长）
ReferencePalette，保存在 Recipe.palette

当前照片原图
    ↓ RecipeAnalyzer.rasterize（最长边 256，每个编辑会话只做一次）
TargetPalette

ColorMappingBuilder.build(reference:target:)
    ↓ 权重再乘配方强度
EditState.colorMapping

预览 / 导出
    ↓ 同一个 RenderPipeline
ColorProcessor
    ↓ 现有色彩调整
    ↓ 现有曲线 CIColorCube（若曲线不是恒等）
    ↓ RecipeColorCubeBuilder.apply（仅当 colorMapping 存在）
```

方向仍是正在编辑的照片颜色 → 样片颜色。

## 3. LUT 在 ColorProcessor 中的位置

在色温、饱和度、自然饱和度之后，紧接在曲线 LUT 之后。`colorMapping == nil` 时直接返回曲线结果，和原来一样。

## 4. 两个 LUT 的顺序

先曲线，再颜色迁移。曲线继续表示影调，颜色立方体表示区域色相迁移。后一个滤镜的输入是前一个的输出，所以曲线不会被颜色 LUT 替换掉。

## 5. 预览与导出

两边都调用 `CoreImageRenderEngine.render`，里面是同一个 `RenderPipeline`。颜色映射在套用配方时算好并放进 `EditState`，不在预览或导出里各算一次。目标色板来自当前原图缩到 256 的像素，不来自 2048 预览图。同一张小图上，预览尺寸和全尺寸导出的像素一致。

## 6. 未启用时的兼容性

`colorMapping == nil` 时，渲染像素与接入前的颜色路径相同。旧配方没有 `palette`，套用时不会写入 `colorMapping`。强度为 0 时也不生成映射。几何仍由 `RecipeEngine` 原样保留。

## 7. 测试结果

| 测试集 | 结果 |
|---|---|
| RecipeColorRenderTests | PASS |
| RecipeColorCubeBuilderTests | PASS |
| RecipePaletteTests | PASS |
| ColorSpaceTests | PASS |
| RecipeAnalyzerTests | PASS |
| RecipeEngineTests | PASS |
| RecipeStoreTests | PASS |
| ColorMappingTests | PASS |
| EditStateTests | PASS |

集成测试覆盖未启用、零偏移、橙色向样片移动、曲线与颜色迁移同时生效，以及预览和导出一致。

## 8. 性能风险

目标色板在每个编辑会话里只分析一次，并缓存在 `EditorSession`。拖动强度只改 `mappingWeight`，不重新统计色板。

颜色 LUT 和曲线 LUT 一样，每次渲染都会重新生成 33³ 数据。预览防抖仍是原来的 60ms。这是现有曲线的做法，本阶段没有另做缓存。

## 9. 未完成事项

配方 JSON 现在可以带上 `palette`，但还没有版本迁移界面，也没有把颜色映射单独做成可开关的 UI。肤色保护、进一步自适应映射和 LUT 缓存都没有做。
