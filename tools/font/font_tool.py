"""中文字体子集工具。
python3 tools/font/font_tool.py build <NotoSansSC[wght].ttf>   # 从完整字体重新生成子集
python3 tools/font/font_tool.py check                          # 检查代码/数据里的所有字符都在子集里（测试会跑）
依赖 fonttools。"""
import glob, sys, subprocess, os
OUT = "assets/fonts/NotoSansSC-Greybox.ttf"
EXTRA = "，。！？：；“”‘’（）【】《》、…—·×→←↑↓✓×♪％＋－⚠"

def used_chars():
    chars = set(chr(c) for c in range(0x20, 0x7f)) | set(EXTRA)
    files = glob.glob("**/*.gd", recursive=True) + glob.glob("**/*.tres", recursive=True) + glob.glob("**/*.tscn", recursive=True)
    for f in files:
        if f.startswith(("tests/", ".godot/", "legacy_greybox1/")):
            continue
        for ch in open(f, encoding="utf-8").read():
            if ord(ch) > 0x7f and ch not in "\ufeff":
                chars.add(ch)
    return chars

if sys.argv[1] == "build":
    open("/tmp/greybox_chars.txt", "w", encoding="utf-8").write("".join(sorted(used_chars())))
    subprocess.check_call([sys.executable, "-m", "fontTools.varLib.instancer", sys.argv[2], "wght=500", "-o", "/tmp/greybox_med.ttf", "-q"])
    subprocess.check_call(["pyftsubset", "/tmp/greybox_med.ttf", "--text-file=/tmp/greybox_chars.txt", f"--output-file={OUT}", "--layout-features=*"])
    print("子集已生成：", OUT, os.path.getsize(OUT), "字节")
else:
    from fontTools.ttLib import TTFont
    cmap = TTFont(OUT).getBestCmap()
    miss = sorted(c for c in used_chars() if ord(c) not in cmap and not c.isspace())
    if miss:
        print("字体缺字：", "".join(miss)); sys.exit(1)
    print("字体覆盖检查通过")
