#!/bin/bash

# --- 配置区域 ---
PROJECT_DIR="/opt/xboard"
BACKUP_DIR="/root/xboard_backup"
LOG_FILE="/root/backup.log"
REMOTE_USER="root"
REMOTE_IP="43.22.9.251"
REMOTE_PATH="/root/xboard_remote_backups"
DB_CONTAINER="woai87"
DB_USER="mini"
DB_PASS="Aa8888888-"
DB_NAME="mini"

# 脚本的绝对路径 (请确保文件确实存放在这里)
SCRIPT_PATH="/root/bf.sh"

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/xboard_backup_$DATE.tar.gz"

# --- 1. 自动添加定时任务 ---
# 如果 crontab 中没有此脚本的任务，则自动添加
CRON_JOB="0 3 * * * $SCRIPT_PATH >> $LOG_FILE 2>&1"
if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "定时任务已成功添加到 crontab (每天凌晨 3 点执行)。"
fi

# --- 2. 备份逻辑 ---
mkdir -p "$BACKUP_DIR"
echo "[$(date)] 正在导出数据库..."
# 使用容器内 mysqldump 进行备份
docker exec "$DB_CONTAINER" /usr/bin/mysqldump --single-transaction --quick -u"$DB_USER" --password="$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/db.sql"

echo "正在压缩配置与数据..."
tar -czf "$BACKUP_FILE" -C "$PROJECT_DIR" docker-compose.yml -C "$BACKUP_DIR" db.sql

# --- 3. 远程同步与清理 ---
echo "正在上传至远端服务器..."
scp -o BatchMode=yes -o StrictHostKeyChecking=no "$BACKUP_FILE" "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"

if [ $? -eq 0 ]; then
    echo "远程传输成功！正在执行清理..."
    find "$BACKUP_DIR" -name "xboard_backup_*.tar.gz" ! -name "$(basename "$BACKUP_FILE")" -type f -delete
    rm -f "$BACKUP_DIR/db.sql"
    # 远程清理
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "ls -t $REMOTE_PATH/xboard_backup_*.tar.gz | tail -n +2 | xargs rm -f"
    echo "--- 流程完成 ---"
else
    echo "错误: 传输失败。请确保已配置 SSH 免密登录。"
fi
