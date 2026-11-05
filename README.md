# ChineseJava · 中文编程（OpenJDK 28 派生 · Windows 线）

> **中英两种写法都能用，而且可以混着写。** 中文不是替换英文，是**并列多出来的一种拼写**：
> 中文拼写命中后仍然回落到**完全未改动**的英文原表 —— 两种写法产生同一个 token、同一份字节码。

---

## 🔴 报错是中文，前缀仍是英文

```
坏.java:1: error: 不兼容的类型: String无法转换为int
        整数 x = "s";
                 ^
1 个错误
```
前缀保留 `error:` / `warning:` / `note:` **默认英文**（编辑器问题面板、构建工具、CI 日志解析都靠它），
正文与术语是中文；需要中文前缀（`错误:`/`警告:`/`注:`）时见 [常见问题.md](常见问题.md)。

## 这是什么

一份 **OpenJDK 28 派生**的中文 Java：不改 `class` 文件、不改 `java.*` 真名、不改字节码，
只在 **javac 前端**加了两层加法：

| 层 | 内容 | 状态 |
|---|---|---|
| **L2 关键字** | 71 个中文拼写位（硬 53 + 软 18），中英可混写 | ✅ 已完成（13+ 条判据） |
| **L1 诊断** | 术语统一（`批注`→`注解` 等）、补 15 条上游缺失译文、前缀默认英文可开关、**硬关键字误用给专属消息** | ✅ 已完成（21 条判据） |
| ~~L3 中文标准库名字层~~ | ~~中文类名/方法名别名表~~ | ⬜ **已取消**（2026-11 口径变更：不做库名汉化） |
| ~~L4 实现层~~ | ~~抄一份实现并中文化~~ | ⬜ 不做 |

> **口径**：本派生**只汉化关键字与诊断，不汉化任何库名**。
> `java.*`、`java.util.List`、`List.add` 全部保持英文；原库原汁原味，`java.*` 命名空间无任何放宽。
> 取消的原因与处置记录见 [口径变更-取消库名汉化.md](docs/口径变更-取消库名汉化.md)。

**英文侧零影响**：中文写法与英文写法的字节码 SHA256 一致、诊断键不变、
`-J-Duser.language=en` 一键回到官方英文体验。

## 快速开始

```java
// 示例：examples/中文示例/甲类.java
公开 类型 甲类 {
    公开 静态 空型 main(String[] 参数) {
        整数 计数 = 0;
        如果 (计数 == 0) {
            System.out.println("你好，ChineseJava");
        } 否则 {
            System.out.println("bad");
        }
    }
}
```

```powershell
# 用我们构建出的 JDK 编译并运行（镜像路径）
$J = 'E:\ChineseJava\jdk\build\cnjava\images\jdk'
& "$J\bin\javac.exe" -d out 甲类.java
& "$J\bin\java.exe" -cp out 甲类
```

英文写法（`public class` / `static void main` / `if`）与上面的中文写法**混着写也行**。

## 怎么构建（Windows）

```powershell
pwsh -File tools\构建.ps1 -Check        # 环境检查（MSYS2 / boot JDK / VS 2022）
pwsh -File tools\构建.ps1 -Configure    # 只配置
pwsh -File tools\构建.ps1               # 配置 + make images + 中文关键字冒烟
pwsh -File verify.ps1                  # 用户侧自检（含"判据自测"：把表改坏必须变红）
```

前置：**MSYS2**（`E:\msys64`，提供 autoconf/make/zip）、**boot JDK 27 或 28**（`E:\java\jdk-27`）、
**VS 2022 C++ 工具链**。来源与 SHA256 见 [构建环境台账.md](docs/构建环境台账.md)。

## 包里有什么 / 没有什么

**有**：`src/jdk.compiler` 的词法层与解析层补丁（中文关键字）、`*_zh_CN.properties` 的诊断汉化、
生成器与守卫（表 → 产物，唯一写入者）、判据套件（真编译真运行）、台账（差异/覆盖率/判据原始输出）。

**没有**：`class` 文件改动（一个字节都没动）；`java.*` 真名改动；L3 中文标准库层；
非 Windows 平台的验证；零警告验证（首次构建用了 `--disable-warnings-as-errors`）。

## 判据与台账（都在 `docs\`）

| 文件 | 是什么 |
|---|---|
| [中文关键字表.md](docs/中文关键字表.md) | 71 个中文拼写位（含强度/出处），由生成器产出 |
| [判据记录.md](docs/判据记录.md) | 每一批的**原始输出**与"没做什么/没测过什么" |
| [诊断差异台账.md](docs/诊断差异台账.md) | 诊断改动的三类计数（新增/覆盖上游/保留上游，Σ 口径） |
| [构建环境台账.md](docs/构建环境台账.md) | MSYS2 / boot JDK 的来源与 SHA256、**两个上游本地化 bug 与本地补丁** |

**表是唯一真相**：`tools\关键字表.tsv`、`tools\诊断术语表.tsv`、`tools\诊断补缺表.tsv`；
产物禁止手改，改表后重跑生成器，守卫用 `-Check` 核对（手改或不重跑都会被抓出来）。

## 已知边界（如实标注）

- **单向门**：用了中文关键字的源码，**官方 javac 编不过**（这是设计目的：我们能读别人的，别人读不了我们的中文拼写）；
  纯中文标识符（`String 名字`）官方 javac 一直能读 —— 不对称只来自**关键字**与将来的 L3 库层。
- **硬关键字误用时的诊断还很差**（只报 `不是语句`/`需要';'`），尚未给"X 是关键字"的可行动提示。
- 上游两个**本地化 bug**（中文 MSVC 横幅让 `configure` 判错 CPU 与版本号）我们打了本地补丁绕过，
  这不是语言特性，将来上游修好后应删除。

## 许可证与商标

- 本体是 **OpenJDK 28 的派生作品**，随上游采用 **GPLv2 + Classpath Exception**；派生说明与范围见
  [LICENSE-SCOPE.md](LICENSE-SCOPE.md)，第三方与上游版权声明见 [NOTICE.txt](NOTICE.txt)。
- **不冒充官方 Java**：本项目名称是 ChineseJava，不是 "Java"，也不使用 Oracle 的商标；
  中文拼写是本项目的加法，与 Oracle/OpenJDK 官方无关。


---

## 跑判据会写盘（2026-10-11 审计后补）

* 各批判据（`tests\跑批*判据.ps1`）会在 **`构建日志\批N-<时间>\`** 下建工作目录：编译产物、生成的源码、诊断原文都放那里；
* `verify.ps1` 第 4 节的**判据自测**会**临时修改** `tools\关键字表.tsv`（把 class 的中文改成单字「类」）再还原；
  现在有一条判据证明它**逐字节还原**（SHA256 一致）——跑完自检后表不会被悄悄改坏；
* 只读环境（CI / 独立审计）请用 `pwsh -File verify.ps1 -跳过自测`，并接受 `构建日志\` 会被写入。
## 仓库结构

```
README.md / 常见问题.md      使用说明
verify.ps1                   用户侧自检（25 项：环境 / 表↔产物 / 4 套判据 / 元判据 / 判据自测）
install.ps1                  把构建出的镜像装成可用发行目录
tools/                       唯一真相的表 + 生成器 + 构建/测试入口
tests/                       判据套件（跑批1 诊断 / 2b 软关键字 / 4 命名空间不变式 / 5 关键字穷举）
docs/                        台账与记录（判据记录、硬边界台账、构建环境台账、口径变更）
examples/                    中文示例（中英对照）
patches/                     我们对上游 OpenJDK 的**全部**改动（本仓库不含 OpenJDK 源码）
LICENSE / NOTICE.txt         许可与改动清单（GPLv2 + Classpath Exception）
```

**本仓库不含 OpenJDK 源码**（`jdk/` 在 `.gitignore` 里）。要自己构建：

```powershell
git clone https://github.com/openjdk/jdk.git jdk
cd jdk; git checkout 98540582000172a16087d15b650b80caa505c5b7; cd ..
(Get-Content patches\README.md)   # 按里面的步骤应用补丁
pwsh tools\构建.ps1               # 需要 MSYS2 + VS2022 + boot JDK 27（见 docs\构建环境台账.md）
pwsh verify.ps1                   # 25 项自检
```