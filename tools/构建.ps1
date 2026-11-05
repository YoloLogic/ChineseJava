# 构建.ps1 —— 用 MSYS2 + boot JDK 构建 ChineseJava 的 Windows JDK
#
#   用法：
#     pwsh -File tools\构建.ps1 -Check          # 只检查环境（不构建）
#     pwsh -File tools\构建.ps1 -Configure      # 只跑 configure
#     pwsh -File tools\构建.ps1                 # configure（若未配）+ make images
#     pwsh -File tools\构建.ps1 -Make           # 只跑 make images
#
# 固化三条约束：
#   1) 产物全部在 E 盘（源码树 jdk\ 与 build\ 都在 E:，MSYS2 在 E:\msys64）
#   2) **不动全局** JAVA_HOME / PATH —— 只在本次进程内临时设置
#   3) 全程落日志（构建日志\ 下），并在成功后用**新编出的 JDK** 跑中文关键字冒烟
#
# 路径不写死：工程根从本脚本位置推出。

param(
    [string]$BootJdk = 'E:\java\jdk-27',
    [string]$Conf    = 'cnjava',
    [int]$Jobs       = 12,
    [switch]$Check,
    [switch]$Configure,
    [switch]$Make,
    [switch]$WarningsAsErrors
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root    = Split-Path -Parent $PSScriptRoot
$jdkDir  = Join-Path $root 'jdk'
$msysBash = 'E:\msys64\usr\bin\bash.exe'
$logDir  = Join-Path $root '构建日志'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory $logDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log   = Join-Path $logDir "构建-$stamp.log"

function 记($m) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Add-Content $log -Value $line -Encoding utf8NoBOM; Write-Host $line }
function 转msys([string]$p) { '/' + $p.Substring(0,1).ToLower() + $p.Substring(2).Replace('\','/') }

$jdkMsys  = 转msys $jdkDir
$bootMsys = 转msys $BootJdk
$buildDir = Join-Path $jdkDir "build\$Conf"

# ---------------- 一、环境检查 ----------------
记 "=== 环境检查 ==="
$fail = @()
if (-not (Test-Path $msysBash)) { $fail += "MSYS2 bash 不存在：$msysBash" }
if (-not (Test-Path $jdkDir))  { $fail += "上游树不存在：$jdkDir" }
if (-not (Test-Path (Join-Path $BootJdk 'bin\javac.exe'))) { $fail += "boot JDK 不存在：$BootJdk" }
if ($fail.Count -eq 0) {
    $bv = (& (Join-Path $BootJdk 'bin\javac.exe') -version 2>&1) -join ''
    记 "boot JDK: $bv"
    if ($bv -notmatch 'javac (27|28)') { $fail += "boot JDK 版本必须 ∈ {27,28}，实测：$bv" }
    $miss = @()
    foreach ($t in @('autoconf', 'm4', 'make', 'zip', 'unzip', 'diff', 'awk')) {
        $p = (& $msysBash -lc "command -v $t" 2>&1) -join ''
        if (-not $p) { $miss += $t }
    }
    if ($miss.Count -gt 0) { $fail += "MSYS2 缺少工具：$($miss -join ' ')" }
    else { 记 "MSYS2 工具：autoconf / m4 / make / zip / unzip / diff / awk 全部到位" }
    $dirty = & git -C $jdkDir status --short
    记 "上游树改动：$($dirty -join ' | ')"
}
if ($fail.Count -gt 0) {
    $fail | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    记 "环境检查未通过，共 $($fail.Count) 条"
    exit 1
}
if ($Check) { Write-Host "[ok] 环境检查通过（只检查，未构建）" -ForegroundColor Green; 记 "[ok] 环境检查通过（-Check）"; exit 0 }
if ($Configure -and $Make) { Write-Host "[FAIL] -Configure 与 -Make 不能同时用" -ForegroundColor Red; exit 1 }

# ---------------- 二、临时环境（只在本次进程内）----------------
[Environment]::SetEnvironmentVariable('JAVA_HOME', $null, 'Process')
$env:BOOT_JDK = $BootJdk
$env:PATH = (Join-Path $BootJdk 'bin') + ';' + $env:PATH   # 仅本次进程，供脚本内调用；不改全局

# 关键：cl.exe 与 MSYS2 工具都强制英文。
#   实测教训：中文横幅会让 configure 报
#   「Target CPU mismatch. We are building for x86_64 but CL is for "版"; expected "x64"」
#   —— 与铁律② 同源：工具链解析必须见到英文。
$env:VSLANG = '1033'    # 让 MSVC(cl/link/rc) 输出英文
$env:LC_ALL = 'C'
$env:LANG   = 'C'
记 "临时变量：BOOT_JDK=$env:BOOT_JDK  VSLANG=$env:VSLANG  LC_ALL=$env:LC_ALL（均未写入系统环境）"

# ---------------- 三、configure ----------------
$confArgs = "--with-boot-jdk=$bootMsys --with-conf-name=$Conf"
if (-not $WarningsAsErrors) { $confArgs += ' --disable-warnings-as-errors' }
if ((-not $Make) -and ((-not (Test-Path (Join-Path $buildDir 'spec.gmk'))) -or $Configure)) {
    记 "=== configure：$confArgs ==="
    & $msysBash -lc "cd '$jdkMsys' && ./configure $confArgs" 2>&1 | Tee-Object -FilePath $log -Append | Select-Object -Last 25
    if ($LASTEXITCODE -ne 0) { 记 "[FAIL] configure 退出码 $LASTEXITCODE"; exit 1 }
    记 "[ok] configure 完成：$buildDir"
}
if ($Configure) { Write-Host "[ok] configure 完成（-Configure：只配置，不跑 make）" -ForegroundColor Green; 记 "[ok] configure 完成（-Configure）"; exit 0 }

# ---------------- 四、make images ----------------
记 "=== make images（JOBS=$Jobs）—— 这一步会用刚编出的 javac 编它自己（自举）==="
$sw = [Diagnostics.Stopwatch]::StartNew()
& $msysBash -lc "cd '$jdkMsys' && make CONF=$Conf images JOBS=$Jobs" 2>&1 | Tee-Object -FilePath $log -Append | Select-Object -Last 30
$rc = $LASTEXITCODE
记 ("make 退出码 $rc，耗时 {0:N0}s" -f $sw.Elapsed.TotalSeconds)
if ($rc -ne 0) { 记 "[FAIL] make images 失败；完整日志：$log"; exit 1 }

# ---------------- 五、产物判据（真跑）----------------
$imageJdk = Join-Path $buildDir 'images\jdk'
$javaExe  = Join-Path $imageJdk 'bin\java.exe'
$javacExe = Join-Path $imageJdk 'bin\javac.exe'
if (-not (Test-Path $javaExe)) { 记 "[FAIL] 没有产出 $javaExe"; exit 1 }
记 "=== 产物真跑 ==="
$v = & $javaExe -version 2>&1
记 "java -version: $($v -join ' / ')"

# 用新编出的 JDK 编「中文关键字」源码 —— 这是本轮的关键判据
$smoke = Join-Path $logDir "冒烟-$stamp"
New-Item -ItemType Directory $smoke -Force | Out-Null
@'
公开 类型 冒烟 {
    公开 静态 空型 main(String[] 参数) {
        整数 计数 = 0;
        如果 (计数 == 0) { System.out.println("ChineseJava 冒烟 ok"); }
        否则 { System.out.println("bad"); }
        for (整数 i = 0; i < 1; i++) { System.out.println("中英混写 ok"); }
    }
}
'@ | Set-Content (Join-Path $smoke '冒烟.java') -Encoding utf8NoBOM
& $javacExe -d $smoke (Join-Path $smoke '冒烟.java') 2>&1 | Tee-Object -FilePath $log -Append | Out-String | Write-Host
$c1 = $LASTEXITCODE
$run = ''
if ($c1 -eq 0) { $run = (& $javaExe -cp $smoke 冒烟 2>&1) -join ' | ' }
记 "中文关键字冒烟：javac 退出码 $c1 ；运行输出：$run"
if ($c1 -ne 0) { 记 "[FAIL] 新编出的 JDK 不能编译中文关键字"; exit 1 }

记 "[ok] 构建完成。产物：$imageJdk"
Write-Host "[ok] 构建完成（$([math]::Round($sw.Elapsed.TotalMinutes,1)) 分钟）→ $imageJdk" -ForegroundColor Green
Write-Host "     日志：$log"
