# -*- coding: utf-8 -*-
"""
Web 构建后处理：给 PWA 加自动更新能力（gh-pages 快速迭代部署用）。

问题背景：Godot 生成的 Service Worker 是 cache-first（命中缓存永不回源），
且浏览器对 SW 脚本最多 24 小时才检查一次更新——连续部署多次时，
用户手机会一直跑第一次访问时缓存的旧版本。

补丁内容：
1. index.service.worker.js
   - install 时 skipWaiting()     ：新版 SW 不等旧标签页关闭，立即接管
   - activate 时 clients.claim()  ：立即控制已打开页面（触发 controllerchange）
2. index.html 注入 <script>
   - 页面加载时主动调 registration.update()（绕过 24h 节流，立即检查新版）
   - 监听 controllerchange 自动刷新一次（sessionStorage 防循环）

用法：python patch_web_pwa.py   （在 gcj 根目录，导出后、push gh-pages 前执行）
"""
import io
import os
import sys

WEB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "game", "build", "web")


def patch(path: str, anchor: str, replacement: str, desc: str, marker: str) -> bool:
    fp = os.path.join(WEB, path)
    with io.open(fp, "r", encoding="utf-8") as f:
        src = f.read()
    if marker in src:
        print(f"  [跳过] {desc}（已有补丁）")
        return True
    if anchor not in src:
        print(f"  [失败] {desc}：找不到锚点，Godot 模板可能已变化，需人工检查！")
        return False
    with io.open(fp, "w", encoding="utf-8", newline="\n") as f:
        f.write(src.replace(anchor, replacement, 1))
    print(f"  [完成] {desc}")
    return True


def main() -> int:
    print(f"补丁目标: {WEB}")
    ok = True
    # 1. SW：install 立即接管 + activate 立即认领客户端
    ok &= patch(
        "index.service.worker.js",
        "self.addEventListener('install', (event) => {\n\tevent.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));",
        "self.addEventListener('install', (event) => {\n\tself.skipWaiting();\n\tevent.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));",
        "SW install: skipWaiting",
        "\tself.skipWaiting();\n",
    )
    ok &= patch(
        "index.service.worker.js",
        "self.addEventListener('activate', (event) => {\n\tevent.waitUntil(caches.keys().then(",
        "self.addEventListener('activate', (event) => {\n\tself.clients.claim();\n\tevent.waitUntil(caches.keys().then(",
        "SW activate: clients.claim",
        "self.clients.claim();",
    )
    # 2. index.html：加载即检查更新 + controllerchange 自动刷新
    snippet = (
        "<script>\n"
        "\t// PWA 自动更新（patch_web_pwa.py 注入）：加载即检查新版，新 SW 接管后自动刷新一次\n"
        "\tif ('serviceWorker' in navigator) {\n"
        "\t\tnavigator.serviceWorker.register('index.service.worker.js').then(function (reg) {\n"
        "\t\t\treturn reg.update();\n"
        "\t\t}).catch(function () {});\n"
        "\t\tnavigator.serviceWorker.addEventListener('controllerchange', function () {\n"
        "\t\t\tif (sessionStorage.getItem('_sw_reloaded') === '1') { return; }\n"
        "\t\t\tsessionStorage.setItem('_sw_reloaded', '1');\n"
        "\t\t\tlocation.reload();\n"
        "\t\t});\n"
        "\t}\n"
        "\t</script>"
    )
    ok &= patch("index.html", "</head>", snippet + "\n</head>", "index.html: 自动更新脚本", "_sw_reloaded")
    print("结果:", "全部成功" if ok else "存在失败，禁止直接部署！")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
