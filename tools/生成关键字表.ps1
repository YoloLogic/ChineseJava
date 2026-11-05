# 生成关键字表.ps1 —— 从唯一真相 tools\关键字表.tsv 生成 docs\中文关键字表.md
#
#   用法：pwsh -File tools\生成关键字表.ps1              # 校验 + 生成
#          pwsh -File tools\生成关键字表.ps1 -Check       # 只校验（守卫/批检用，不改文件）
#          pwsh -File tools\生成关键字表.ps1 -SkipScan    # 跳过 jdk 树冲突扫描（快）
#
# 设计口径：
#   * 表（TSV）是唯一真相；本脚本是唯一的写出者；.md 是生成物，禁止手改。
#   * 路径全部从脚本位置推出来，不写死。
#   * 判据能失败：字数/唯一性/类别/冲突 任一违规 ⇒ 退出码 1。

param(

    [switch]$Check,
    [switch]$SkipScan
)

# ChineseJava：产物比较口径（审计 4.4 后定）
#   ① 写盘一侧统一用 [IO.File]::WriteAllText 直写（LF、不补行尾）⇒ 产物是确定的
#   ② 比较时只把 CRLF 归一成 LF，然后**逐字节** -ceq 比
#   ⇒ 「手改产物」包括**追加空行/空格**都会被抓住（旧口径 TrimEnd() 会把这类改动吃掉）
function 同产物([string]$盘上, [string]$期望) {
    return (($盘上 -replace "`r`n", "`n") -ceq ($期望 -replace "`r`n", "`n"))
}


$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root   = Split-Path -Parent $PSScriptRoot          # 工程根
$tsv    = Join-Path $PSScriptRoot '关键字表.tsv'
$outMd  = Join-Path $root 'docs\中文关键字表.md'
$jdkDir = Join-Path $root 'jdk'

$类别集 = @('保留', '字面量', '上下文', '特例', '预览', '不译')
$强度集 = @('硬', '软', '不译')
$出处集 = @('C++', 'Py', '双', '新')
$汉字   = '[\u4e00-\u9fff]'

if (-not (Test-Path $tsv)) { throw "找不到表文件：$tsv" }

# ---------- 一、读表 ----------
$rows = New-Object System.Collections.Generic.List[object]
$行号 = 0
foreach ($line in (Get-Content $tsv -Encoding UTF8)) {
    $行号++
    if ($line -match '^\s*#') { continue }
    if ($line -match '^\s*$') { continue }
    $f = $line -split "`t"
    if ($f.Count -lt 5) { throw "第 $行号 行字段不足（至少 5 列）：$line" }
    $备注 = ''
    if ($f.Count -ge 6) { $备注 = $f[5].Trim() }
    $rows.Add([pscustomobject]@{
        英文 = $f[0].Trim(); 中文 = $f[1].Trim(); 类别 = $f[2].Trim()
        强度 = $f[3].Trim(); 出处 = $f[4].Trim(); 备注 = $备注
    })
}

# ---------- 二、校验 ----------
$错 = New-Object System.Collections.Generic.List[string]
foreach ($r in $rows) {
    if ($类别集 -notcontains $r.类别) { $错.Add("类别非法：$($r.英文) = $($r.类别)") }
    if ($强度集 -notcontains $r.强度) { $错.Add("强度非法：$($r.英文) = $($r.强度)") }
    if ($出处集 -notcontains $r.出处) { $错.Add("出处非法：$($r.英文) = $($r.出处)") }
    if ($r.中文 -ne '不译') {
        $c = ([regex]::Matches($r.中文, $汉字)).Count
        if ($c -lt 2 -or $c -gt 6) { $错.Add("字数违规（$c 个汉字，要求 2–6，按汉字数算不按 len）：$($r.英文) = $($r.中文)") }
        if ($r.中文.Length -ne $c)  { $错.Add("含非汉字字符：$($r.英文) = $($r.中文)") }
    }
}
foreach ($g in ($rows | Group-Object 中文 | Where-Object { $_.Count -gt 1 })) { $错.Add("中文重复：$($g.Name) × $($g.Count)") }
foreach ($g in ($rows | Group-Object 英文 | Where-Object { $_.Count -gt 1 })) { $错.Add("英文重复：$($g.Name) × $($g.Count)") }

# ---------- 三、冲突扫描（中文词 × 上游源码标识符）----------
$扫描数 = 0
if (-not $SkipScan) {
    if (-not (Test-Path $jdkDir)) {
        $错.Add("找不到上游树：$jdkDir")
    } else {
        # 口径（写死，不许含糊；口径演进史见 docs\判据记录.md）：
        #   1) **上游未改动的 *.java**：整行口径（不剥注释）—— 上游是纯英文，出现中文拼写即真冲突（实测 0）。
        #   2) **我们改过 / 新增的 *.java**：只在**标识符位置**算冲突 —— 需要剥掉
        #      跨行块注释（/* … */）、行注释（//）、字符串与字符字面量；因为这些文件里有我们写的中文注释。
        #   3) **我方产品源码 `zhstdlib/`**：同上（剥净后判定）。
        #   4) 显式豁免：表产物 `ZhKeywords.java`。
        #   5) **`tests/` 与 `examples/` 不在扫描范围内** —— 判据用例与示例天然必须写出这些拼写；
        #      它们的把关方式是「用我们自己编出的 JDK 编过 + 中英对拍」，见 docs\判据记录.md。
        #   6) 我方 *.ps1 / *.md / *.txt **不算** —— 生成器与文档就是描述本特性的文字。

        # 剥净器：按行跟踪跨行块注释状态，然后去字符串/字符字面量、再去行注释
        function 剥净文件([string]$路径) {
            $结果 = New-Object System.Collections.Generic.List[string]
            $inBlock = $false
            foreach ($l in [IO.File]::ReadAllLines($路径, [Text.Encoding]::UTF8)) {
                $t = $l
                if ($inBlock) {
                    $idx = $t.IndexOf('*/')
                    if ($idx -ge 0) { $inBlock = $false; $t = $t.Substring($idx + 2) } else { $结果.Add(''); continue }
                }
                while ($true) {
                    $i1 = $t.IndexOf('/*')
                    if ($i1 -lt 0) { break }
                    $i2 = $t.IndexOf('*/', $i1 + 2)
                    if ($i2 -ge 0) { $t = $t.Substring(0, $i1) + ' ' + $t.Substring($i2 + 2) }
                    else { $inBlock = $true; $t = $t.Substring(0, $i1); break }
                }
                $t = [regex]::Replace($t, '"(?:\\.|[^"\\])*"', '""')
                $t = [regex]::Replace($t, "'(?:\\.|[^'\\])*'", "''")
                $i3 = $t.IndexOf('//')
                if ($i3 -ge 0) { $t = $t.Substring(0, $i3) }
                $结果.Add($t)
            }
            return $结果
        }

        $我们改过 = @(& git -C $jdkDir diff --name-only -- '*.java' 2>$null)
        $我们新增 = @(& git -C $jdkDir ls-files --others --exclude-standard -- '*.java' 2>$null)
        $排除 = @(':!src/jdk.compiler/share/classes/com/sun/tools/javac/parser/ZhKeywords.java')
        foreach ($x in ($我们改过 + $我们新增)) { if ($x) { $排除 += ":!$x" } }

        # 2) 我们改过 / 新增的 *.java → 剥净后按行判定（缓存一次，71 个词共用）
        $我方缓存 = @{}
        foreach ($rel in ($我们改过 + $我们新增)) {
            if (-not $rel) { continue }
            if ($rel -like '*ZhKeywords.java') { continue }
            $f = Join-Path $jdkDir ($rel -replace '/', '\')
            if (Test-Path $f) { $我方缓存[$rel] = 剥净文件 $f }
        }
        foreach ($sub in @('zhstdlib')) {
            $p = Join-Path $root $sub
            if (Test-Path $p) {
                foreach ($f in (Get-ChildItem $p -Recurse -File -Include '*.java' -ErrorAction SilentlyContinue)) {
                    $我方缓存[$f.FullName] = 剥净文件 $f.FullName
                }
            }
        }

        foreach ($r in ($rows | Where-Object { $_.中文 -ne '不译' })) {
            $扫描数++
            $命中 = @()
            # 1) 上游未改文件：整行口径
            foreach ($h in @(& git -C $jdkDir grep -n -F -e $r.中文 -- '*.java' @排除 2>$null)) {
                $命中 += "上游 $h"
            }
            # 2/3) 我们改过/新增/产品源码：剥净后的标识符口径
            foreach ($k in $我方缓存.Keys) {
                $i = 0
                foreach ($行 in $我方缓存[$k]) {
                    $i++
                    if ($行 -match [regex]::Escape($r.中文)) {
                        $命中 += "$([IO.Path]::GetFileName($k)):$i"
                    }
                }
            }
            if ($命中.Count -gt 0) {
                $样例 = (($命中 | Select-Object -First 3) -join ' / ')
                $错.Add("冲突（标识符位置）：$($r.中文)（$($r.英文)）出现 $($命中.Count) 处 → $样例")
            }
        }
    }
}

if ($错.Count -gt 0) {
    Write-Host "[FAIL] 表校验未通过，共 $($错.Count) 条：" -ForegroundColor Red
    $错 | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# ---------- 四、统计 ----------
$硬 = @($rows | Where-Object { $_.强度 -eq '硬' })
$软 = @($rows | Where-Object { $_.强度 -eq '软' })
$保留 = @($rows | Where-Object { $_.类别 -eq '保留' })
$字面量 = @($rows | Where-Object { $_.类别 -eq '字面量' })
$上下文 = @($rows | Where-Object { $_.类别 -eq '上下文' })
$特例 = @($rows | Where-Object { $_.类别 -eq '特例' })
$预览 = @($rows | Where-Object { $_.类别 -eq '预览' })
$不译 = @($rows | Where-Object { $_.类别 -eq '不译' })

function 表($标题, $集合) {
    $o = @()
    $o += "### $标题（$(($集合 | Measure-Object).Count) 个）"
    $o += ''
    $o += '| 英文 | 中文 | 强度 | 出处 | 备注 |'
    $o += '|---|---|---|---|---|'
    foreach ($r in $集合) { $o += "| ``$($r.英文)`` | **$($r.中文)** | $($r.强度) | $($r.出处) | $($r.备注) |" }
    $o += ''
    return $o
}

# ---------- 五、生成 ----------
$md = @()
$md += '# ChineseJava 中文关键字表'
$md += ''
$md += '> 本文件由 `tools\生成关键字表.ps1` 从唯一真相 `tools\关键字表.tsv` **生成** —— 不要手改。'
$md += '> 改表只改 TSV，再重跑生成器；守卫用 `-Check` 核对（手改或不重跑都会被抓出来）。'
$md += ''
$md += '**中英两种写法都可以用，而且可以混着写。中文不是替换英文，是并列多出来的一种拼写。**'
$md += ''
$md += '## 一、总数（口径写死）'
$md += ''
$md += '| 口径 | 个数 | 构成 |'
$md += '|---|---|---|'
$md += "| 表内总行数 | $($rows.Count) | 含「不译」1 行 |"
$md += "| **硬关键字**（占标识符空间） | **$($硬.Count)** | 保留 $($保留.Count) + 字面量 $($字面量.Count) |"
$md += "| **软关键字**（位置敏感，不占标识符空间） | **$($软.Count)** | 上下文 $($上下文.Count) + 特例 $($特例.Count) + 预览 $($预览.Count) |"
$md += "| 不译 | $($不译.Count) | 单字符符号不是词 |"
$md += "| 可命名的中文拼写位 | $($硬.Count + $软.Count) | 硬 + 软 |"
$md += ''
$md += '## 二、保留关键字（JLS 3.9，硬）'
$md += ''
$md += 表 '保留关键字' $保留
$md += '## 三、字面量（JLS 3.10，硬 —— 镜像 Java 现状，非加严）'
$md += ''
$md += 表 '字面量' $字面量
$md += '## 四、上下文关键字（JLS 3.9 注，软）'
$md += ''
$md += 表 '上下文关键字' $上下文
$md += '## 五、特例与预览（软）'
$md += ''
$md += 表 '特例与预览' (@($特例) + @($预览))
$md += '## 六、不译'
$md += ''
$md += 表 '不译' $不译
$md += '## 七、两份清单（守卫直接按此列筛）'
$md += ''
$md += "### 硬关键字占用清单（$($硬.Count) 个中文词，从此不能当变量/方法/类名）"
$md += ''
$md += (($硬 | ForEach-Object { $_.中文 }) -join '、')
$md += ''
$md += "### 软关键字清单（$($软.Count) 个，不占标识符空间，仍可当标识符用）"
$md += ''
$md += (($软 | ForEach-Object { $_.中文 }) -join '、')
$md += ''
$md += '## 八、定则与裁定记录'
$md += ''
$md += '**R1（跨语言词位）**：同一门语言内禁止撞词；跨语言可复用同一概念词。'
$md += ''
$md += '- `open` / `opens` → `开放` / `开放包`：两个不同的 Java 关键字，会同时出现在同一个 `module-info.java` 里 ⇒ 必须拆。'
$md += '- `exports` → `导出`：跨语言复用 C++ 的 `export`（同一概念，且分属两种语言、永不共存）。'
$md += '- `uses` → `使用`：跨语言重词（C++ `using`、Python `with` 亦为「使用」），已登记为记账项。'
$md += ''
$md += '**R2（字数）**：每个中文拼写必须 2–6 个**汉字**（按汉字数算，不按 `len()`），唯一、可切分。'
$md += ''
$md += '**R3（强度镜像）**：强度照抄 JLS 分类 —— 保留关键字硬、上下文关键字/受限标识符软、`_` 不译；字面量按 Java 现状亦为硬。'
$md += ''
$md += '**R4（同词根两词要加限定）**：`final`→`最终` / `finally`→`最终必须`；`throw`→`抛出` / `throws`→`声明抛出`。'
$md += ''
$md += '**R5（一个中文词只服务一个英文概念）**：C++ 的 `requires` 已占 `约束`，Java 的模块依赖改用 `依赖`。'
$md += ''
$md += ('**生成时间口径**：本表由生成器生成，内容只依赖 `tools\关键字表.tsv` 与上游树，不含时间戳（保证 `-Check` 可复现）。')
$md += ''

$内容 = ($md -join "`r`n")

# ---------- 六、Java 侧产物（词法层别名表）----------
$outJava = Join-Path $jdkDir 'src\jdk.compiler\share\classes\com\sun\tools\javac\parser\ZhKeywords.java'
$jv = New-Object System.Collections.Generic.List[string]
$jv.Add('/*')
$jv.Add(' * ChineseJava —— 中文关键字拼写表（OpenJDK 派生作品，许可 GPLv2 + Classpath Exception）')
$jv.Add(' *')
$jv.Add(' * 本文件由生成器生成：tools\生成关键字表.ps1')
$jv.Add(' * 唯一真相：tools\关键字表.tsv —— 禁止手改本文件；要改就改表，然后重跑生成器。')
$jv.Add(' */')
$jv.Add('')
$jv.Add('package com.sun.tools.javac.parser;')
$jv.Add('')
$jv.Add('/**')
$jv.Add(' * ChineseJava：中文关键字拼写表。')
$jv.Add(' *')
$jv.Add(' * 中文不是替换英文，是并列多出来的一种拼写：中文拼写命中后仍回落到**完全未改动**的英文原表，')
$jv.Add(' * 因此中英两种写法产生同一个 token、同一份字节码。')
$jv.Add(' *')
$jv.Add(' * 交替存放：{ 中文, 英文关键字, 中文, 英文关键字, ... }')
$jv.Add(' */')
$jv.Add('final class ZhKeywords {')
$jv.Add('    private ZhKeywords() {}')
$jv.Add('')
$jv.Add('    /** 硬关键字：与英文同级保留（占标识符空间）。由 Tokens 构造时挂到 keywords 表上。 */')
$jv.Add('    static final String[] HARD = {')
foreach ($r in $硬) { $jv.Add("        `"$($r.中文)`", `"$($r.英文)`",") }
$jv.Add('    };')
$jv.Add('')
$jv.Add('    /** 软关键字：位置敏感、不占标识符空间，由解析层消费（批 2b）。 */')
$jv.Add('    static final String[] SOFT = {')
foreach ($r in $软) { $jv.Add("        `"$($r.中文)`", `"$($r.英文)`",") }
$jv.Add('    };')
$jv.Add('')
$jv.Add('    /**')
$jv.Add('     * ChineseJava：若给定名字是**硬**关键字的中文拼写，返回它；否则返回 null。')
$jv.Add('     *')
$jv.Add('     * 只查硬关键字：软关键字（记录/密封/自动…）本来就能当标识符，误用不该给提示。')
$jv.Add('     * 用途：解析层报告语法错误时，补一条"这是关键字，不能用作标识符"的可行动提示。')
$jv.Add('     */')
$jv.Add('    static String hardKeyword(String name) {')
$jv.Add('        for (int i = 0; i < HARD.length; i += 2) {')
$jv.Add('            if (HARD[i].equals(name)) {')
$jv.Add('                return name;')
$jv.Add('            }')
$jv.Add('        }')
$jv.Add('        return null;')
$jv.Add('    }')
$jv.Add('}')
$java内容 = ($jv -join "`r`n")

# ---------- 七、写出或核对 ----------
function 比对($路径, $应为, $说明) {
    if (-not (Test-Path $路径)) { Write-Host "[FAIL] 生成物不存在（$说明）：$路径" -ForegroundColor Red; return $false }
    $旧 = (Get-Content $路径 -Raw -Encoding UTF8)
    if (同产物 $旧 $应为) { return $true }
    Write-Host "[FAIL] 生成物与表不一致（表改过但没重跑生成器？）$说明：$路径" -ForegroundColor Red
    $a = $旧 -split "`r?`n"; $b = $应为 -split "`r?`n"
    for ($i = 0; $i -lt [Math]::Max($a.Count, $b.Count); $i++) {
        if ($a[$i] -ne $b[$i]) { Write-Host "  首个差异 行$($i+1)：`n    盘上：$($a[$i])`n    应为：$($b[$i])" -ForegroundColor Red; break }
    }
    return $false
}

if ($Check) {
    $ok1 = 比对 $outMd   $内容     '（说明文档）'
    $ok2 = 比对 $outJava $java内容 '（词法层别名表）'
    if (-not ($ok1 -and $ok2)) { exit 1 }
    Write-Host "[ok] -Check 通过：两处生成物都与表一致（$($rows.Count) 行，硬 $($硬.Count) / 软 $($软.Count)）" -ForegroundColor Green
    exit 0
}

foreach ($p in @($outMd, $outJava)) {
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
[IO.File]::WriteAllText($outMd, $内容, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($outJava, $java内容, (New-Object Text.UTF8Encoding($false)))

Write-Host "[ok] 校验通过 + 已生成两处产物" -ForegroundColor Green
Write-Host "     表行数 $($rows.Count)｜硬 $($硬.Count)（保留 $($保留.Count) + 字面量 $($字面量.Count)）｜软 $($软.Count)（上下文 $($上下文.Count) + 特例 $($特例.Count) + 预览 $($预览.Count)）｜不译 $($不译.Count)"
if ($SkipScan) { Write-Host "     冲突扫描：已跳过（-SkipScan）" } else { Write-Host "     冲突扫描：$扫描数 个中文词 × 上游 *.java，命中 0" }
Write-Host "     生成物 1：$outMd"
Write-Host "     生成物 2：$outJava"
