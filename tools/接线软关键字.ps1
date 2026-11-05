# 接线软关键字.ps1 —— 批 2b：把中文软关键字接到 javac 解析层（位置敏感）
#
#   用法：pwsh -File tools\接线软关键字.ps1            # 打补丁（已在则跳过）
#          pwsh -File tools\接线软关键字.ps1 -Check    # 只检查是否已接线
#
# 原理：
#   英文软关键字（record/sealed/permits/var/yield/when/module/open/…）在 javac 里不是词法层
#   关键字，而是**解析层按位置**用 Name 比较识别的（`token.name() == names.record`）。
#   所以中文软拼写不能挂词法表（挂了就会占掉标识符空间），只能在每个"期待软关键字"的位置
#   同时接受中文拼写。本脚本把 `X.name() == names.Y` 一律换成 `isSoft(X.name(), names.Y)`：
#   英文行为完全不变（先做恒等比较），中文拼写等价生效；**其它位置仍是普通标识符**，
#   因此「整数 记录 = 1;」照旧合法，且 AST/字节码里保留中文原名。
#
# 本脚本是「跟随上游」时重新应用的唯一入口；生成物（ZhKeywords）由 生成关键字表.ps1 产出。

param([switch]$Check)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'jdk\src\jdk.compiler\share\classes\com\sun\tools\javac\parser\JavacParser.java'
if (-not (Test-Path $src)) { throw "找不到 $src" }

$原文 = Get-Content $src -Raw -Encoding UTF8
$已接线 = $原文 -match 'private boolean isSoft\(Name tokenName, Name english\)'
if ($Check) {
    if ($已接线) { Write-Host "[ok] 已接线（JavacParser 含 isSoft 助手）" -ForegroundColor Green; exit 0 }
    Write-Host "[FAIL] 尚未接线" -ForegroundColor Red; exit 1
}
if ($已接线) { Write-Host "[ok] 已接线，跳过（幂等）" -ForegroundColor Green; exit 0 }

# ---------- 一、助手块 ----------
$助手锚 = @'
    protected boolean isRecordStart() {
'@
$助手新 = @'
    // ===================== ChineseJava：软关键字（位置敏感） =====================
    // 中文拼写只在解析层被识别：命中时等价于英文软关键字，其它位置仍是普通标识符，
    // 因此「整数 记录 = 1;」照旧合法，且 AST/字节码里保留中文原名。
    // 表来源：tools\关键字表.tsv → 生成物 ZhKeywords.SOFT（生成物禁止手改）。

    private Map<Name, Name> zhSoftNames;
    private Name zhNonSealed;

    private void initZhSoftNames() {
        Map<Name, Name> m = new HashMap<>();
        Name nonSealed = null;
        for (int i = 0; i < ZhKeywords.SOFT.length; i += 2) {
            String zh = ZhKeywords.SOFT[i];
            String en = ZhKeywords.SOFT[i + 1];
            if (zh == null || zh.isEmpty()) {
                continue;
            }
            if ("non-sealed".equals(en)) {
                nonSealed = names.fromString(zh);   // 英文是两个 token、中文是一个，单独处理
            } else {
                m.put(names.fromString(en), names.fromString(zh));
            }
        }
        zhNonSealed = nonSealed;
        zhSoftNames = m;
    }

    /** ChineseJava：tokenName 是否就是软关键字 english（接受英文原拼写与中文拼写）。 */
    private boolean isSoft(Name tokenName, Name english) {
        if (tokenName == english) {
            return true;
        }
        if (zhSoftNames == null) {
            initZhSoftNames();
        }
        Name zh = zhSoftNames.get(english);
        return zh != null && tokenName == zh;
    }

    protected boolean isRecordStart() {
'@

# ---------- 二、替换表（每处都断言命中次数） ----------
$对 = @()
$对 += [pscustomobject]@{ 说明 = 'var 判定（局部变量类型推断）'; 次 = 1
    旧 = 'boolean var = token.kind == IDENTIFIER && token.name() == names.var;'
    新 = 'boolean var = token.kind == IDENTIFIER && isSoft(token.name(), names.var);' }
$对 += [pscustomobject]@{ 说明 = '受限类型名 != var'; 次 = 1
    旧 = 'if (restrictedTypeName != null && (!allowVar || restrictedTypeName != names.var)) {'
    新 = 'if (restrictedTypeName != null && (!allowVar || !isSoft(restrictedTypeName, names.var))) {' }
$对 += [pscustomobject]@{ 说明 = 'yield 作为非法方法名（2 处）'; 次 = 2
    旧 = '        if (name == names.yield) {'
    新 = '        if (isSoft(name, names.yield)) {' }
$对 += [pscustomobject]@{ 说明 = 'yield 语句'; 次 = 1
    旧 = 'if (token.name() == names.yield && allowYieldStatement) {'
    新 = 'if (isSoft(token.name(), names.yield) && allowYieldStatement) {' }
$对 += [pscustomobject]@{ 说明 = 'when 守卫'; 次 = 1
    旧 = 'if (token.kind == IDENTIFIER && token.name() == names.when) {'
    新 = 'if (token.kind == IDENTIFIER && isSoft(token.name(), names.when)) {' }
$对 += [pscustomobject]@{ 说明 = 'when 前瞻'; 次 = 1
    旧 = 'S.token(lookahead + 1).name() == names.when) {'
    新 = 'isSoft(S.token(lookahead + 1).name(), names.when)) {' }
$对 += [pscustomobject]@{ 说明 = 'typeName != var'; 次 = 1
    旧 = 'if (typeName != names.var) {'
    新 = 'if (!isSoft(typeName, names.var)) {' }
$对 += [pscustomobject]@{ 说明 = '受限类型名逐名判定：var'; 次 = 1
    旧 = '        if (name == names.var) {'
    新 = '        if (isSoft(name, names.var)) {' }
$对 += [pscustomobject]@{ 说明 = '受限类型名逐名判定：record'; 次 = 1
    旧 = '        if (name == names.record) {'
    新 = '        if (isSoft(name, names.record)) {' }
$对 += [pscustomobject]@{ 说明 = '受限类型名逐名判定：value'; 次 = 1
    旧 = '        if (name == names.value) {'
    新 = '        if (isSoft(name, names.value)) {' }
$对 += [pscustomobject]@{ 说明 = '受限类型名逐名判定：sealed'; 次 = 1
    旧 = '        if (name == names.sealed) {'
    新 = '        if (isSoft(name, names.sealed)) {' }
$对 += [pscustomobject]@{ 说明 = '受限类型名逐名判定：permits'; 次 = 1
    旧 = '        if (name == names.permits) {'
    新 = '        if (isSoft(name, names.permits)) {' }
$对 += [pscustomobject]@{ 说明 = '模块头：open'; 次 = 1
    旧 = 'if (token.name() == names.open) {'
    新 = 'if (isSoft(token.name(), names.open)) {' }
$对 += [pscustomobject]@{ 说明 = '模块头：module'; 次 = 1
    旧 = 'if (token.kind == IDENTIFIER && token.name() == names.module) {'
    新 = 'if (token.kind == IDENTIFIER && isSoft(token.name(), names.module)) {' }
$对 += [pscustomobject]@{ 说明 = '模块指令：requires'; 次 = 1
    旧 = 'if (token.name() == names.requires) {'
    新 = 'if (isSoft(token.name(), names.requires)) {' }
$对 += [pscustomobject]@{ 说明 = '模块指令：transitive'; 次 = 1
    旧 = 'if (token.name() == names.transitive) {'
    新 = 'if (isSoft(token.name(), names.transitive)) {' }
$对 += [pscustomobject]@{ 说明 = '模块指令：exports/opens 分支'; 次 = 1
    旧 = '} else if (token.name() == names.exports || token.name() == names.opens) {'
    新 = '} else if (isSoft(token.name(), names.exports) || isSoft(token.name(), names.opens)) {' }
$对 += [pscustomobject]@{ 说明 = '模块指令：exports 判定'; 次 = 1
    旧 = 'boolean exports = token.name() == names.exports;'
    新 = 'boolean exports = isSoft(token.name(), names.exports);' }
$对 += [pscustomobject]@{ 说明 = '模块指令：to'; 次 = 1
    旧 = 'if (token.kind == IDENTIFIER && token.name() == names.to) {'
    新 = 'if (token.kind == IDENTIFIER && isSoft(token.name(), names.to)) {' }
$对 += [pscustomobject]@{ 说明 = '模块指令：provides'; 次 = 1
    旧 = '} else if (token.name() == names.provides) {'
    新 = '} else if (isSoft(token.name(), names.provides)) {' }
$对 += [pscustomobject]@{ 说明 = '模块指令：with'; 次 = 1
    旧 = 'if (token.kind == IDENTIFIER && token.name() == names.with) {'
    新 = 'if (token.kind == IDENTIFIER && isSoft(token.name(), names.with)) {' }
$对 += [pscustomobject]@{ 说明 = '模块指令：uses'; 次 = 1
    旧 = '} else if (token.name() == names.uses) {'
    新 = '} else if (isSoft(token.name(), names.uses)) {' }
$对 += [pscustomobject]@{ 说明 = '模块导入：module'; 次 = 1
    旧 = '} else if (token.kind == IDENTIFIER && token.name() == names.module &&'
    新 = '} else if (token.kind == IDENTIFIER && isSoft(token.name(), names.module) &&' }
$对 += [pscustomobject]@{ 说明 = 'permits 子句'; 次 = 1
    旧 = 'if (allowSealedTypes && token.kind == IDENTIFIER && token.name() == names.permits) {'
    新 = 'if (allowSealedTypes && token.kind == IDENTIFIER && isSoft(token.name(), names.permits)) {' }
$对 += [pscustomobject]@{ 说明 = 'record 声明起点'; 次 = 1
    旧 = 'if (token.kind == IDENTIFIER && token.name() == names.record && peekToken(TokenKind.IDENTIFIER)) {'
    新 = 'if (token.kind == IDENTIFIER && isSoft(token.name(), names.record) && peekToken(TokenKind.IDENTIFIER)) {' }
$对 += [pscustomobject]@{ 说明 = 'non-sealed 序列里的 sealed'; 次 = 1
    旧 = 'tokenSealed.name() == names.sealed) {'
    新 = 'isSoft(tokenSealed.name(), names.sealed)) {' }
$对 += [pscustomobject]@{ 说明 = 'value 修饰符起点'; 次 = 1
    旧 = 'if (token.kind == IDENTIFIER && token.name() == names.value) {'
    新 = 'if (token.kind == IDENTIFIER && isSoft(token.name(), names.value)) {' }
$对 += [pscustomobject]@{ 说明 = 'value 后跟 record/value'; 次 = 1
    旧 = 'if (next.name() == names.record || next.name() == names.value'
    新 = 'if (isSoft(next.name(), names.record) || isSoft(next.name(), names.value)' }
$对 += [pscustomobject]@{ 说明 = 'sealed 声明起点'; 次 = 1
    旧 = '        if (token.name() == names.sealed) {'
    新 = '        if (isSoft(token.name(), names.sealed)) {' }
$对 += [pscustomobject]@{ 说明 = 'sealed 后跟 sealed'; 次 = 1
    旧 = '                        next.name() == names.sealed ||'
    新 = '                        isSoft(next.name(), names.sealed) ||' }
$对 += [pscustomobject]@{ 说明 = 'sealed 后跟 value'; 次 = 1
    旧 = 'allowValueClasses && next.name() == names.value;'
    新 = 'allowValueClasses && isSoft(next.name(), names.value);' }
$对 += [pscustomobject]@{ 说明 = 'non-sealed 起点：中文是 1 个 token'; 次 = 1
    旧 = '            Token next = S.token(3);'
    新 = '            Token next = (zhNonSealed != null && token.name() == zhNonSealed) ? S.token(1) : S.token(3);' }
$对 += [pscustomobject]@{ 说明 = 'non-sealed 识别：接受中文单 token'; 次 = 1
    旧 = @'
        return false;
    }

    protected boolean isValueModifier() {
'@
    新 = @'
        // ChineseJava：中文「非密封」是一个 token，等价于英文 non-sealed 三 token 序列
        if (zhNonSealed != null && someToken.name() == zhNonSealed) {
            checkSourceLevel(Feature.SEALED_CLASSES);
            return true;
        }
        return false;
    }

    protected boolean isValueModifier() {
'@ }

$对 += [pscustomobject]@{ 说明 = 'non-sealed 修饰符位：中文只占 1 token'; 次 = 1
    旧 = @'
                if (isNonSealedClassStart(false)) {
                    flag = Flags.NON_SEALED;
                    nextToken();
                    nextToken();
                    break;
                }
'@
    新 = @'
                if (isNonSealedClassStart(false)) {
                    flag = Flags.NON_SEALED;
                    if (zhNonSealed != null && token.name() == zhNonSealed) {
                        // ChineseJava：中文「非密封」是一个 token，交给循环末尾的 nextToken()
                    } else {
                        nextToken();
                        nextToken();
                    }
                    break;
                }
'@ }
$对 += [pscustomobject]@{ 说明 = 'non-sealed 局部类位：中文只占 1 token'; 次 = 1
    旧 = @'
                if (isNonSealedClassStart(true)) {
                    log.error(token.pos, Errors.SealedOrNonSealedLocalClassesNotAllowed);
                    nextToken();
                    nextToken();
                    nextToken();
'@
    新 = @'
                if (isNonSealedClassStart(true)) {
                    boolean zhNonSealedForm = zhNonSealed != null && token.name() == zhNonSealed;
                    log.error(token.pos, Errors.SealedOrNonSealedLocalClassesNotAllowed);
                    nextToken();
                    if (!zhNonSealedForm) {
                        nextToken();
                        nextToken();
                    }
'@ }

# ---------- 三、应用 ----------
$文本 = $原文
$助手次数 = ([regex]::Matches($文本, [regex]::Escape($助手锚))).Count
if ($助手次数 -ne 1) { throw "助手锚点不唯一：$助手次数 处" }
if ($文本.Contains('private Map<Name, Name> zhSoftNames;')) { throw "助手块已存在但标记不匹配，请人工检查" }
$文本 = $文本.Replace($助手锚, $助手新)

$总 = 0
foreach ($p in $对) {
    $n = ([regex]::Matches($文本, [regex]::Escape($p.旧))).Count
    if ($n -ne $p.次) { throw "锚点不匹配：$($p.说明) —— 期望 $($p.次) 处，实际 $n 处" }
    $文本 = $文本.Replace($p.旧, $p.新)
    $总 += $n
    Write-Host ("  [ok] {0,-28} ×{1}" -f $p.说明, $n) -ForegroundColor Green
}

Set-Content -Path $src -Value $文本 -Encoding utf8NoBOM
Write-Host "[ok] 接线完成：助手 1 段 + 替换 $总 处；已写回 JavacParser.java" -ForegroundColor Green
