# verify.ps1 —— ChineseJava 用户侧自检（能失败的那种）
#
#   用法：pwsh -File verify.ps1                 # 跑全部检查
#          pwsh -File verify.ps1 -跳过自测        # 跳过"判据自测"（它会临时改表再还原）
#          pwsh -File verify.ps1 -Jdk <镜像路径>  # 指定另一份 JDK 镜像
#
# 设计口径（对齐 Chinese++/ChinesePython 的 verify 思路）：
#   * 每条检查都打印 [ok]/[FAIL]，末尾给出"通过 N 项 / 失败 M 项"
#   * **会写盘**：各批判据会在 构建日志\ 下建工作目录（编译产物、日志都在那里）；
#     第 4 节自测会**临时修改** tools\关键字表.tsv 再还原（有判据证明逐字节还原，SHA256 一致）。
#     只读环境（CI/审计）请加 -跳过自测，并接受 构建日志\ 会被写。
#   * 脚本**自己也要能失败**：默认会跑一次"判据自测"——临时把表改坏，
#     要求守卫必须变红，然后再还原并确认变绿。只有能红，才证明这些检查不是摆设。
#   * 退出码：全绿 0，否则 1

param(
    [string]$Jdk = '',
    [switch]$跳过自测
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = $PSScriptRoot
$jdkDir = Join-Path $root 'jdk'
if (-not $Jdk) { $Jdk = Join-Path $jdkDir 'build\cnjava\images\jdk' }

$script:通过 = 0; $script:失败 = 0
function 好($m) { Write-Host "  [ok]   $m" -ForegroundColor Green; $script:通过++ }
function 坏($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red;   $script:失败++ }
function 节($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

Write-Host "=== ChineseJava 自检 ===" -ForegroundColor Cyan
Write-Host "工程根：$root"
Write-Host "镜像  ：$Jdk"

# ---------------------------------------------------------------- 1 环境与产物
节 '1 环境与产物'
foreach ($p in @(
    @{ 名 = '上游树 jdk\'; 路径 = $jdkDir },
    @{ 名 = 'JDK 镜像'; 路径 = $Jdk },
    @{ 名 = '镜像里的 javac'; 路径 = (Join-Path $Jdk 'bin\javac.exe') },
    @{ 名 = '表：关键字表.tsv'; 路径 = (Join-Path $root 'tools\关键字表.tsv') },
    @{ 名 = '表：诊断术语表.tsv'; 路径 = (Join-Path $root 'tools\诊断术语表.tsv') },
    @{ 名 = '表：诊断补缺表.tsv'; 路径 = (Join-Path $root 'tools\诊断补缺表.tsv') },
    @{ 名 = '生成物：ZhKeywords.java'; 路径 = (Join-Path $jdkDir 'src\jdk.compiler\share\classes\com\sun\tools\javac\parser\ZhKeywords.java') },
    @{ 名 = '自建资源包：chinesejava.properties'; 路径 = (Join-Path $jdkDir 'src\jdk.compiler\share\classes\com\sun\tools\javac\resources\chinesejava.properties') },
    @{ 名 = 'MSYS2 bash（构建用）'; 路径 = 'E:\msys64\usr\bin\bash.exe' },
    @{ 名 = 'boot JDK（构建用）'; 路径 = 'E:\java\jdk-27\bin\javac.exe' },
    @{ 名 = 'jtreg（回归用）'; 路径 = 'E:\java\jtreg\lib\jtreg.jar' }
)) {
    if (Test-Path $p.路径) { 好 "$($p.名)" } else { 坏 "缺：$($p.名) → $($p.路径)" }
}
if (Test-Path (Join-Path $Jdk 'bin\java.exe')) {
    $v = (& (Join-Path $Jdk 'bin\java.exe') -version 2>&1) -join ' '
    好 "镜像可运行：$v"
} else { 坏 '镜像里没有 java.exe' }

# ---------------------------------------------------------------- 2 表 ↔ 产物
节 '2 表 ↔ 产物一致（生成器 -Check）'
foreach ($s in @('生成关键字表.ps1', '生成诊断汉化.ps1')) {
    $脚本 = Join-Path $root "tools\$s"
    $out = & pwsh -NoProfile -File $脚本 -Check 2>&1
    if ($LASTEXITCODE -eq 0) { 好 "$s -Check 通过" }
    else {
        坏 "$s -Check 未通过（手改产物或改了表没重跑？）"
        $out | Select-Object -Last 8 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkYellow }
    }
}

# ---------------------------------------------------------------- 3 判据套件
节 '3 判据套件'
$输出 = @{}
# 枚举而不是硬编码：这样"仓库里躺着一套红的判据却没人跑"在结构上不可能（2026-10-11 第二轮审计教训）
$套件 = @(Get-ChildItem (Join-Path $root 'tests') -Filter '跑批*判据.ps1' -File | Sort-Object Name | Select-Object -ExpandProperty Name)
foreach ($t in $套件) {
    $脚本 = Join-Path $root "tests\$t"
    if (-not (Test-Path $脚本)) { 坏 "缺判据套件：$t"; continue }
    $out = & pwsh -NoProfile -File $脚本 -Jdk $Jdk 2>&1
    $输出[$t] = $out
    $尾 = ($out | Select-Object -Last 3) -join ' '
    if ($LASTEXITCODE -eq 0) { 好 "$t：$尾" } else { 坏 "$t：$尾"; $out | Select-Object -Last 8 | ForEach-Object { Write-Host "        $_" } }
}

# ---------------------------------------------------------------- 3.5 元判据（判据自己的健康）
# 来源：2026-10-11 独立审计（审计员用自写脚本发现：① 批5 有 98 处异常被 Continue 吞掉、
# 判词里的 SHA256 打不出来；② 批4 有一项打出空 [ok]）。教训是：
# 「绿得没有证据」和「假绿」一样危险，所以这里对**判据的输出本身**再做一层检查。
节 '3.5 元判据：判据输出里不许有被吞的异常 / 不许有空判词'
# 枚举而不是硬编码：这样"仓库里躺着一套红的判据却没人跑"在结构上不可能（2026-10-11 第二轮审计教训）
$套件 = @(Get-ChildItem (Join-Path $root 'tests') -Filter '跑批*判据.ps1' -File | Sort-Object Name | Select-Object -ExpandProperty Name)
foreach ($t in $套件) {
    if (-not $输出.ContainsKey($t)) { continue }
    $out = @($输出[$t])
    $痕 = @($out | Where-Object { $_ -match 'InvalidOperation|MethodInvocationException|NullReferenceException|不能对值为 Null|不能对空值' })
    $空判 = @($out | Where-Object { $_ -match '^\s*\[ok\]\s*$' })
    $汇总 = ($out | Where-Object { $_ -match '=== 汇总' } | Select-Object -First 1)
    if ($痕.Count -eq 0 -and $空判.Count -eq 0) {
        好 "$t：无被吞异常、无空判词（$($汇总 -replace '\s+', ' ')）"
    } else {
        坏 "$t：被吞异常 $($痕.Count) 处、空判词 $($空判.Count) 处"
        ($痕 + $空判) | Select-Object -First 3 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkYellow }
    }
}

# ---------------------------------------------------------------- 4 判据自测（能失败）
节 '4 判据自测：把表改坏，守卫必须变红'
if ($跳过自测) {
    Write-Host "  [skip] 已按 -跳过自测 跳过" -ForegroundColor Yellow
} else {
    $tsv = Join-Path $root 'tools\关键字表.tsv'
    $原文 = [IO.File]::ReadAllText($tsv, [Text.Encoding]::UTF8)
    $哈希前 = (Get-FileHash $tsv -Algorithm SHA256).Hash
    try {
        # 把 class 的中文改成单字「类」——违反 2–6 汉字定则，守卫必须报错
        $坏 = $原文.Replace("`t类型`t", "`t类`t")
        if ($坏 -eq $原文) { 坏 '自测无法构造（表里找不到 类型 这一行）' }
        else {
            [IO.File]::WriteAllText($tsv, $坏, (New-Object Text.UTF8Encoding($false)))
            & pwsh -NoProfile -File (Join-Path $root 'tools\生成关键字表.ps1') -SkipScan *> $null
            if ($LASTEXITCODE -ne 0) { 好 '表被改坏后守卫确实变红（说明检查不是摆设）' }
            else { 坏 '表被改坏后守卫仍然通过 —— 守卫失效！' }
        }
    } finally {
        [IO.File]::WriteAllText($tsv, $原文, (New-Object Text.UTF8Encoding($false)))
    }
    # 审计建议：自测会临时改表，必须证明**逐字节还原**（否则跑一次自检就悄悄改坏了仓库）
    $哈希后 = (Get-FileHash $tsv -Algorithm SHA256).Hash
    if ($哈希前 -eq $哈希后) { 好 '自测后表逐字节还原（SHA256 一致）' } else { 坏 '自测改了表没还原干净！' }
    & pwsh -NoProfile -File (Join-Path $root 'tools\生成关键字表.ps1') -Check *> $null
    if ($LASTEXITCODE -eq 0) { 好 '还原后守卫恢复绿色' } else { 坏 '还原失败：表与产物仍不一致' }
}

# ---------------------------------------------------------------- 汇总
$总 = $script:通过 + $script:失败
Write-Host "`n=== 汇总：共 $总 项检查，通过 $($script:通过)，失败 $($script:失败) ===" -ForegroundColor Cyan
if ($script:失败 -gt 0) { Write-Host "自检未通过" -ForegroundColor Red; exit 1 }
Write-Host "自检通过（全部 $总 项）" -ForegroundColor Green
exit 0
