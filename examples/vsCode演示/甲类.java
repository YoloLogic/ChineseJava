公开 类型 甲类 {

    公开 静态 空型 main(String[] 参数) {
        整数 计数 = 0;

        对于 (整数 i = 0; i < 5; i++) {
            如果 (i % 2 == 0) {
                计数 += i;
            } 否则 {
                计数 -= 1;
            }
        }

        java.util.List<String> 名单 = new java.util.ArrayList<>();
        名单.add("甲");
        名单.add("乙");

        System.out.println("计数 = " + 计数);
        System.out.println("名单 = " + 名单);

        // 中英可以混写：下面这行是纯英文关键字
        for (int j = 0; j < 2; j++) {
            System.out.println("英文 for 也能用 j=" + j);
        }
    }
}
