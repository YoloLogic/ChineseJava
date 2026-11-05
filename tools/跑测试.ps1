# 跑测试.ps1 —— 用 jtreg 跑上游回归（兼容性门槛）
#
#   用法：pwsh -File tools\跑测试.ps1                                  # 默认跑两组高相关测试
#          pwsh -File tools\跑测试.ps1 -Test "test/langtools/tools/javac/diags/CheckExamples.java"
#          pwsh -File tools\跑测试.ps1 -Test "test/langtools/tools/javac/parser"
#
# 说明：jtreg 装在 E:\java\jtreg（8.3+1，树里锁定的版本）；用 JT_HOME 传给 make，避免重新 configure。
#      环境与构建脚本一致：cl.exe / MSYS2 工具强制英文（VSLANG=1033、LC_ALL=C）。

param(
    [string]$Test   = 'test/langtools/tools/javac/diags/CheckResourceKeys.java test/langtools/tools/javac/diags/CheckExamples.java',
    [string]$JtHome = 'E:\java\jtreg',
    [string]$Conf   = 'cnjava',
    [int]$Jobs      = 8,
    [string]$语言   = 'en'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
$jdkDir = Join-Path $root 'jdk'
$msysBash = 'E:\msys64\usr\bin\bash.exe'
function 转msys([string]$p) { '/' + $p.Substring(0, 1).ToLower() + $p.Substring(2).Replace('\', '/') }

$logDir = Join-Path $root '构建日志'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory $logDir -Force | Out-Null }
$log = Join-Path $logDir ("测试-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
function 记($m) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Add-Content $log -Value $line -Encoding utf8NoBOM; Write-Host $line }

if (-not (Test-Path $msysBash)) { throw "找不到 MSYS2 bash：$msysBash" }
if (-not (Test-Path (Join-Path $JtHome 'lib\jtreg.jar'))) { throw "找不到 jtreg：$JtHome\lib\jtreg.jar" }

# 与构建一致：强制英文，避免中文横幅/消息干扰工具解析
$env:VSLANG = '1033'; $env:LC_ALL = 'C'; $env:LANG = 'C'
$env:PATH = "$(Join-Path 'E:\msys64\usr\bin' '');" + $env:PATH   # 让 make 里调用的 shell 工具可见

# 关键：Windows 上 Java 的默认 locale 取自**系统区域设置**，LC_ALL/LANG 不起作用。
# 上游一批 langtools 测试用 -XDrawDiagnostics 对拍参考文件（只有英文），
# 在中文 Windows 上会因"计数行被本地化"（`1 个错误` vs `1 error`）而假失败。
# 三个通道都要给（实测：只给其中一两个仍会红）：
#   ① agent VM（跑 `@compile` 动作的那个 JVM）  → TEST_OPTS_VM_OPTIONS   → jtreg -vmoption:  (RunTests.gmk:211)
#   ② 测试 VM（进程内用 JavaCompiler API 断言） → TEST_OPTS_JAVA_OPTIONS → jtreg -javaoption: (RunTests.gmk:212/965)
#   ③ jtreg 自身 JVM                            → JTREG_LAUNCHER_OPTIONS (RunTests.gmk:918/1076)
# 另加 JAVA_TOOL_OPTIONS 兜底（覆盖测试自己 spawn 的 java 子进程）。注意 LC_ALL/LANG 在 Windows 上无效。
$测试选项 = ''
if ($语言) {
    $env:JAVA_TOOL_OPTIONS = "-Duser.language=$语言 -Duser.country=US"
    $测试选项  = "TEST_OPTS_VM_OPTIONS='-Duser.language=$语言 -Duser.country=US'"
    $测试选项 += " TEST_OPTS_JAVA_OPTIONS='-Duser.language=$语言 -Duser.country=US'"
    $测试选项 += " JTREG_LAUNCHER_OPTIONS='-Duser.language=$语言 -Duser.country=US'"
    Write-Host "[env] JAVA_TOOL_OPTIONS=$env:JAVA_TOOL_OPTIONS（兜底）"
    Write-Host "[env] $测试选项（①②③ 通道）"
}

$jdkMsys = 转msys $jdkDir
$jtMsys = 转msys $JtHome
记 "=== jtreg 回归：TEST=$Test ==="
记 "jtreg=$JtHome ｜ Conf=$Conf ｜ JOBS=$Jobs ｜ 日志=$log"
$sw = [Diagnostics.Stopwatch]::StartNew()
& $msysBash -lc "cd '$jdkMsys' && make CONF=$Conf test JT_HOME=$jtMsys TEST='$Test' JOBS=$Jobs $测试选项" 2>&1 |
    Tee-Object -FilePath $log -Append | Select-String -Pattern 'Test results|Passed:|Failed:|Error:|TEST SUCCESS|TEST FAILURE|^Testing|Summary' | Select-Object -Last 40
$rc = $LASTEXITCODE
记 ("make test 退出码 $rc，耗时 {0:N0}s" -f $sw.Elapsed.TotalSeconds)
if ($rc -ne 0) { 记 "[FAIL] 回归未通过；完整日志：$log"; exit 1 }
记 "[ok] 回归通过；完整日志：$log"
