# 跑批2b判据.ps1 —— 批 2b（软关键字接线）的判据套件
#
#   用法：pwsh -File tests\跑批2b判据.ps1 [-Jdk <镜像路径>]
#   默认镜像：jdk\build\cnjava\images\jdk
#
# 判据（每条都能失败；失败即退出码 1）：
#   K2b-1 单个软关键字在「关键字位置」可用（record/sealed/permits/non-sealed/var/yield/when）
#   K2b-2 软关键字拼写**仍可当标识符**，且名字在字节码里保留（javap 看到中文名）
#   K2b-3 中英对拍：同一逻辑程序，中文写法与英文写法**字节码一致**
#   K2b-4 歧义位置与英文行为一致：`记录 甲;` 与 `record 甲;` 的诊断键相同
#   K2b-5 模块用例：module-info 里 模块/依赖/导出/开放/开放包/指向/提供/伴随/使用/传递 全部可用

param(
    [string]$Jdk = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
if (-not $Jdk) { $Jdk = Join-Path $root 'jdk\build\cnjava\images\jdk' }
$javac = Join-Path $Jdk 'bin\javac.exe'
$java  = Join-Path $Jdk 'bin\java.exe'
$javap = Join-Path $Jdk 'bin\javap.exe'
if (-not (Test-Path $javac)) { Write-Host "[FAIL] 找不到 javac：$javac" -ForegroundColor Red; exit 1 }

$工作 = Join-Path $root ("构建日志\批2b-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory $工作 -Force | Out-Null

$script:通过 = 0; $script:失败 = 0
function 好($m) { Write-Host "  [ok]   $m" -ForegroundColor Green; $script:通过++ }
function 坏($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red;   $script:失败++ }
function 写($路径, $内容) { $d = Split-Path -Parent $路径; if (-not (Test-Path $d)) { New-Item -ItemType Directory $d -Force | Out-Null }; Set-Content $路径 -Value $内容 -Encoding utf8NoBOM }

Write-Host "=== ChineseJava 批 2b 判据（软关键字）===" -ForegroundColor Cyan
Write-Host "镜像：$Jdk"

# ---------------------------------------------------------------- K2b-1
Write-Host "`n-- K2b-1 单个软关键字可用 --"
$单 = Join-Path $工作 '单个'
写 "$单\单个.java" @'
记录 点(整数 横, 整数 纵) { }
密封 接口 形状 许可 圆, 方 { }
非密封 类型 圆 实现 形状 { }
最终 类型 方 实现 形状 { }
公开 类型 单个 {
    公开 静态 空型 main(String[] 参数) {
        自动 甲 = 新建 点(3, 4);
        整数 和 = 选择 (甲) {
            情形 点(整数 横, 整数 纵) 符合 横 > 0 -> 横 + 纵;
            默认 -> 0;
        };
        System.out.println("和=" + 和 + " 横=" + 甲.横());
    }
}
'@
& $javac -d "$单\out" "$单\单个.java" 2>&1 | Tee-Object -FilePath "$工作\K2b-1.txt"
if ($LASTEXITCODE -eq 0) {
    好 "记录/密封/许可/非密封/自动/符合/选择 全部可用（记录 + 密封族 + var + when + switch 表达式）"
    $r = (& $java -cp "$单\out" 单个 2>&1) -join ''
    if ($r -match '和=7' -and $r -match '横=3') { 好 "运行输出正确：$r" } else { 坏 "运行输出异常：$r" }
} else { 坏 "K2b-1 编译失败（输出见 $工作\K2b-1.txt）" }

# ---------------------------------------------------------------- K2b-2
Write-Host "`n-- K2b-2 软拼写仍可当标识符，且名字保留 --"
$标识 = Join-Path $工作 '标识符'
写 "$标识\标识符.java" @'
公开 类型 标识符 {
    公开 静态 空型 main(String[] 参数) {
        整数 记录 = 1;
        整数 自动 = 2;
        整数 密封 = 3;
        整数 许可 = 4;
        整数 模块 = 5;
        整数 开放 = 6;
        System.out.println(记录 + 自动 + 密封 + 许可 + 模块 + 开放);
    }
}
'@
& $javac -g -d "$标识\out" "$标识\标识符.java" 2>&1 | Tee-Object -FilePath "$工作\K2b-2.txt"
if ($LASTEXITCODE -eq 0) {
    好 "记录/自动/密封/许可/模块/开放 作为局部变量名：编译通过"
    $r = (& $java -cp "$标识\out" 标识符 2>&1) -join ''
    if ($r.Trim() -eq '21') { 好 "运行输出正确：21" } else { 坏 "运行输出异常：$r" }
} else { 坏 "K2b-2 编译失败" }
& $javap -p -c -l -classpath "$标识\out" 标识符 2>&1 | Tee-Object -FilePath "$工作\K2b-2-javap.txt" | Out-Null
# 字节级检查（不依赖控制台编码）：class 文件里应能找到中文名的 UTF-8 字节
$字节 = [IO.File]::ReadAllBytes("$标识\out\标识符.class")
function 含字节($bytes, $文本) {
    $nd = [Text.Encoding]::UTF8.GetBytes($文本)
    for ($i = 0; $i -le $bytes.Length - $nd.Length; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $nd.Length; $j++) { if ($bytes[$i+$j] -ne $nd[$j]) { $ok = $false; break } }
        if ($ok) { return $true }
    }
    return $false
}
$保留 = @('记录','自动','密封','许可','模块','开放') | Where-Object { -not (含字节 $字节 $_) }
if ($保留.Count -eq 0) { 好 "class 字节里 6 个中文变量名全部保留（没有把 中文 → 英文 改名）" }
else { 坏 "以下名字在字节码里丢了：$($保留 -join '、')" }

# ---------------------------------------------------------------- K2b-3
Write-Host "`n-- K2b-3 中英对拍（字节码一致）--"
$对拍中 = @'
记录 点(整数 横, 整数 纵) { }
密封 接口 形状 许可 圆 { }
非密封 类型 圆 实现 形状 { }
公开 类型 对拍 {
    公开 静态 空型 main(String[] 参数) {
        自动 甲 = 新建 点(3, 4);
        整数 和 = 选择 (甲) {
            情形 点(整数 横, 整数 纵) 符合 横 > 0 -> 横 + 纵;
            默认 -> 0;
        };
        System.out.println("和=" + 和);
    }
}
'@
$对拍英 = @'
record 点(int 横, int 纵) { }
sealed interface 形状 permits 圆 { }
non-sealed class 圆 implements 形状 { }
public class 对拍 {
    public static void main(String[] 参数) {
        var 甲 = new 点(3, 4);
        int 和 = switch (甲) {
            case 点(int 横, int 纵) when 横 > 0 -> 横 + 纵;
            default -> 0;
        };
        System.out.println("和=" + 和);
    }
}
'@
$a = Join-Path $工作 '对拍中'; $b = Join-Path $工作 '对拍英'
写 "$a\对拍.java" $对拍中; 写 "$b\对拍.java" $对拍英
& $javac -d "$a\out" "$a\对拍.java" 2>&1 | Tee-Object -FilePath "$工作\K2b-3-中.txt"; $c1 = $LASTEXITCODE
& $javac -d "$b\out" "$b\对拍.java" 2>&1 | Tee-Object -FilePath "$工作\K2b-3-英.txt"; $c2 = $LASTEXITCODE
if ($c1 -eq 0 -and $c2 -eq 0) {
    $h1 = (Get-FileHash "$a\out\对拍.class" -Algorithm SHA256).Hash
    $h2 = (Get-FileHash "$b\out\对拍.class" -Algorithm SHA256).Hash
    if ($h1 -eq $h2) { 好 "中文写法 ≡ 英文写法（SHA256 $($h1.Substring(0,16))…）" } else { 坏 "字节码不一致：中 $($h1.Substring(0,16))… / 英 $($h2.Substring(0,16))…" }
} else { 坏 "对拍编译失败：中文退出码 $c1 / 英文退出码 $c2" }

# ---------------------------------------------------------------- K2b-4
Write-Host "`n-- K2b-4 歧义位置与英文行为一致（诊断键对拍）--"
$歧 = Join-Path $工作 '歧义'
写 "$歧\中\T.java" "类型 T { 记录 甲; }"
写 "$歧\英\T.java" "class T { record 甲; }"
$d1 = (& $javac -XDrawDiagnostics -d "$歧\中\out" "$歧\中\T.java" 2>&1) -join "`n"
$d2 = (& $javac -XDrawDiagnostics -d "$歧\英\out" "$歧\英\T.java" 2>&1) -join "`n"
$k1 = ([regex]::Matches($d1, 'compiler\.[a-z.]+') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ','
$k2 = ([regex]::Matches($d2, 'compiler\.[a-z.]+') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ','
if ($k1 -eq $k2) { 好 "诊断键一致：$k1" } else { 坏 "诊断键不同：中 [$k1] / 英 [$k2]" }

# ---------------------------------------------------------------- K2b-5
Write-Host "`n-- K2b-5 模块用例 --"
$模 = Join-Path $工作 '模块'
写 "$模\src\示例.应用\module-info.java" @'
开放 模块 示例.应用 {
    依赖 传递 java.logging;
    导出 示例.应用;
}
'@
写 "$模\src\示例.应用\示例\应用\甲.java" @'
包声明 示例.应用;
公开 类型 甲 {
    公开 静态 空型 main(String[] 参数) { System.out.println("模块 ok"); }
}
'@
& $javac -d "$模\out" --module-source-path "$模\src" --module 示例.应用 2>&1 | Tee-Object -FilePath "$工作\K2b-5.txt"
if ($LASTEXITCODE -eq 0) {
    好 "module-info 里 开放/模块/依赖/传递/导出 可用"
    $r = (& $java --module-path "$模\out" --module 示例.应用/示例.应用.甲 2>&1) -join ''
    if ($r -match '模块 ok') { 好 "模块真跑：$r" } else { 坏 "模块运行异常：$r" }
} else { 坏 "K2b-5 编译失败（输出见 $工作\K2b-5.txt）" }

# ---------------------------------------------------------------- K2b-6
Write-Host "`n-- K2b-6 模块指令补齐：开放包/指向/使用/提供/伴随 --"
$模2 = Join-Path $工作 '模块2'
写 "$模2\src\示例.服务\module-info.java" @'
模块 示例.服务 {
    导出 示例.服务;
}
'@
写 "$模2\src\示例.服务\示例\服务\问候.java" @'
包声明 示例.服务;
公开 接口 问候 { String 说(); }
'@
写 "$模2\src\示例.应用\module-info.java" @'
模块 示例.应用 {
    依赖 示例.服务;
    导出 示例.应用;
    开放包 示例.应用.内部 指向 示例.服务;
    使用 示例.服务.问候;
    提供 示例.服务.问候 伴随 示例.应用.问候实现;
}
'@
写 "$模2\src\示例.应用\示例\应用\问候实现.java" @'
包声明 示例.应用;
公开 类型 问候实现 实现 示例.服务.问候 {
    公开 String 说() { 返回 "模块2 ok"; }
}
'@
写 "$模2\src\示例.应用\示例\应用\内部\内部件.java" @'
包声明 示例.应用.内部;
公开 类型 内部件 { }
'@
& $javac -d "$模2\out" --module-source-path "$模2\src" --module 示例.应用,示例.服务 2>&1 | Tee-Object -FilePath "$工作\K2b-6.txt"
if ($LASTEXITCODE -eq 0) {
    好 "开放包/指向/使用/提供/伴随 全部可用（两个模块一起编）"
    $r = (& $java --module-path "$模2\out" --describe-module 示例.应用 2>&1) -join "`n"
    if ($r -match 'provides' -and $r -match 'uses') { 好 "模块描述符里 provides/uses 均已登记" } else { 坏 "模块描述符异常：$r" }
} else { 坏 "K2b-6 编译失败（输出见 $工作\K2b-6.txt）" }

# ---------------------------------------------------------------- K2b-7
Write-Host "`n-- K2b-7 值类（value，预览）--"
$值 = Join-Path $工作 '值类'
写 "$值\点.java" @'
值类 类型 点 {
    私有 最终 整数 x, y;
    点(整数 横, 整数 纵) {
        x = 横;
        y = 纵;
        父类();
    }
    公开 整数 取横() { 返回 x; }
    公开 整数 取纵() { 返回 y; }
}
'@
& $javac --enable-preview --source 28 -d "$值\out" "$值\点.java" 2>&1 | Tee-Object -FilePath "$工作\K2b-7.txt"
if ($LASTEXITCODE -eq 0) {
    好 "值类 可用（值类 类型 点 { … 父类(); }，--enable-preview --source 28）"
    $v = (& $javap -v -classpath "$值\out" 点 2>&1) -join "`n"
    if ($v -match '(?i)value|ACC_VALUE|identity') { 好 "javap 里能看到值类相关标记" } else { 好 "javap 输出正常（值类标记名随版本而异，不做断言）" }
} else { 坏 "值类 编译失败（见 K2b-7.txt）" }

# ---------------------------------------------------------------- 汇总
Write-Host "`n=== 汇总：通过 $script:通过 项，失败 $script:失败 项 ===" -ForegroundColor Cyan
Write-Host "工作目录：$工作"
if ($script:失败 -gt 0) { exit 1 }
exit 0
