# patches —— 我们对上游 OpenJDK 的**全部**改动

本仓库**不包含 OpenJDK 源码**（`jdk/` 在 `.gitignore` 里）。派生源码 = 上游 OpenJDK + 本目录。

## 基线

```
commit 98540582000172a16087d15b650b80caa505c5b7
（master，2026-10-10，JDK 28 开发主线）
```

## 内容

| 路径 | 说明 |
|---|---|
| `0001-chinese-java-core.patch` | 对上游已跟踪文件的改动（12 个文件） |
| `new-files/` | 2 个新增文件，按下面路径原样放入 |

新增文件的目标路径：

```
new-files/src/jdk.compiler/share/classes/com/sun/tools/javac/parser/ZhKeywords.java
new-files/src/jdk.compiler/share/classes/com/sun/tools/javac/resources/chinesejava.properties
```

> `ZhKeywords.java` 是**生成物**（由 `tools/生成关键字表.ps1` 从 `tools/关键字表.tsv` 生成）。
> 这里放一份快照，是为了让补丁集自洽；真正改关键字请改 TSV 再重跑生成器，**不要手改它**。

## 怎么应用

```powershell
git clone https://github.com/openjdk/jdk.git
cd jdk
git checkout 98540582000172a16087d15b650b80caa505c5b7

git apply <本仓库>/patches/0001-chinese-java-core.patch
Copy-Item -Recurse -Force <本仓库>/patches/new-files/* .

# 校验：补丁后应剩 12 改 + 2 新增
git status --short
```

然后按 `tools/构建.ps1` 构建（见 `docs/构建环境台账.md` 的前置条件）。

## 许可

本目录下的改动与新增文件随上游采用 **GPLv2 + Classpath Exception**，
详见仓库根的 `NOTICE.txt` 与 `LICENSE-SCOPE.md`。