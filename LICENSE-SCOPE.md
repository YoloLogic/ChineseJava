# 许可证范围说明（LICENSE-SCOPE）

> 说清楚：这个仓库里**哪些文件**适用哪种许可、为什么、以及发行时要做什么。

## 一、一句话

**本项目是 OpenJDK 28 的派生作品（derivative work），整体随上游采用 GPLv2 + Classpath Exception。**
我们原创的表、生成器、判据、文档也一并放在同一许可下（减少许可摩擦，不做多重许可）。

## 二、逐类文件

| 类别 | 位置 | 许可 | 说明 |
|---|---|---|---|
| **上游 OpenJDK 源码** | `jdk\`（整棵树） | **GPLv2 + Classpath Exception** | 上游原件；版权归 Oracle 及 OpenJDK 贡献者 |
| **我们对上游的改动** | `jdk\` 内 **14 个文件**（12 改 + 2 新增；`NOTICE.txt` 按"处"计为 16 条） | **GPLv2 + Classpath Exception**（作为派生部分） | 改动是"加法"：中文关键字挂表 + 解析层位置识别 + 中文诊断资源 + 2 处上游本地化 bug 绕过 |
| **本项目的原创文件** | `tools\`、`tests\`、`docs\`、`examples\`、`verify.ps1`、`install.ps1`、`README.md`、`常见问题.md` | **GPLv2 + Classpath Exception** | 表（TSV）、生成器、判据套件、台账、文档 |
| **上游内置的第三方代码** | `jdk\src\**`（如 zlib、libpng、libjpeg、lcms、harfbuzz、freetype 子集等） | **各自原许可** | 随上游原样保留，未改动；明细见上游 `ADDITIONAL_LICENSE_INFO` 与各目录内声明 |
| **上游的二进制/工具（不入库）** | `E:\msys64`、`E:\java\jdk-27`、`E:\java\jtreg` | 各自许可（MSYS2 / Temurin / jtreg） | **只是构建与测试依赖**，不随本项目发行 |

## 三、Classpath Exception 意味着什么

上游的 `src\**\classes\**` 等 Java 类库源码带 Classpath Exception：
把它们编译进你的程序、或把它们作为库链接，**不会**导致你的程序被 GPL 传染。
我们的诊断资源文件（`*_zh_CN.properties`）与生成器属于这一类语境。

## 四、发行时要做的三件事

1. **给源码**：GPLv2 要求随二进制提供对应源码（或书面提供源码的承诺）。
   我们发行包里应含：`jdk\`（含我们改动后的完整源码）+ 本仓库的原创文件。
2. **保留声明**：不得删除上游的版权头与 `LICENSE`、`ADDITIONAL_LICENSE_INFO`、`ASSEMBLY_EXCEPTION`；
   并附本文件与 `NOTICE.txt`。
3. **不得冒充官方**：见下一节。

## 五、商标与命名（重要）

- **不使用 Oracle 的 "Java" 商标**：本项目的名称是 **ChineseJava**；对外描述用
  "基于 OpenJDK 的中文 Java 实现" 这类**描述性**说法，不得暗示是 Oracle/OpenJDK 官方发行版。
- **保留 `java` / `javac` 文件名是兼容性必需**（构建工具、脚本、IDE 都按这个名字找），
  但发行包中必须同时给出本文件与 `NOTICE.txt`，说明这是**修改版**。
- 本仓库**不含**任何 Oracle 专有代码（全部来自 OpenJDK 公开源码）。

## 六、你改这份代码时的义务

你基于本派生作品再发行/再修改时，同样要：保留许可与声明（GPLv2）、提供源码、
并且**不要把修改版叫成官方 Java**。中文拼写与诊断汉化是**加法**，不改变上游代码的许可状态。
