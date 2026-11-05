# ChineseJava 批 4 判据：命名空间不变式 + 台账 + 表驱动纪律
#
# 口径变更（2026-11）：**取消 java 库汉化，只保留关键字 + 诊断**。
#   原批4 测的「汉语平行库（复制层）」「英文兼容（派生层）」已随库名层一起删除；
#   那处「java/ 后跟非 ASCII 段即放行」的窄放行也已回退（git checkout 恢复上游）。
#
# 本批现在只测**仍然成立且必须成立**的四件事：
#   K4-1 环境
#   K4-2 纯英文程序照旧编译运行（原库英文零影响）
#   K4-3 java.lang / java.util 无法伪造（上游不变式，回退后更该守住）
#   K4-4 汉语名 java.工具.* 同样被拒（放行已撤销 —— 这是口径变更的核心断言）
#   K4-5 关键字表 ↔ 产物一致（表驱动纪律没丢）
#   K4-6 关键字生成器守卫能失败（塞坏条目必须红 → 还原）
#   K4-7 硬边界台账项目齐全
#
# 每条都能失败（反向断言写在同一项里）。
param(
    [string]$Jdk = 'E:\ChineseJava\jdk\build\cnjava\images\jdk'
)
$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$工作  = Join-Path $root ("构建日志\批4-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory $工作 -Force | Out-Null

$javac = Join-Path $Jdk 'bin\javac.exe'
$java  = Join-Path $Jdk 'bin\java.exe'
$javap = Join-Path $Jdk 'bin\javap.exe'

$script:通过 = 0; $script:失败 = 0
function 好($m) { Write-Host "  [ok]   $m" -ForegroundColor Green; $script:通过++ }
function 坏($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red;    $script:失败++ }
function 跑($exe, [string[]]$参数) { $o = (& $exe @参数 2>&1) -join "`n"; return @{ 码 = $LASTEXITCODE; 出 = $o } }
function 跑脚本($脚本路径, [string[]]$参数) {
    $o = (& pwsh -NoProfile -File $脚本路径 @参数 2>&1) -join "`n"
    return @{ 码 = $LASTEXITCODE; 出 = $o }
}

# ---------------------------------------------------------------- K4-1
Write-Host "`n-- K4-1 环境 --"
if (Test-Path $javac) {
    $v = (& $java -version 2>&1 | Select-Object -First 1)
    好 "镜像就位（$v）"
} else { 坏 "缺镜像：$javac" }

# ---------------------------------------------------------------- K4-2 原库英文零影响
Write-Host "`n-- K4-2 原库英文零影响（纯英文程序照旧编译运行）--"
$乙目录 = Join-Path $工作 '英文'; New-Item -ItemType Directory $乙目录 -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $乙目录 '乙.java'), @'
import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;

public class 乙 {
    public static void main(String[] args) {
        Function<Integer, Integer> 平方 = x -> x * x;
        List<String> 表 = new ArrayList<>();
        表.add("a");
        System.out.println("原库英文 = " + 平方.apply(6) + 表.size() + 表);
    }
}
'@, (New-Object Text.UTF8Encoding($false)))
$b = 跑 $javac @('-d', (Join-Path $乙目录 'out'), (Join-Path $乙目录 '乙.java'))
if ($b.码 -eq 0) {
    $rb = 跑 $java @('-cp', (Join-Path $乙目录 'out'), '乙')
    if ($rb.出 -match '原库英文 = 361\[a\]') { 好 "纯英文程序（java.util + java.util.function）编译运行正常：$($rb.出.Trim())" }
    else { 坏 "英文程序输出不对：$($rb.出)" }
} else { 坏 "纯英文程序编不过：$($b.出 -split "`n" | Select-Object -First 4)" }

# ---------------------------------------------------------------- K4-3/K4-4 命名空间不变式
Write-Host "`n-- K4-3/K4-4 命名空间：java.lang/java.util 不可伪造；汉语名 java.工具.* 同样被拒 --"
# 造一个真 class 当字节模板（放在普通包里，避免被 javac 挡）
$模板目录 = Join-Path $工作 '模板'; New-Item -ItemType Directory $模板目录 -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $模板目录 '壳.java'), @'
package chinesejava.probe;
public class 壳 { 公开 静态 空型 main(String[] a) { System.out.println("壳"); } }
'@, (New-Object Text.UTF8Encoding($false)))
$c0 = 跑 $javac @('-d', $模板目录, (Join-Path $模板目录 '壳.java'))
if ($c0.码 -ne 0) {
    坏 "探针模板编不过：$($c0.出 -split "`n" | Select-Object -First 3)"
} else {
    # 探针程序：按内部名从目录取 .class，直接 defineClass，把判定权交给 VM
    $探针源 = @'
import java.nio.file.*;

public class 放行探针 {
    static class 目录加载器 extends ClassLoader {
        final Path 根;
        目录加载器(Path 根) { super(null); this.根 = 根; }
        @Override protected Class<?> findClass(String 名) throws ClassNotFoundException {
            Path f = 根.resolve(名.replace('.', '/') + ".class");
            if (!Files.isRegularFile(f)) throw new ClassNotFoundException(名 + " （无字节）");
            try { byte[] b = Files.readAllBytes(f); return defineClass(名, b, 0, b.length); }
            catch (Throwable t) { throw new ClassNotFoundException(名 + " ⇒ " + t, t); }
        }
    }
    public static void main(String[] a) throws Exception {
        Path 根 = Paths.get(a[0]);
        for (int i = 1; i < a.length; i++) {
            String 名 = a[i];
            try {
                Class<?> c = Class.forName(名, false, new 目录加载器(根));
                System.out.println(名 + " ⇒ 放行 " + c + " 包=" + c.getPackageName());
            } catch (Throwable t) {
                Throwable r = t; while (r.getCause() != null) r = r.getCause();
                System.out.println(名 + " ⇒ 被拒 " + r.getClass().getSimpleName() + ": " + r.getMessage());
            }
        }
    }
}
'@
    [IO.File]::WriteAllText((Join-Path $模板目录 '放行探针.java'), $探针源, (New-Object Text.UTF8Encoding($false)))
    $c1 = 跑 $javac @('-d', $模板目录, (Join-Path $模板目录 '放行探针.java'))
    if ($c1.码 -ne 0) { 坏 "探针程序编不过：$($c1.出 -split "`n" | Select-Object -First 3)" }
    else {
        # 把模板 class 摆到各目标包路径下（字节真存在，才逼 VM 走到最后一步）
        $字节 = Join-Path $模板目录 'chinesejava\probe\壳.class'
        $摆放 = @{
            'java\lang\伪'    = 'java.lang.伪'
            'java\util\伪'    = 'java.util.伪'
            'java\工具\伪'    = 'java.工具.伪'
            'java\工具\lang\伪' = 'java.工具.lang.伪'
        }
        foreach ($k in $摆放.Keys) {
            $d = Split-Path (Join-Path $模板目录 $k)
            New-Item -ItemType Directory $d -Force | Out-Null
            Copy-Item $字节 (Join-Path $模板目录 ($k + '.class')) -Force
        }
        $名 = @('java.lang.伪', 'java.util.伪', 'java.工具.伪', 'java.工具.lang.伪')
        $r1 = 跑 $java (@('-cp', $模板目录, '放行探针', $模板目录) + $名)
        $出 = $r1.出
        $拒lang = ($出 -match 'java\.lang\.伪 ⇒ 被拒') -and ($出 -match 'java\.util\.伪 ⇒ 被拒')
        $拒汉 = ($出 -match 'java\.工具\.伪 ⇒ 被拒') -and ($出 -match 'java\.工具\.lang\.伪 ⇒ 被拒')
        if ($拒lang) { 好 "java.lang.* / java.util.* 伪造被拒（Prohibited package name）" }
        else { 坏 "java.lang/java.util 能伪造了！$($出 -replace "`n", ' | ')" }
        if ($拒汉) { 好 "汉语名 java.工具.* 同样被拒（窄放行确已撤销，这是本次口径变更的核心）" }
        else { 坏 "汉语名 java.工具.* 仍被放行 —— 窄放行没撤干净！$($出 -replace "`n", ' | ')" }
        Write-Host "      探针原始输出：" -ForegroundColor DarkGray
        $出 -split "`n" | ForEach-Object { if ($_) { Write-Host "        $_" -ForegroundColor DarkGray } }
    }
}

# ---------------------------------------------------------------- K4-5 表↔产物一致
Write-Host "`n-- K4-5 关键字表 ↔ 产物一致（生成器 -Check）--"
$g = 跑脚本 (Join-Path $root 'tools\生成关键字表.ps1') @('-Check')
if ($g.码 -eq 0) { 好 (($g.出 -split "`n" | Where-Object { $_ -match 'Check 通过|校验通过' } | Select-Object -First 1).Trim()) } else { 坏 "表与产物不同步：$($g.出 -split "`n" | Select-Object -Last 3)" }

# ---------------------------------------------------------------- K4-6 生成器守卫能失败
Write-Host "`n-- K4-6 关键字生成器守卫能失败（塞一条撞关键字拼写的坏条目 → 必须红 → 还原）--"
$tsv = Join-Path $root 'tools\关键字表.tsv'
$原文 = [IO.File]::ReadAllText($tsv, [Text.Encoding]::UTF8)
try {
    [IO.File]::AppendAllText($tsv, "abstract`t抽象`t保留`t硬`t新`t撞车测试", (New-Object Text.UTF8Encoding($false)))
    $坏跑 = 跑脚本 (Join-Path $root 'tools\生成关键字表.ps1') @('-SkipScan')
    if ($坏跑.码 -ne 0) { 好 "坏条目确实被守卫拒绝（守卫报了中文重复/英文重复）" }
    else { 坏 "坏条目没被拒绝——守卫形同虚设" }
} finally {
    [IO.File]::WriteAllText($tsv, $原文, (New-Object Text.UTF8Encoding($false)))
    $好跑 = 跑脚本 (Join-Path $root 'tools\生成关键字表.ps1') @('-Check')
    if ($好跑.码 -eq 0) { 好 "还原后守卫恢复绿色" } else { 坏 "还原后仍红：$($好跑.出 -split "`n" | Select-Object -Last 3)" }
}

# ---------------------------------------------------------------- K4-7 硬边界台账
Write-Host "`n-- K4-7 硬边界台账（照 Chinese++ 口径立账）--"
$台账 = Join-Path $root 'docs\硬边界台账.md'
if (Test-Path $台账) {
    $t = [IO.File]::ReadAllText($台账, [Text.Encoding]::UTF8)
    $缺 = @()
    foreach ($词 in @('toString', 'equals', 'hashCode', 'clone', 'finalize', 'main', '不可伪造')) {
        if ($t -notmatch [regex]::Escape($词)) { $缺 += $词 }
    }
    if ($缺.Count -eq 0) { 好 "台账在：Object 五钩子 + main + java.* 不可伪造 + 覆盖面都记着" }
    else { 坏 "台账缺条目：$($缺 -join '、')" }
} else { 坏 "缺 docs\硬边界台账.md" }

# ---------------------------------------------------------------- 汇总
Write-Host "`n=== 汇总：通过 $script:通过 项，失败 $script:失败 项 ===" -ForegroundColor Cyan
Write-Host "工作目录：$工作"
if ($script:失败 -gt 0) { exit 1 }
exit 0
