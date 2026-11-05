# ChineseJava 批 5 判据：71 个中文拼写位的**穷举**验证
#
# 口径：表驱动（tools\关键字用例.tsv 是唯一真相），每个拼写位都要过三关：
#   ① 中文用法**真编译**（预期=跑的还要真运行、输出必须是 ok）
#   ② 与英文同结构版本**字节码对拍**（同一模板、同一文件名 ⇒ 只有拼写不同）
#   ③ 反向：**硬**关键字当标识符必须报"ChineseJava 关键字"；**软**关键字当标识符必须仍然合法
# 另外本脚本自己先做一次**穷举性对账**：用例表必须与关键字表 71/71 对齐（少一条就红）。
param(
    [string]$Jdk = 'E:\ChineseJava\jdk\build\cnjava\images\jdk'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$工作 = Join-Path $root ("构建日志\批5-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory $工作 -Force | Out-Null

$javac = Join-Path $Jdk 'bin\javac.exe'
$java  = Join-Path $Jdk 'bin\java.exe'

$script:通过 = 0; $script:失败 = 0; $script:序号 = 0
function 好($m) { Write-Host "  [ok]   $m" -ForegroundColor Green; $script:通过++ }
function 坏($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red;    $script:失败++ }
function 跑($exe, [string[]]$参数) { $o = (& $exe @参数 2>&1) -join "`n"; return @{ 码 = $LASTEXITCODE; 出 = $o } }

# ---------- 读表 ----------
$用例表 = Join-Path $root 'tools\关键字用例.tsv'
$关键字表 = Join-Path $root 'tools\关键字表.tsv'
if (-not (Test-Path $用例表)) { 坏 "缺 tools\关键字用例.tsv"; exit 1 }
$用例 = @(Get-Content $用例表 -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' -and $_ -notmatch '^英文\|' })
$关键字 = @(Get-Content $关键字表 -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' })

# ---------- K5-1 穷举性对账（自己先能失败） ----------
Write-Host "`n-- K5-1 穷举性对账：用例表必须覆盖关键字表（`_` 不译，不计）--"
$表英 = @($关键字 | ForEach-Object { ($_ -split "`t")[0] } | Where-Object { $_ -ne '_' })
$例英 = @($用例 | ForEach-Object { ($_ -split '\|')[0] })
$缺 = @($表英 | Where-Object { $例英 -notcontains $_ })
$多 = @($例英 | Where-Object { $表英 -notcontains $_ })
if ($表英.Count -eq 71 -and $缺.Count -eq 0 -and $多.Count -eq 0) {
    好 "用例表 71/71 对齐（硬 $(@($用例 | Where-Object { ($_ -split '\|')[2] -eq '硬' }).Count) + 软 $(@($用例 | Where-Object { ($_ -split '\|')[2] -eq '软' }).Count)）"
} else {
    坏 "对账不齐：表 $($表英.Count) 条、用例 $($例英.Count) 条；缺 $($缺 -join '、')；多 $($多 -join '、')"
}

# ---------- 逐条验证 ----------
$模块支撑 = @{
    'demo/pkg/A.java'    = "package demo.pkg;`npublic class A { }`n"
    'demo/pkg/S.java'    = "package demo.pkg;`npublic interface S { }`n"
    'demo/pkg/Impl.java' = "package demo.pkg;`npublic class Impl implements S { }`n"
}
function 写源码($目录, $期望, $拼写, $模板, $文件名) {
    New-Item -ItemType Directory $目录 -Force | Out-Null
    $文本 = $模板.Replace('\n', "`n").Replace('@', $拼写)
    [IO.File]::WriteAllText((Join-Path $目录 $文件名), $文本, (New-Object Text.UTF8Encoding($false)))
}
function 类哈希表($目录) {
    $t = @{}
    if (Test-Path $目录) {
        Get-ChildItem $目录 -Recurse -Filter '*.class' | ForEach-Object {
            $t[$_.FullName.Substring($目录.Length).Replace('\', '/')] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        }
    }
    return $t
}
function 哈希同($甲, $乙) {
    if ($甲.Count -ne $乙.Count) { return $false }
    foreach ($k in $甲.Keys) { if (-not $乙.ContainsKey($k) -or $乙[$k] -ne $甲[$k]) { return $false } }
    return $true
}

Write-Host "`n-- K5-2 逐条：中文用法真编译/真运行 + 与英文版字节码对拍 --"
$失败行 = New-Object System.Collections.Generic.List[string]
foreach ($用例行 in $用例) {
    $f = $用例行 -split '\|'
    if ($f.Count -ne 5) { 坏 "用例表列数不对：$用例行"; continue }
    $英 = $f[0].Trim(); $中 = $f[1].Trim(); $强度 = $f[2].Trim(); $预期 = $f[3].Trim(); $模板 = $f[4]
    $script:序号++
    $基 = Join-Path $工作 ("{0:d3}-{1}" -f $script:序号, $英)
    $中目 = Join-Path $基 '中'; $英目 = Join-Path $基 '英'
    $名 = if ($预期 -eq '模块') { 'module-info.java' } else { '用例.java' }

    if ($预期 -ne '误用') {
        写源码 $中目 $中 $中 $模板 $名
        写源码 $英目 $英 $英 $模板 $名
        if ($预期 -eq '模块') {
            foreach ($k in $模块支撑.Keys) {
                foreach ($d in @($中目, $英目)) {
                    $p = Join-Path $d $k; New-Item -ItemType Directory (Split-Path $p) -Force | Out-Null
                    [IO.File]::WriteAllText($p, $模块支撑[$k], (New-Object Text.UTF8Encoding($false)))
                }
            }
        }
        $额外 = @()
        if ($预期 -eq '预览') { $额外 = @('--enable-preview', '--release', '28') }
        $中出 = Join-Path $中目 'out'; $英出 = Join-Path $英目 'out'
        $源 = if ($预期 -eq '模块') { @((Join-Path $中目 $名)) + @($模块支撑.Keys | ForEach-Object { Join-Path $中目 $_ }) } else { @((Join-Path $中目 $名)) }
        $c1 = 跑 $javac ($额外 + @('-d', $中出) + $源)
        $源英 = if ($预期 -eq '模块') { @((Join-Path $英目 $名)) + @($模块支撑.Keys | ForEach-Object { Join-Path $英目 $_ }) } else { @((Join-Path $英目 $名)) }
        $c2 = 跑 $javac ($额外 + @('-d', $英出) + $源英)
        if ($c1.码 -ne 0) { 坏 "$中（$英）：中文用法编译失败 → $(($c1.出 -split "`n" | Select-Object -First 2) -join ' / ')"; $失败行.Add("$中/编译"); continue }
        if ($c2.码 -ne 0) { 坏 "$中（$英）：英文对照版编译失败 → $(($c2.出 -split "`n" | Select-Object -First 2) -join ' / ')"; $失败行.Add("$英/编译"); continue }
        # 字节码对拍
        $h1 = 类哈希表 $中出; $h2 = 类哈希表 $英出
        if (哈希同 $h1 $h2) {
            # 审计报告 4.1 实测教训：单元素集合经管道后 `[0]` 会**索引到字符串的字符**，
            # 于是取出的"键"变成 "/"、$h1[$k] 为 null、Substring 抛异常被吞成空白证据。
            # 所以必须 @(...) 强制成数组再取下标；哈希值也要判空后再截断。
            $ks = @($h1.Keys | Sort-Object)
            $k = if ($ks.Count -gt 0) { [string]$ks[0] } else { '' }
            $hv = if ($k -and $h1[$k]) { ([string]$h1[$k]).Substring(0, 12) } else { '（空）' }
            好 "$中（$英）：编译通过，字节码与英文版一致（共 $($ks.Count) 个 class；$k SHA256 $hv…）"
        } else {
            坏 "$中（$英）：字节码与英文版不一致（中文 $(($h1.Keys | Sort-Object) -join ',') vs 英文 $(($h2.Keys | Sort-Object) -join ',')）"
            $失败行.Add("$中/对拍")
        }
        # 真运行（预期=跑 或 预览）
        if ($预期 -eq '跑' -or $预期 -eq '预览') {
            $运行额外 = @()
            if ($预期 -eq '预览') { $运行额外 = @('--enable-preview') }
            $类 = '用例'
            if ($模板 -match '(\S+) demo;') { $类 = "demo.$类" }   # package 行用全限定名（当前用例里 package 是"编"，留个兜底）
            $r = 跑 $java ($运行额外 + @('-cp', $中出, $类))
            if ($r.码 -eq 0 -and $r.出 -match 'ok') { }
            else { 坏 "$中（$英）：中文版运行没输出 ok（退出码 $($r.码)：$($r.出 -replace "`n", ' | ')）"; $失败行.Add("$中/运行") }
        }
    }

    # ---------- 反向：标识符用法 ----------
    $反目录 = Join-Path $基 '反'; New-Item -ItemType Directory $反目录 -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $反目录 '标识符用例.java'),
        "public class 标识符用例 {`n    public static void main(String[] a) {`n        int $中 = 1;`n        System.out.println($中);`n    }`n}`n",
        (New-Object Text.UTF8Encoding($false)))
    $反 = 跑 $javac @('-d', (Join-Path $反目录 'out'), (Join-Path $反目录 '标识符用例.java'))
    if ($强度 -eq '硬') {
        if ($反.码 -ne 0 -and ($反.出 -match 'ChineseJava 关键字' -or $反.出 -match 'ChineseJava keyword')) { }
        else { 坏 "$中（$英）：硬关键字当标识符竟然没报专属消息（退出码 $($反.码)）"; $失败行.Add("$中/反向") }
    } else {
        if ($反.码 -eq 0) { }
        else { 坏 "$中（$英）：软关键字当标识符竟然不合法（退出码 $($反.码)：$(($反.出 -split "`n" | Select-Object -First 2) -join ' / ')）"; $失败行.Add("$中/反向") }
    }
}
if ($失败行.Count -eq 0) { 好 "71 条全部：中文用法编译（可跑的真跑出 ok）+ 与英文版字节码一致 + 反向断言成立" }
else { Write-Host "  （失败明细：$($失败行.Count) 处 → $($失败行 -join '、')）" -ForegroundColor DarkYellow }

# ---------- K5-3 `_` 如实不译 ----------
Write-Host "`n-- K5-3 `_` 如实不译 --"
$下划线 = $关键字 | Where-Object { ($_ -split "`t")[0] -eq '_' }
if ($下划线 -and $下划线 -match '不译') { 好 "表里 `_` 标为「不译」（单字符符号不是词，翻译会破坏 2–6 汉字定则）" } else { 坏 "`_` 的登记丢了" }

# ---------- 汇总 ----------
Write-Host "`n=== 汇总：通过 $script:通过 项，失败 $script:失败 项（用例 $($用例.Count) 条）===" -ForegroundColor Cyan
Write-Host "工作目录：$工作"
if ($script:失败 -gt 0) { exit 1 }
exit 0
