"""下载 Noto Sans SC 字体到 assets/fonts（纯标准库）。

路径按脚本位置推导，不再写死旧机器目录。
代理：环境里已有 HTTP(S)_PROXY 就沿用；否则本机常见代理 127.0.0.1:7897 兜底（可改）。
"""
import os
import urllib.request
from pathlib import Path

# 只在没设置时兜底，避免覆盖用户环境
for key in ("HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY"):
    os.environ.setdefault(key, "http://127.0.0.1:7897")

ROOT = Path(__file__).resolve().parent.parent
out_dir = ROOT / "assets" / "fonts"
out_dir.mkdir(parents=True, exist_ok=True)
out = out_dir / "NotoSansSC-Regular.otf"

urls = [
    "https://cdn.jsdelivr.net/gh/googlefonts/noto-cjk@main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
    "https://fastly.jsdelivr.net/gh/googlefonts/noto-cjk@main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
]
for u in urls:
    try:
        print("GET", u, flush=True)
        urllib.request.urlretrieve(u, str(out))
        print("OK", out.stat().st_size, flush=True)
        break
    except Exception as e:
        print("FAIL", type(e).__name__, e, flush=True)
print("exists", out.exists(), flush=True)
