/*
 * ChineseJava —— 中文关键字拼写表（OpenJDK 派生作品，许可 GPLv2 + Classpath Exception）
 *
 * 本文件由生成器生成：tools\生成关键字表.ps1
 * 唯一真相：tools\关键字表.tsv —— 禁止手改本文件；要改就改表，然后重跑生成器。
 */

package com.sun.tools.javac.parser;

/**
 * ChineseJava：中文关键字拼写表。
 *
 * 中文不是替换英文，是并列多出来的一种拼写：中文拼写命中后仍回落到**完全未改动**的英文原表，
 * 因此中英两种写法产生同一个 token、同一份字节码。
 *
 * 交替存放：{ 中文, 英文关键字, 中文, 英文关键字, ... }
 */
final class ZhKeywords {
    private ZhKeywords() {}

    /** 硬关键字：与英文同级保留（占标识符空间）。由 Tokens 构造时挂到 keywords 表上。 */
    static final String[] HARD = {
        "抽象", "abstract",
        "断言", "assert",
        "布尔", "boolean",
        "跳出", "break",
        "字节", "byte",
        "情形", "case",
        "捕获", "catch",
        "字符", "char",
        "类型", "class",
        "常量", "const",
        "跳过", "continue",
        "默认", "default",
        "执行", "do",
        "双精度", "double",
        "否则", "else",
        "枚举", "enum",
        "继承", "extends",
        "最终", "final",
        "最终必须", "finally",
        "单精度", "float",
        "对于", "for",
        "跳转", "goto",
        "如果", "if",
        "实现", "implements",
        "导入", "import",
        "属于", "instanceof",
        "整数", "int",
        "接口", "interface",
        "长型", "long",
        "本机", "native",
        "新建", "new",
        "包声明", "package",
        "私有", "private",
        "受保护", "protected",
        "公开", "public",
        "返回", "return",
        "短型", "short",
        "静态", "static",
        "严格浮点", "strictfp",
        "父类", "super",
        "选择", "switch",
        "同步", "synchronized",
        "自身", "this",
        "抛出", "throw",
        "声明抛出", "throws",
        "瞬态", "transient",
        "尝试", "try",
        "空型", "void",
        "易变", "volatile",
        "每当", "while",
        "真值", "true",
        "假值", "false",
        "空值", "null",
    };

    /** 软关键字：位置敏感、不占标识符空间，由解析层消费（批 2b）。 */
    static final String[] SOFT = {
        "自动", "var",
        "产出", "yield",
        "记录", "record",
        "密封", "sealed",
        "许可", "permits",
        "符合", "when",
        "模块", "module",
        "开放", "open",
        "开放包", "opens",
        "依赖", "requires",
        "传递", "transitive",
        "导出", "exports",
        "指向", "to",
        "使用", "uses",
        "提供", "provides",
        "伴随", "with",
        "非密封", "non-sealed",
        "值类", "value",
    };

    /**
     * ChineseJava：若给定名字是**硬**关键字的中文拼写，返回它；否则返回 null。
     *
     * 只查硬关键字：软关键字（记录/密封/自动…）本来就能当标识符，误用不该给提示。
     * 用途：解析层报告语法错误时，补一条"这是关键字，不能用作标识符"的可行动提示。
     */
    static String hardKeyword(String name) {
        for (int i = 0; i < HARD.length; i += 2) {
            if (HARD[i].equals(name)) {
                return name;
            }
        }
        return null;
    }
}