record 点(int 横, int 纵) { }

sealed interface 形状 permits 圆, 方 {
    double 面积();
}

non-sealed class 圆 implements 形状 {
    public double 面积() { return 3.14 * 2 * 2; }
}

final class 方 implements 形状 {
    public double 面积() { return 4.0 * 4.0; }
}

public class 甲类 {
    public static void main(String[] 参数) {
        var 甲 = new 点(3, 4);
        形状[] 图形 = { new 圆(), new 方() };
        for (形状 形 : 图形) {
            System.out.println("面积 = " + 形.面积());
        }
        int 判定 = switch (甲) {
            case 点(int 横, int 纵) when 横 > 0 -> 横 + 纵;
            default -> 0;
        };
        System.out.println("判定 = " + 判定);
        return;
    }
}
