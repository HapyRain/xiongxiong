import os
import urllib.request

os.environ["HTTPS_PROXY"] = "http://127.0.0.1:7897"
os.environ["HTTP_PROXY"] = "http://127.0.0.1:7897"
os.environ["ALL_PROXY"] = "http://127.0.0.1:7897"

out_dir = r"D:\xiongxiong\xiongxiong\assets\fonts"
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, "NotoSansSC-Regular.otf")
urls = [
    "https://cdn.jsdelivr.net/gh/googlefonts/noto-cjk@main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
    "https://fastly.jsdelivr.net/gh/googlefonts/noto-cjk@main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
]
for u in urls:
    try:
        print("GET", u, flush=True)
        urllib.request.urlretrieve(u, out)
        print("OK", os.path.getsize(out), flush=True)
        break
    except Exception as e:
        print("FAIL", type(e).__name__, e, flush=True)
print("exists", os.path.exists(out), flush=True)
