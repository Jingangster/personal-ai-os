#!/usr/bin/env bash
# Personal AI OS 一键安装（macOS / Linux）
# 用法： bash install.sh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/vault"
ZIP_URL="https://github.com/Jingangster/personal-ai-os/archive/refs/heads/main.zip"
MIRRORS=("$ZIP_URL" "https://ghfast.top/$ZIP_URL" "https://gh-proxy.com/$ZIP_URL" "https://ghproxy.net/$ZIP_URL")

# ---------- 1. 模板来源 ----------
if [ ! -d "$SRC/00 首页" ]; then
  echo "==> 本地没有模板，开始下载"
  TMP="$(mktemp -d)"
  OK=""
  for m in "${MIRRORS[@]}"; do
    echo "  尝试: $m"
    if curl -sL --max-time 60 -o "$TMP/paios.zip" "$m"; then
      SIZE=$(stat -f%z "$TMP/paios.zip" 2>/dev/null || stat -c%s "$TMP/paios.zip" 2>/dev/null || echo 0)
      if [ "$SIZE" -gt 10000 ]; then OK=1; break; fi
    fi
  done
  [ -n "$OK" ] || { echo "全部下载源失败。请手动下载 ZIP 解压后重跑本脚本。" >&2; exit 1; }
  mkdir -p "$TMP/x"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$TMP/paios.zip" -d "$TMP/x"
  else
    tar -xf "$TMP/paios.zip" -C "$TMP/x"
  fi
  SRC="$(find "$TMP/x" -maxdepth 2 -type d -name vault | head -1)"
  [ -n "$SRC" ] || { echo "ZIP 内容异常" >&2; exit 1; }
  echo "  [OK] 下载并解压完成"
else
  echo "  [OK] 检测到本地模板（离线安装）"
fi

# ---------- 2. 目标库 ----------
echo "==> 选择目标 Obsidian 库"
printf "输入库路径（回车 = 新建 ~/Documents/PersonalAIOS）: "
read -r VP
[ -z "$VP" ] && VP="$HOME/Documents/PersonalAIOS"
mkdir -p "$VP"

# ---------- 3. 复制 ----------
cp -R "$SRC/." "$VP/"
if [ -f "$ROOT/新手必做.md" ]; then
  cp "$ROOT/新手必做.md" "$VP/"
  echo "  [OK] 新手必做.md 已放进库里"
fi
echo "  [OK] 模板已复制到: $VP"

# ---------- 4. 下一步：剪贴板就绪 + 自动打开 ----------
PROMPT_FILE="$VP/prompts/00-工作模式.md"
CLIP="no"
if [ -f "$PROMPT_FILE" ] && command -v pbcopy >/dev/null 2>&1; then
  pbcopy < "$PROMPT_FILE" && CLIP="yes"
fi
echo "================ 安装完成 ================"
if [ "$CLIP" = "yes" ]; then
  echo " 提示词已放进剪贴板。"
  echo " 下一步：打开自动弹出的 AI 网页，Cmd+V 粘贴，发送。完事。"
else
  echo " 下一步：打开 $PROMPT_FILE 全文复制，发给任意 AI。"
fi
echo "=========================================="
if command -v open >/dev/null 2>&1; then
  open "$VP" 2>/dev/null || true
  open "https://chat.deepseek.com" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "https://chat.deepseek.com" 2>/dev/null || true
fi
