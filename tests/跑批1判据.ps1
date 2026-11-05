# 跑批1判据.ps1 —— 批 1（L1 诊断汉化）判据套件
#
#   用法：pwsh -File tests\跑批1判据.ps1 [-Jdk <镜像路径>]
#
# 判据（每条都能失败；失败即退出码 1）：
#   K1-1 覆盖（Σ 口径）：16 个主包 en-only 键数 = 0；并报出"有意留英"（值逐字等于英文）条数
#   K1-2 前缀双跑：默认输出英文前缀 error:；设开关后输出中文前缀 错误:
#   K1-3 术语↔产物：生成器 -Check 通过；批注/简名/single-type-import 在产物里为 0，替换词已生效
#   K1-4 前缀落点唯一性：3 个前缀键在 jdk 的 *.java 里只出现在 AbstractDiagnosticFormatter
#   K1-5 真编译：含"注解"的诊断真的出现中文新词；15 条缺键都在产物里
#   K1-7 一键回英文：-J-Duser.language=en 时正文与前缀全英文
#   K1-8 差异台账对拍：与 git HEAD（上游原文）逐键比对，新增/覆盖 计数必须等于台账数字

param([string]$Jdk = '')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
$jdkDir = Join-Path $root 'jdk'
if (-not $Jdk) { $Jdk = Join-Path $jdkDir 'build\cnjava\images\jdk' }
$javac = Join-Path $Jdk 'bin\javac.exe'
if (-not (Test-Path $javac)) { Write-Host "[FAIL] 找不到 javac：$javac" -ForegroundColor Red; exit 1 }

$工作 = Join-Path $root ("构建日志\批1-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory $工作 -Force | Out-Null
$script:通过 = 0; $script:失败 = 0
function 好($m) { Write-Host "  [ok]   $m" -ForegroundColor Green; $script:通过++ }
function 坏($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red;   $script:失败++ }

$主包 = @(
    'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\compiler.properties',
    'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\javac.properties',
    'src\java.base\share\classes\sun\launcher\resources\launcher.properties',
    'src\jdk.javadoc\share\classes\jdk\javadoc\internal\tool\resources\javadoc.properties',
    'src\jdk.javadoc\share\classes\jdk\javadoc\internal\doclets\toolkit\resources\doclets.properties',
    'src\jdk.javadoc\share\classes\jdk\javadoc\internal\doclets\formats\html\resources\standard.properties',
    'src\jdk.javadoc\share\classes\jdk\javadoc\internal\doclint\resources\doclint.properties',
    'src\jdk.jshell\share\classes\jdk\internal\jshell\tool\resources\l10n.properties',
    'src\jdk.jdeps\share\classes\com\sun\tools\jdeps\resources\jdeps.properties',
    'src\jdk.jartool\share\classes\sun\tools\jar\resources\jar.properties',
    'src\jdk.jartool\share\classes\sun\security\tools\jarsigner\resources\jarsigner.properties',
    'src\jdk.jlink\share\classes\jdk\tools\jlink\resources\jlink.properties',
    'src\jdk.jlink\share\classes\jdk\tools\jmod\resources\jmod.properties',
    'src\jdk.jconsole\share\classes\sun\tools\jconsole\resources\messages.properties',
    'src\jdk.jpackage\share\classes\jdk\jpackage\internal\resources\MainResources.properties',
    'src\java.base\share\classes\sun\security\tools\keytool\resources\keytool.properties'
)

function 读键值文本([string]$文本) {
    # 注意：properties 的键**大小写敏感**（doclets 里同时有 doclet.AnnotationTypes 与 doclet.annotationtypes），
    # 所以必须用大小写敏感的字典，不能用 PowerShell 默认的 @{} / [ordered]@{}。
    $out = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $行 = $文本 -split "`r?`n"
    $i = 0
    while ($i -lt $行.Count) {
        $l = $行[$i]
        if ($l -match '^\s*[#!]' -or $l -notmatch '\S') { $i++; continue }
        if ($l -match '^([A-Za-z0-9\.\-_]+)\s*=\s*(.*)$') {
            $k = $matches[1]; $v = $matches[2]
            $逻辑 = $v -replace '\\\s*$', ''
            while ($v -match '\\\s*$' -and ($i + 1) -lt $行.Count) {
                $i++
                $v = $行[$i]
                $逻辑 += (($v -replace '\\\s*$', '').TrimStart())
            }
            $out[$k] = $逻辑
        }
        $i++
    }
    return $out
}
function 读键值([string]$路径) { return 读键值文本 ([IO.File]::ReadAllText($路径, [Text.Encoding]::UTF8)) }

Write-Host "=== ChineseJava 批 1 判据（诊断汉化）===" -ForegroundColor Cyan
Write-Host "镜像：$Jdk"

# ---------------------------------------------------------------- K1-1
Write-Host "`n-- K1-1 覆盖（Σ 口径）--"
$缺口合计 = 0; $留英合计 = 0; $明细 = @()
foreach ($rel in $主包) {
    $en = 读键值 (Join-Path $jdkDir $rel)
    $zh = 读键值 (Join-Path $jdkDir ($rel -replace '\.properties$', '_zh_CN.properties'))
    $缺 = @($en.Keys | Where-Object { -not $zh.ContainsKey($_) })
    $留 = @($en.Keys | Where-Object { $zh.ContainsKey($_) -and ([string]$zh[$_] -eq [string]$en[$_]) })
    $缺口合计 += $缺.Count
    $留英合计 += $留.Count
    $明细 += [pscustomobject]@{ 包 = ($rel -split '\\')[1]; 英文键 = $en.Keys.Count; 缺口 = $缺.Count; 有意留英 = $留.Count }
}
$明细 | Format-Table -AutoSize | Out-String | Write-Host
if ($缺口合计 -eq 0) { 好 "16 个主包缺口合计 Σ = 0（口径：逐包 en-only 相加）" }
else { 坏 "仍有缺口 Σ = $缺口合计" }
好 "有意留英（值逐字等于英文，登记为豁免而非缺口）合计 = $留英合计"

# ---------------------------------------------------------------- K1-2
Write-Host "`n-- K1-2 前缀双跑 --"
$t = Join-Path $工作 '前缀'
New-Item -ItemType Directory $t -Force | Out-Null
Set-Content "$t\坏.java" "public class 坏 { void f() { int x = `"s`"; } }" -Encoding utf8NoBOM
$默认 = (& $javac -d "$t\o1" "$t\坏.java" 2>&1) -join "`n"
# 注意：PowerShell 会把内联的 -J-Da.b.c=v 拆坏（实测 "无效的标记: .diagnostics.prefix=zh"），
# 所以这里用环境变量形式（对用户也最稳，见 常见问题.md）。
$env:CHINESEJAVA_PREFIX = 'zh'
$中文 = (& $javac -d "$t\o2" "$t\坏.java" 2>&1) -join "`n"
Remove-Item Env:\CHINESEJAVA_PREFIX
$默认 | Set-Content "$工作\K1-2-默认.txt" -Encoding utf8NoBOM
$中文 | Set-Content "$工作\K1-2-中文开关.txt" -Encoding utf8NoBOM
if ($默认 -match ': error: ' -and $默认 -notmatch '错误: ') { 好 "默认前缀是英文：$(($默认 -split "`n")[0].Trim())" }
else { 坏 "默认前缀不是英文：$(($默认 -split "`n")[0].Trim())" }
if ($中文 -match '错误: ' -and $中文 -notmatch ': error: ') { 好 "开关打开后前缀是中文：$(($中文 -split "`n")[0].Trim())" }
else { 坏 "开关未生效：$(($中文 -split "`n")[0].Trim())" }

# ---------------------------------------------------------------- K1-3
Write-Host "`n-- K1-3 术语 ↔ 产物 --"
& pwsh -NoProfile -File (Join-Path $root 'tools\生成诊断汉化.ps1') -Check *> "$工作\K1-3-生成器.txt"
if ($LASTEXITCODE -eq 0) { 好 "生成器 -Check 通过（产物与表一致）" } else { 坏 "生成器 -Check 未通过（见 K1-3-生成器.txt）" }
$compilerZh = Get-Content (Join-Path $jdkDir 'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\compiler_zh_CN.properties') -Raw -Encoding UTF8
foreach ($对 in @(@('批注', 0), @('简名', 0), @('single-type-import', 0))) {
    $n = ([regex]::Matches($compilerZh, [regex]::Escape($对[0]))).Count
    if ($n -eq $对[1]) { 好 "产物里「$($对[0])」出现 $n 次（应为 $($对[1])）" } else { 坏 "产物里「$($对[0])」出现 $n 次，应为 $($对[1])" }
}
foreach ($词 in @('注解', '简单名', '单类型导入')) {
    $n = ([regex]::Matches($compilerZh, [regex]::Escape($词))).Count
    if ($n -gt 0) { 好 "新术语「$词」出现 $n 次" } else { 坏 "新术语「$词」没出现" }
}

# ---------------------------------------------------------------- K1-4
Write-Host "`n-- K1-4 前缀落点唯一性 --"
$命中 = & git -C $jdkDir grep -l -e 'compiler\.err\.error"' -e 'compiler\.warn\.warning"' -e 'compiler\.note\.note"' -- '*.java' 2>$null
$命中 = @($命中 | Where-Object { $_ -match '\.java$' })
if ($命中.Count -eq 1 -and $命中[0] -match 'AbstractDiagnosticFormatter') { 好 "3 个前缀键只被 1 个 .java 引用：$($命中[0])" }
else { 坏 "前缀键引用面不止一处：$($命中 -join ' / ')" }

# ---------------------------------------------------------------- K1-5
Write-Host "`n-- K1-5 真编译（含「注解」的新词）--"
Set-Content "$t\探针.java" "@FunctionalInterface`npublic class 探针 { }" -Encoding utf8NoBOM
$o = (& $javac -d "$t\o3" "$t\探针.java" 2>&1) -join "`n"
$o | Set-Content "$工作\K1-5-注解.txt" -Encoding utf8NoBOM
if ($o -match '注解' -and $o -notmatch '批注') { 好 "真编译输出用新术语：$(($o -split "`n") | Where-Object { $_ -match '错误|注解' } | Select-Object -First 1)" }
else { 坏 "输出未使用新术语或仍含「批注」：$o" }
$缺 = @('compiler.misc.missing.case','compiler.misc.feature.value.classes','compiler.warn.value.finalize','compiler.misc.type.req.identity','javac.opt.preview-mode')
$kv = 读键值 (Join-Path $jdkDir 'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\compiler_zh_CN.properties')
$javacKv = 读键值 (Join-Path $jdkDir 'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\javac_zh_CN.properties')
$缺的 = @()
foreach ($k in $缺) { if (-not ($kv.ContainsKey($k) -or $javacKv.ContainsKey($k))) { $缺的 += $k } }
if ($缺的.Count -eq 0) { 好 "抽查的缺键都已在产物里" } else { 坏 "缺键仍缺：$($缺的 -join ', ')" }

# ---------------------------------------------------------------- K1-7
Write-Host "`n-- K1-7 一键回英文 --"
# 同样避开内联 -J 的 PowerShell 坑：用数组 splat（等价于命令行里逐个参数）
$英参数 = @('-J-Duser.language=en', '-J-Duser.country=US', '-d', "$t\o4", "$t\探针.java")
$英 = (& $javac @英参数 2>&1) -join "`n"
$英 | Set-Content "$工作\K1-7-英文.txt" -Encoding utf8NoBOM
$像诊断 = ($英 -match 'error: ') -and ($英 -match '(annotation|incompatible|expected|symbol)') -and ($英 -notmatch '无效的标记|invalid flag')
if ($像诊断 -and $英 -notmatch '注解') { 好 "回英文生效（真诊断，不是参数报错）：$(($英 -split "`n") | Where-Object { $_ -match 'error:' } | Select-Object -First 1)" }
else { 坏 "回英文未生效或输出不是真诊断：$英" }

# ---------------------------------------------------------------- K1-8
Write-Host "`n-- K1-8 差异台账对拍（对 git HEAD 上游原文）--"
$新增实 = 0; $覆盖实 = 0
# 注意：既要算**已跟踪文件的改动**，也要算**我们新增的未跟踪 properties**
# （前缀开关键住在自建包 chinesejava.properties 里，git diff 看不到未跟踪文件）。
# 收集我们碰过的所有 properties（含英文侧：补缺表里状态为「我方新增」的键中英两侧都写）
$全部属性 = @()
$全部属性 += @(& git -C $jdkDir diff --name-only -- '*.properties' 2>$null)
$全部属性 += @(& git -C $jdkDir ls-files --others --exclude-standard -- '*.properties' 2>$null)
$改的文件 = @($全部属性 | Where-Object { $_ } | Sort-Object -Unique)
$新增集 = New-Object System.Collections.Generic.HashSet[string]
$覆盖集 = New-Object System.Collections.Generic.HashSet[string]
foreach ($rel in $改的文件) {
    $头 = (& git -C $jdkDir show "HEAD:$rel" 2>$null) -join "`n"
    $原文 = 读键值文本 $头
    $现在 = 读键值 ([IO.Path]::Combine($jdkDir, ($rel -replace '/', '\')))
    foreach ($k in $现在.Keys) {
        if (-not $原文.ContainsKey($k)) { [void]$新增集.Add($k) }
        elseif ([string]$原文[$k] -ne [string]$现在[$k]) { [void]$覆盖集.Add($k) }
    }
}
# 同一个键可能同时出现在英文基础包与 _zh_CN 包里 ⇒ 按**去重键**计（与生成器台账口径一致）
$覆盖集.ExceptWith($新增集)
$新增实 = $新增集.Count; $覆盖实 = $覆盖集.Count
$台账文本 = Get-Content (Join-Path $root 'docs\诊断差异台账.md') -Raw -Encoding UTF8
$m = [regex]::Match($台账文本, '\|\s*\*\*合计\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|\s*\*\*(\d+)\*\*')
$台新增 = [int]$m.Groups[1].Value; $台覆盖 = [int]$m.Groups[2].Value
Write-Host "  实测：新增 $新增实 ｜ 覆盖 $覆盖实 ；台账：新增 $台新增 ｜ 覆盖 $台覆盖"
if ($新增实 -eq $台新增 -and $覆盖实 -eq $台覆盖) { 好 "台账与实际改动逐项一致" }
else { 坏 "台账与实际不符（新增 实测$新增实 vs 台账$台新增；覆盖 实测$覆盖实 vs 台账$台覆盖）" }

# ---------------------------------------------------------------- K1-9
Write-Host "`n-- K1-9 硬关键字误用的专属消息（照上游 assert/enum 范式；英文侧必须不变）--"
# 覆盖：NAMED 类 token 走 token.name()；结构性关键字（Tag.DEFAULT，token 不保留拼写）按位置回读源码。
$覆盖面 = @('布尔', '整数', '真值', '空值', '类型', '如果', '返回', '抽象', '对于')
$专属数 = 0
foreach ($kw in $覆盖面) {
    Set-Content "$t\误用_$kw.java" "公开 类型 甲 { 整数 $kw = 1; }" -Encoding utf8NoBOM
    $o = (& $javac -XDrawDiagnostics -d "$t\o9" "$t\误用_$kw.java" 2>&1) -join "`n"
    if ($o -match 'compiler\.err\.chinesejava\.keyword') { $专属数++ } else { Write-Host "        （$kw 未走专属消息：$o）" -ForegroundColor DarkYellow }
}
if ($专属数 -eq $覆盖面.Count) { 好 "$($覆盖面.Count) 个中文硬关键字（含结构性：类型/如果/返回/…）都给专属消息" }
else { 坏 "只有 $专属数/$($覆盖面.Count) 个走了专属消息" }
$o文本 = (& $javac -d "$t\o10" "$t\误用_真值.java" 2>&1) -join "`n"
if ($o文本 -match '是 ChineseJava 关键字, 不能用作标识符') { 好 "消息正文可读：$(($o文本 -split "`n") | Where-Object { $_ -match '错误' } | Select-Object -First 1)" }
else { 坏 "消息正文不符：$o文本" }
# 软关键字（导出=exports）本来就能当标识符 ⇒ **不该**给"不能用作标识符"的提示；如实断言不放宽
Set-Content "$t\软.java" "公开 类型 甲 { 整数 导出 = 1; }" -Encoding utf8NoBOM
$o软 = (& $javac -XDrawDiagnostics -d "$t\o12" "$t\软.java" 2>&1) -join "`n"
if ($o软 -notmatch 'chinesejava\.keyword') { 好 "软关键字（导出）不给该提示（它本来就能当标识符）" }
else { 坏 "软关键字被误判成硬关键字：$o软" }
# 中文正常程序必须照常编译（提示分支不许误伤）
Set-Content "$t\正常.java" "公开 类型 正常 { 公开 静态 空型 main(String[] 参数) { 整数 甲 = 1; 返回; } }" -Encoding utf8NoBOM
& $javac -d "$t\o13" "$t\正常.java" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { 好 "中文正常程序照常编译通过（提示分支不误伤）" } else { 坏 "中文正常程序编译失败" }

# 英文基线：英文关键字误用必须与**未汉化的 boot JDK**逐字一致（且不崩）
$boot = 'E:\java\jdk-27\bin\javac.exe'
Set-Content "$t\英误用.java" "public class 英误用 { int class = 1; }" -Encoding utf8NoBOM
$英参数 = @('-J-Duser.language=en', '-J-Duser.country=US', '-XDrawDiagnostics', '-d', "$t\o7", "$t\英误用.java")
$我们 = (& $javac @英参数 2>&1) -join "`n"
if (Test-Path $boot) {
    $官方 = (& $boot @英参数 2>&1) -join "`n"
    $我们 | Set-Content "$工作\K1-9-英文基线-我们.txt" -Encoding utf8NoBOM
    $官方 | Set-Content "$工作\K1-9-英文基线-官方.txt" -Encoding utf8NoBOM
    if ($我们 -match 'UnsupportedOperationException|exception has occurred') { 坏 "英文侧把 javac 打崩了（历史真 bug：标点 token 调 name()）" }
    elseif ($我们 -eq $官方) { 好 "英文关键字误用：我们的 javac 与 boot JDK 输出**逐字一致**" }
    else { 坏 "英文基线不一致：`n    我们：$我们`n    官方：$官方" }
} else { 坏 "找不到 boot JDK：$boot" }

# ---------------------------------------------------------------- 汇总
Write-Host "`n=== 汇总：通过 $script:通过 项，失败 $script:失败 项 ===" -ForegroundColor Cyan
Write-Host "工作目录：$工作"
if ($script:失败 -gt 0) { exit 1 }
exit 0
