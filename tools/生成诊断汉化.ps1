# 生成诊断汉化.ps1 —— L1 诊断汉化的唯一写入者
#
#   用法：pwsh -File tools\生成诊断汉化.ps1                # 改写上游 16 个主包的 *_zh_CN.properties
#          pwsh -File tools\生成诊断汉化.ps1 -Check        # 只比对（守卫/批检用，不改文件）
#          pwsh -File tools\生成诊断汉化.ps1 -EmitPatch    # 额外导出 patches\ 下的审阅补丁
#
# 输入（全部是表，脚本不写死内容）：
#   tools\诊断术语表.tsv   —— 术语替换（覆盖上游）/ 前缀 6 条键 / 有意保留的登记
#   tools\诊断补缺表.tsv   —— 上游 zh_CN 缺失的 15 条键及译文
#   jdk 上游树             —— 英文 *_zh_CN.properties 与 *_zh_CN.properties
#
# 产出：
#   ① 上游 16 个主包的 *_zh_CN.properties（就地改写；表是唯一真相，产物禁止手改）
#   ② docs\诊断差异台账.md —— 新增 / 覆盖上游 / 保留上游 三类计数（Σ 口径）
#   ③ 可选 patches\ 下的审阅补丁
#
# 口径：只改「值」，不动键名；未改动的键连原始续行格式一起照抄（保证 diff 最小）。

param(

    [switch]$Check,
    [switch]$EmitPatch
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

$root   = Split-Path -Parent $PSScriptRoot
$jdkDir = Join-Path $root 'jdk'
$术语Tsv = Join-Path $PSScriptRoot '诊断术语表.tsv'
$补缺Tsv = Join-Path $PSScriptRoot '诊断补缺表.tsv'
$台账   = Join-Path $root 'docs\诊断差异台账.md'

# ---------- 16 个主包 ----------
$主包 = @(
    @{ 名 = 'compiler'; 英文 = 'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\compiler.properties' },
    @{ 名 = 'javac'; 英文 = 'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\javac.properties' },
    @{ 名 = 'launcher'; 英文 = 'src\java.base\share\classes\sun\launcher\resources\launcher.properties' },
    @{ 名 = 'javadoc'; 英文 = 'src\jdk.javadoc\share\classes\jdk\javadoc\internal\tool\resources\javadoc.properties' },
    @{ 名 = 'doclets'; 英文 = 'src\jdk.javadoc\share\classes\jdk\javadoc\internal\doclets\toolkit\resources\doclets.properties' },
    @{ 名 = 'standard'; 英文 = 'src\jdk.javadoc\share\classes\jdk\javadoc\internal\doclets\formats\html\resources\standard.properties' },
    @{ 名 = 'doclint'; 英文 = 'src\jdk.javadoc\share\classes\jdk\javadoc\internal\doclint\resources\doclint.properties' },
    @{ 名 = 'l10n'; 英文 = 'src\jdk.jshell\share\classes\jdk\internal\jshell\tool\resources\l10n.properties' },
    @{ 名 = 'jdeps'; 英文 = 'src\jdk.jdeps\share\classes\com\sun\tools\jdeps\resources\jdeps.properties' },
    @{ 名 = 'jar'; 英文 = 'src\jdk.jartool\share\classes\sun\tools\jar\resources\jar.properties' },
    @{ 名 = 'jarsigner'; 英文 = 'src\jdk.jartool\share\classes\sun\security\tools\jarsigner\resources\jarsigner.properties' },
    @{ 名 = 'jlink'; 英文 = 'src\jdk.jlink\share\classes\jdk\tools\jlink\resources\jlink.properties' },
    @{ 名 = 'jmod'; 英文 = 'src\jdk.jlink\share\classes\jdk\tools\jmod\resources\jmod.properties' },
    @{ 名 = 'messages'; 英文 = 'src\jdk.jconsole\share\classes\sun\tools\jconsole\resources\messages.properties' },
    @{ 名 = 'MainResources'; 英文 = 'src\jdk.jpackage\share\classes\jdk\jpackage\internal\resources\MainResources.properties' },
    @{ 名 = 'keytool'; 英文 = 'src\java.base\share\classes\sun\security\tools\keytool\resources\keytool.properties' }
)

# ---------- 一、读表 ----------
$替换 = @()          # @{ 原文; 建议 }
$前缀覆盖 = @{}      # 键 → 值（覆盖上游）
$前缀新增 = @()      # @{ 键; 值 }
foreach ($l in (Get-Content $术语Tsv -Encoding UTF8)) {
    if ($l -match '^\s*#' -or $l -notmatch '\S') { continue }
    $f = $l -split "`t"
    if ($f.Count -lt 5) { continue }
    $类别 = $f[0].Trim(); $原文 = $f[1].Trim(); $建议 = $f[2].Trim(); $处置 = $f[4].Trim()
    if ($类别 -eq '术语' -and $处置 -eq '覆盖上游') { $替换 += [pscustomobject]@{ 原文 = $原文; 建议 = $建议 } }
    elseif ($类别 -eq '前缀' -and $处置 -eq '覆盖上游') { $前缀覆盖[$原文] = $建议 }
    elseif ($类别 -eq '前缀' -and $处置 -eq '新增') { $前缀新增 += [pscustomobject]@{ 键 = $原文; 值 = $建议 } }
}
if ($替换.Count -eq 0) { throw "术语表里没有可用的替换规则" }

$补缺 = @{}          # 键 → @{ 英 = 英文原文; 中 = 中文译文 }
$我方新增键 = New-Object System.Collections.Generic.HashSet[string]
foreach ($l in (Get-Content $补缺Tsv -Encoding UTF8)) {
    if ($l -match '^\s*#' -or $l -notmatch '\S') { continue }
    $f = $l -split "`t"
    if ($f.Count -lt 4) { continue }
    $k = $f[1].Trim()
    $补缺[$k] = [pscustomobject]@{ 英 = $f[2].Trim(); 中 = $f[3].Trim() }
    # 状态列 = 我方新增 ⇒ 这不是上游缺口，而是我们新造的诊断键；**英文侧也必须写**
    # （CreateSymbols 从英文 compiler.properties 生成 Errors/Notes 类，不写就编不过）。
    if ($f.Count -ge 5 -and $f[4].Trim() -eq '我方新增') { [void]$我方新增键.Add($k) }
}
Write-Host "规则：术语替换 $($替换.Count) 条；前缀覆盖 $($前缀覆盖.Count) 条；前缀新增 $($前缀新增.Count) 条；缺键译文 $($补缺.Count) 条"

# 缺键归属哪个包（按键名前缀判定，不写死）
function 归属包([string]$键) {
    if ($键 -like 'compiler.*') { return 'compiler' }
    if ($键 -like 'javac.*') { return 'javac' }
    if ($键 -like 'doclet.*') { return 'standard' }
    if ($键 -like 'launcher.*') { return 'launcher' }
    return ''
}

# ---------- 二、读块（键 + 原始行 + 逻辑值） ----------
function 读块([string]$路径) {
    $行 = @(Get-Content $路径 -Encoding UTF8)
    $块 = New-Object System.Collections.Generic.List[object]
    $i = 0
    while ($i -lt $行.Count) {
        $l = $行[$i]
        if ($l -match '^\s*[#!]' -or $l -notmatch '\S') { $块.Add([pscustomobject]@{ 类型 = '原样'; 行 = @($l) }); $i++; continue }
        if ($l -match '^([A-Za-z0-9\.\-_]+)\s*=\s*(.*)$') {
            $k = $matches[1]; $v = $matches[2]
            $组 = New-Object System.Collections.Generic.List[string]
            $组.Add($l)
            while ($v -match '\\\s*$' -and ($i + 1) -lt $行.Count) {
                $i++
                $组.Add($行[$i])
                $v = $行[$i]
            }
            $逻辑 = ($组[0] -replace '^[A-Za-z0-9\.\-_]+\s*=\s*', '') -replace '\\\s*$', ''
            for ($j = 1; $j -lt $组.Count; $j++) { $逻辑 += (($组[$j] -replace '\\\s*$', '').TrimStart()) }
            $块.Add([pscustomobject]@{ 类型 = '键'; 键 = $k; 行 = $组.ToArray(); 逻辑 = $逻辑 })
            $i++
            continue
        }
        $块.Add([pscustomobject]@{ 类型 = '原样'; 行 = @($l) }); $i++
    }
    return $块
}

# 台账口径用：大小写敏感的文本解析（properties 键大小写敏感）
function 读键值文本([string]$文本) {
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

# ---------- 三、逐包生成 ----------
$账 = New-Object System.Collections.Generic.List[object]
$总新增 = 0; $总覆盖 = 0; $总保留 = 0
$待写 = New-Object System.Collections.Generic.List[object]

foreach ($p in $主包) {
    $英文全 = Join-Path $jdkDir $p.英文
    $中文全 = $英文全 -replace '\.properties$', '_zh_CN.properties'
    if (-not (Test-Path $中文全)) { Write-Host "  [跳过] 没有对应 zh_CN：$($p.名)"; continue }

    $块 = 读块 $中文全
    # properties 键大小写敏感（doclets 里有 doclet.AnnotationTypes 与 doclet.annotationtypes）
    $已有键 = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
    foreach ($b in $块) { if ($b.类型 -eq '键') { $已有键[$b.键] = $true } }

    $出 = New-Object System.Collections.Generic.List[string]
    $覆盖 = 0; $保留 = 0
    foreach ($b in $块) {
        if ($b.类型 -eq '原样') { foreach ($x in $b.行) { $出.Add($x) }; continue }
        $新 = $b.逻辑
        if ($前缀覆盖.ContainsKey($b.键)) { $新 = $前缀覆盖[$b.键] }
        else { foreach ($r in $替换) { $新 = $新.Replace($r.原文, $r.建议) } }
        if ($新 -ne $b.逻辑) {
            $出.Add("$($b.键)=$新")
            $覆盖++
        } else {
            foreach ($x in $b.行) { $出.Add($x) }
            $保留++
        }
    }

    # 补缺键（含前缀新增）
    $新增 = 0
    foreach ($k in $补缺.Keys) {
        if ((归属包 $k) -ne $p.名) { continue }
        if ($已有键.ContainsKey($k)) { continue }
        if ($新增 -eq 0) { $出.Add(''); $出.Add('# ChineseJava：上游 zh_CN 缺失的键（表：tools\诊断补缺表.tsv）') }
        $出.Add("$k=$($补缺[$k].中)")
        $新增++
    }
    foreach ($nf in $前缀新增) {
        # 前缀新增键**不写进上游 bundle**：它们不是诊断正文，单独放自建基础包（见下方“自建资源包”）。
        continue
    }

    # 关键：沿用原文件行尾（上游是 LF），否则整文件都会被算成改动
    $原文本 = Get-Content $中文全 -Raw -Encoding UTF8
    $eol = "`n"; if ($原文本 -match "`r`n") { $eol = "`r`n" }
    $内容 = ($出 -join $eol)

    # ---------- 我方新增键：英文侧也要写 ----------
    $英原文本 = Get-Content $英文全 -Raw -Encoding UTF8
    $英KV0 = 读键值文本 $英原文本
    $英加 = @($我方新增键 | Where-Object { (归属包 $_) -eq $p.名 -and -not $英KV0.ContainsKey($_) })
    $英内容 = $null
    if ($英加.Count -gt 0) {
        $英出 = New-Object System.Collections.Generic.List[string]
        foreach ($l in ($英原文本 -split "`r?`n")) { $英出.Add($l) }
        $英出.Add('')
        $英出.Add('# ChineseJava：我方新增的诊断键（表：tools\诊断补缺表.tsv 里状态为「我方新增」的行）')
        $英出.Add('# 英文侧必须有：CreateSymbols 从本文件生成 Errors/Notes 类；中文侧在对应 _zh_CN.properties 里。')
        foreach ($k in $英加) {
            # CreateSymbols 的**参数类型来自键前面的注释**（`# 0: string, 1: string`），不是从正文数 {n}。
            # 不写这行注释，生成的就会是"无参字段"，调用处 Notes.Xxx(zh) 直接编不过（实测踩过）。
            $参数数 = ([regex]::Matches($补缺[$k].英, '\{\d+\}')).Count
            if ($参数数 -gt 0) {
                $类型注释 = (@(0..($参数数 - 1) | ForEach-Object { "$_`: string" }) -join ', ')
                $英出.Add("# $类型注释")
            }
            $英出.Add("$k=$($补缺[$k].英)")
        }
        $英内容 = ($英出 -join $eol)
    }

    # ---------- 台账口径：始终与 git HEAD（上游原文）比，幂等；**按去重键计** ----------
    $新增集 = New-Object System.Collections.Generic.HashSet[string]
    $覆盖集 = New-Object System.Collections.Generic.HashSet[string]
    $上游Rel = ($p.英文 -replace '\\', '/') -replace '\.properties$', '_zh_CN.properties'
    $上游文本 = $null
    try { $上游文本 = (& git -C $jdkDir show "HEAD:$上游Rel" 2>$null) -join "`n" } catch { $上游文本 = $null }
    if (-not $上游文本) { $上游文本 = $原文本 }
    $上游KV = 读键值文本 $上游文本
    $新KV = 读键值文本 $内容
    $保留x = 0
    foreach ($k in $新KV.Keys) {
        if (-not $上游KV.ContainsKey($k)) { [void]$新增集.Add($k) }
        elseif ([string]$上游KV[$k] -ne [string]$新KV[$k]) { [void]$覆盖集.Add($k) }
        else { $保留x++ }
    }
    if ($英内容) {
        $上游英Rel = $p.英文 -replace '\\', '/'
        $上游英 = $null
        try { $上游英 = (& git -C $jdkDir show "HEAD:$上游英Rel" 2>$null) -join "`n" } catch { $上游英 = $null }
        $上游英KV = 读键值文本 $(if ($上游英) { $上游英 } else { '' })
        foreach ($k in (读键值文本 $英内容).Keys) {
            if (-not $上游英KV.ContainsKey($k)) { [void]$新增集.Add($k) }
            elseif ([string]$上游英KV[$k] -ne [string](读键值文本 $英内容)[$k]) { [void]$覆盖集.Add($k) }
        }
        $覆盖集.ExceptWith($新增集)
    }
    $新增x = $新增集.Count; $覆盖x = $覆盖集.Count
    $账.Add([pscustomobject]@{ 包 = $p.名; 新增 = $新增x; 覆盖 = $覆盖x; 保留 = $保留x })
    $总新增 += $新增x; $总覆盖 += $覆盖x; $总保留 += $保留x
    $待写.Add([pscustomobject]@{ 路径 = $中文全; 内容 = $内容; 包 = $p.名; 原 = $原文本 })
    if ($英内容) { $待写.Add([pscustomobject]@{ 路径 = $英文全; 内容 = $英内容; 包 = "$($p.名)(英文新增)"; 原 = $英原文本 }) }
    Write-Host ("  {0,-14} 新增 {1,3} ｜ 覆盖 {2,3} ｜ 保留 {3,4}（写决策：{4} 处改动{5}）" -f $p.名, $新增x, $覆盖x, $保留x, $覆盖, $(if ($英内容) { "，英文新增 $($英加.Count)" } else { '' }))
}

# ChineseJava：**期望内容**要补末尾换行，且必须在比较与写盘之前、**所有**待写条目都建好之后统一处理。
# 教训（2026-10-11）：① 只在写盘时补换行 ⇒ -Check 拿"没补换行的期望"比"补了换行的盘上"，17 个包全红；
#                    ② 规范化放在自建包加入之前 ⇒ 自建包漏掉规范化，-Check 又红一次。

# ---------- 四、自建资源包（前缀开关键）----------
# 为什么单独一个包：
#   ① 这三个键不是诊断正文，混进上游 compiler.properties / compiler_zh_CN.properties 会污染英文资源；
#   ② 只写进 zh_CN 的话，英文 locale 下 CheckExamples / CheckResourceKeys 都看不见它们（实测会红）——
#      ResourceBundle 按调用时的默认 locale 取包；
#   ③ 放在**基础包**（无 locale 后缀）里，任何 locale 都继承得到，两个测试也都看得见。
$自建路径 = Join-Path $jdkDir 'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\chinesejava.properties'
$自建行 = New-Object System.Collections.Generic.List[string]
$自建行.Add('# ChineseJava：诊断前缀开关键（生成物，由 tools\生成诊断汉化.ps1 从 tools\诊断术语表.tsv 生成）')
$自建行.Add('# 禁止手改。默认不生效：只有 CHINESEJAVA_PREFIX=zh 或 -Dchinesejava.diagnostics.prefix=zh 时才被读取。')
$自建行.Add('# 放在基础包里（无 locale 后缀），任何 locale 都继承得到；语义见 docs\判据记录.md 与 NOTICE.txt。')
foreach ($nf in $前缀新增) { $自建行.Add("$($nf.键)=$($nf.值)") }
$自建内容 = ($自建行 -join "`n")
$自建原 = if (Test-Path $自建路径) { [IO.File]::ReadAllText($自建路径, [Text.Encoding]::UTF8) } else { '' }
$自建上游 = $自建原   # 自建包在上游不存在 ⇒ 全部算“新增”
$自建KV = 读键值文本 $自建内容
$账.Add([pscustomobject]@{ 包 = 'chinesejava(自建包)'; 新增 = $自建KV.Keys.Count; 覆盖 = 0; 保留 = 0 })
$总新增 += $自建KV.Keys.Count
$待写.Add([pscustomobject]@{ 路径 = $自建路径; 内容 = $自建内容; 包 = 'chinesejava'; 原 = $自建原 })

# ---------- 五、写出或核对 ----------
# 统一规范化：比较与写盘用**同一份**期望串（否则 -Check 与写盘判断会不一致）。
foreach ($w in $待写) {
    if (-not $w.内容.EndsWith("`n")) { $w.内容 = $w.内容 + "`n" }
}
$失败 = 0
foreach ($w in $待写) {
    if ($Check) {
        if (-not (Test-Path $w.路径)) { Write-Host "[FAIL] 缺文件：$($w.路径)" -ForegroundColor Red; $失败++; continue }
        $盘上 = (Get-Content $w.路径 -Raw -Encoding UTF8)
        if (-not (同产物 $盘上 $w.内容)) {
            Write-Host "[FAIL] 与表不一致：$($w.包)（表改过但没重跑生成器？）" -ForegroundColor Red
            $a = $盘上 -split "`r?`n"; $b = $w.内容 -split "`r?`n"
            for ($i = 0; $i -lt [Math]::Max($a.Count, $b.Count); $i++) {
                if ($a[$i] -ne $b[$i]) { Write-Host "  首个差异 行$($i+1)：`n    盘上：$($a[$i])`n    应为：$($b[$i])" -ForegroundColor Red; break }
            }
            $失败++
        }
    } else {
        if (同产物 $w.原 $w.内容) {
            Write-Host "  [未变] $($w.包)（内容与盘上一致，不写）"
        } else {
            # 上游 properties 文件是 **LF** 行尾（2026-10-11 实测：`git checkout` 恢复后文件里没有一个 0D）。
            # 早前"HEAD 是 CRLF"的结论是假象——当时用 `git show | Set-Content` 取对照，而 Set-Content 自己会写 CRLF。
            # 所以这里**只做**：归一成 LF + 保证末尾有一个换行，绝不引入 CR。
            $文本 = $w.内容.Replace("`r`n", "`n")
            if (-not $文本.EndsWith("`n")) { $文本 += "`n" }
            [IO.File]::WriteAllText($w.路径, $文本, (New-Object Text.UTF8Encoding($false)))
            Write-Host "  [写入] $($w.包)"
        }
    }
}

# ---------- 五、差异台账 ----------
$台账行 = @()
$台账行 += '# 诊断差异台账（L1）'
$台账行 += ''
$台账行 += '> 由 `tools\生成诊断汉化.ps1` 从 `tools\诊断术语表.tsv` + `tools\诊断补缺表.tsv` 生成，**不要手改**。'
$台账行 += '> 口径：三类计数逐包相加（Σ 口径），**新增 + 覆盖 + 保留 = 该包键数**。'
$台账行 += ''
$台账行 += '| 包 | 新增 | 覆盖上游 | 保留上游 |'
$台账行 += '|---|---|---|---|'
foreach ($a in $账) { $台账行 += "| $($a.包) | $($a.新增) | $($a.覆盖) | $($a.保留) |" }
$台账行 += "| **合计** | **$总新增** | **$总覆盖** | **$总保留** |"
$台账行 += ''
$台账行 += "涉及键数 = 新增 + 覆盖 = $($总新增 + $总覆盖)；其中覆盖里含前缀键 $($前缀覆盖.Count) 条（错误:/警告:/注: → error:/warning:/note:）与术语替换命中若干。"
$台账行 += ''
$台账行 += '## 有意保留（登记，不是缺口）'
$台账行 += ''
$台账行 += '- 关键字名一律保留英文（switch/case/yield/catch/default/this/finally/instanceof/throws/static/void/permits/opens/requires/provides）：**上游既定口径**。'
$台账行 += '- API 名/命令行选项/技术名（serialVersionUID、Xlint、enable-preview、module-source-path、lambda、varargs、finalize、writeReplace…）保留英文。'
$台账行 += '- 格式占位符与技术标记（`{0}`、`capture#{0}`、`@interface`、`<class>`…）保留英文。'
$台账 = $台账
if (-not $Check) { [IO.File]::WriteAllText($台账, ($台账行 -join "`r`n"), (New-Object Text.UTF8Encoding($false))) }

Write-Host ""
$账 | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "合计：新增 $总新增 ｜ 覆盖上游 $总覆盖 ｜ 保留上游 $总保留"

if ($EmitPatch -and -not $Check) {
    $pd = Join-Path $root 'patches'
    if (-not (Test-Path $pd)) { New-Item -ItemType Directory $pd -Force | Out-Null }
    $pf = Join-Path $pd '0003-批1-诊断汉化.patch'
    & git -C $jdkDir diff -- 'src/*/share/classes/**/*_zh_CN.properties' | Set-Content -Path $pf -Encoding utf8NoBOM
    Write-Host "已导出补丁：$pf"
}

if ($Check) {
    if ($失败 -gt 0) { Write-Host "[FAIL] -Check 未通过（$失败 个包）" -ForegroundColor Red; exit 1 }
    Write-Host "[ok] -Check 通过：16 个主包产物与表一致" -ForegroundColor Green
}
