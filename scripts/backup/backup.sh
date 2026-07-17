#!/bin/bash
# ============================================================
# GitHub 仓库批量备份脚本
# adminlove520 全量备份 | 2025-07-17
#
# 用法（本地电脑或任意稳定环境跑）:
#   bash backup.sh
#
# 依赖: git（系统自带）
# 注意: 需要网络能访问 github.com
# ============================================================

set -euo pipefail

# ---- 配置 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="${PROJECT_DIR}/github_backup_$(date +%Y%m%d)"
REPO_LIST="${PROJECT_DIR}/data/repo_list.txt"
DONE_FILE="$BACKUP_DIR/.done.txt"
FAIL_FILE="$BACKUP_DIR/.fail.txt"
LOG_FILE="$BACKUP_DIR/backup.log"
MAX_PARALLEL=4
GITHUB_USER="adminlove520"
CLONE_DELAY=1
# --------------

mkdir -p "$BACKUP_DIR"
: > "$LOG_FILE"
: > "$DONE_FILE"
: > "$FAIL_FILE"

if [ ! -f "$REPO_LIST" ]; then
    echo "[错误] 找不到仓库列表: $REPO_LIST"
    exit 1
fi

total=$(wc -l < "$REPO_LIST")
echo "========================================"
echo "GitHub 仓库备份"
echo "用户: $GITHUB_USER"
echo "仓库数: $total"
echo "备份目录: $BACKUP_DIR"
echo "========================================"
echo ""

clone_one() {
    local repo=$1
    local target="$BACKUP_DIR/${repo}.git"
    local log="$BACKUP_DIR/repo_log_${repo}.txt"

    if [ -d "$target" ]; then
        echo "[跳过-已存在] $repo"
        return 0
    fi

    local start=$(date +%s)
    echo -n "[克隆中] $repo ... "

    if git clone --mirror "https://github.com/$GITHUB_USER/${repo}.git" "$target" > "$log" 2>&1; then
        local size=$(du -sh "$target" 2>/dev/null | cut -f1)
        local cost=$(( $(date +%s) - start ))
        echo "[成功] $repo (${size}, ${cost}s)"
        echo "[成功] $repo (${size}, ${cost}s)" >> "$LOG_FILE"
        echo "$repo" >> "$DONE_FILE"
    else
        local cost=$(( $(date +%s) - start ))
        echo "[失败] $repo (退出码:$?, ${cost}s) → 日志: $log"
        echo "[失败] $repo (${cost}s)" >> "$LOG_FILE"
        echo "$repo" >> "$FAIL_FILE"
    fi
}
export -f clone_one

export BACKUP_DIR LOG_FILE DONE_FILE FAIL_FILE

done_cnt=0
fail_cnt=0
skip_cnt=0

while IFS= read -r repo || [ -n "$repo" ]; do
    # 跳过空行
    [ -z "$repo" ] && continue

    # 跳过已存在的
    if [ -d "$BACKUP_DIR/${repo}.git" ]; then
        echo "[跳过-已存在] $repo"
        continue
    fi

    clone_one "$repo"
    done_cnt=$((done_cnt + 1))

    # 每20个显示一次进度
    if [ $((done_cnt % 20)) -eq 0 ]; then
        echo ""
        echo ">>> 进度: $done_cnt/$total | 失败: $(wc -l < "$FAIL_FILE") | 跳过: $skip_cnt <<<"
        echo ""
    fi

    # 每次克隆后等一下，避免触发GitHub限速
    sleep $CLONE_DELAY

done < "$REPO_LIST"

echo ""
echo "========================================"
echo "备份完成 $(date)"
echo "========================================"
echo "成功: $(wc -l < "$DONE_FILE") 个"
echo "失败: $(wc -l < "$FAIL_FILE") 个"
echo "备份目录: $BACKUP_DIR"
echo "备份总大小:"
du -sh "$BACKUP_DIR"
echo ""
if [ $(wc -l < "$FAIL_FILE") -gt 0 ]; then
    echo "失败仓库列表:"
    cat "$FAIL_FILE"
    echo ""
    echo "重新克隆失败的仓库:"
    echo "  cd $BACKUP_DIR"
    echo "  while read r; do git clone --mirror \"https://github.com/$GITHUB_USER/\${r}.git\" \"\${r}.git\"; sleep 2; done < .fail.txt"
fi
