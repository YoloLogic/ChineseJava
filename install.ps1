# install.ps1 —— ChineseJava 用户侧安装（把构建出的 JDK 装成一个可用的发行目录）
#
#   用法：pwsh -File install.ps1                       # 装到 E:\ChineseJava-发行版
#          pwsh -File install.ps1 -Target D:\某目录      # 指定目标
#          pwsh -File install.ps1 -SkipSmoke            # 跳过冒烟
#
# 约束（与构建脚本一致）：
#   * 不修改全局 JAVA_HOME / PATH；只在发行目录里放一个 chinesejava.cmd 包装脚本
#   * 产物只放 E 盘（默认）；由你显式指定其它盘时以你的参数为准
#   * 安装完必须真跑一次冒烟（中文关键字编译 + 运行），失败即报错退出

param(
    [string]$Target = 'E:\ChineseJava-发行版',
    [string]$源镜像 = '',
    [switch]$SkipSmoke
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = $PSScriptRoot
if (-not $源镜像) { $源镜像 = Join-Path $root 'jdk\build\cnjava\images\jdk' }

Write-Host "=== ChineseJava 安装 ===" -ForegroundColor Cyan
Write-Host "源镜像：$源镜像"
Write-Host "目标  ：$Target"

if (-not (Test-Path (Join-Path $源镜像 'bin\javac.exe'))) {
    throw "源镜像里没有 javac.exe：$源镜像（先跑 tools\构建.ps1）"
}

# 1) 拷镜像
$destJdk = Join-Path $Target 'jdk'
if (Test-Path $destJdk) { Write-Host "目标已存在，先清理：$destJdk" -ForegroundColor Yellow; Remove-Item $destJdk -Recurse -Force }
New-Item -ItemType Directory $Target -Force | Out-Null
Write-Host "拷贝镜像（约 450 MB，可能需要 1-2 分钟）…"
Copy-Item $源镜像 $destJdk -Recurse -Force

# 2) 文档与许可（发行必备）
foreach ($f in @('README.md', '常见问题.md', 'LICENSE-SCOPE.md', 'NOTICE.txt')) {
    $s = Join-Path $root $f
    if (Test-Path $s) { Copy-Item $s $Target -Force }
}
foreach ($d in @('docs', 'examples')) {
    $s = Join-Path $root $d
    if (Test-Path $s) { Copy-Item $s (Join-Path $Target $d) -Recurse -Force }
}

# 3) 包装脚本（不动全局 PATH）
#    为什么用 PowerShell 而不是纯 .cmd：批处理里 `shift & "%X%" %*` 会在同一行先展开 %*，
#    结果把子命令名（javac）也传进去（实测报"仅当显式请求注解处理时才接受类名称 'javac'"）。
$wrapperPs1 = @'
# ChineseJava 包装：chinesejava <javac|java|jar|jshell|javadoc|版本> [参数...]
$jdk = Join-Path $PSScriptRoot 'jdk'
if ($args.Count -eq 0) {
    Write-Host '用法：chinesejava <javac|java|jar|jshell|javadoc|jar|jmod|jlink|版本> [参数...]'
    Write-Host "      JDK：$jdk"
    exit 0
}
$子命令 = $args[0]
$其余 = @()
if ($args.Count -gt 1) { $其余 = $args[1..($args.Count - 1)] }
if ($子命令 -eq '版本') { $子命令 = 'javac'; $其余 = @('-version') }
$exe = Join-Path $jdk "bin\$子命令.exe"
if (-not (Test-Path $exe)) {
    Write-Host "不认识或不存在：$子命令（$exe）" -ForegroundColor Red
    exit 2
}
& $exe @其余
exit $LASTEXITCODE
'@
Set-Content -Path (Join-Path $Target 'chinesejava.ps1') -Value $wrapperPs1 -Encoding utf8NoBOM
$wrapperCmd = @'
@echo off
rem ChineseJava 包装（转发给同目录的 chinesejava.ps1）
pwsh -NoProfile -File "%~dp0chinesejava.ps1" %*
'@
Set-Content -Path (Join-Path $Target 'chinesejava.cmd') -Value $wrapperCmd -Encoding ascii

# 4) 冒烟（真编译真运行）
if ($SkipSmoke) {
    Write-Host "[skip] 已按 -SkipSmoke 跳过冒烟" -ForegroundColor Yellow
} else {
    $t = Join-Path $env:TEMP ('cj-smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory $t -Force | Out-Null
    @'
公开 类型 冒烟 {
    公开 静态 空型 main(String[] 参数) {
        整数 计数 = 0;
        如果 (计数 == 0) { System.out.println("ChineseJava 安装冒烟 ok"); }
        否则 { System.out.println("bad"); }
    }
}
'@ | Set-Content (Join-Path $t '冒烟.java') -Encoding utf8NoBOM
    & (Join-Path $destJdk 'bin\javac.exe') -d $t (Join-Path $t '冒烟.java')
    if ($LASTEXITCODE -ne 0) { throw "冒烟编译失败" }
    $out = (& (Join-Path $destJdk 'bin\java.exe') -cp $t 冒烟 2>&1) -join ' '
    Write-Host "冒烟输出：$out"
    if ($out -notmatch '安装冒烟 ok') { throw "冒烟运行输出不对" }
    Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[ok] 冒烟通过（中文关键字编译并运行）" -ForegroundColor Green
}

# 5) 用法
$v = (& (Join-Path $destJdk 'bin\javac.exe') -version 2>&1) -join ''
Write-Host ""
Write-Host "[ok] 安装完成" -ForegroundColor Green
Write-Host "  发行目录：$Target"
Write-Host "  javac   ：$v"
Write-Host "  用法    ：$Target\chinesejava.cmd javac 你的.java"
Write-Host "  直接调用：$destJdk\bin\javac.exe 你的.java"
Write-Host "  提示    ：默认诊断前缀是英文 error:；要中文前缀请设 `$env:CHINESEJAVA_PREFIX='zh'"
Write-Host "  注意    ：本发行版不是 Oracle/OpenJDK 官方版本，详见 LICENSE-SCOPE.md 与 NOTICE.txt"
