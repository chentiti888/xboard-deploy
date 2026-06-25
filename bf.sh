#!/bin/bash

# --- 配置区域 ---
PROJECT_DIR="/opt/xboard"
BACKUP_DIR="/root/xboard_backup"
LOG_FILE="/root/backup.log"
REMOTE_USER="root"
REMOTE_IP="43.99.98.251"
REMOTE_PATH="/root/xboard_remote_backups"
DB_CONTAINER="woaini"
DB_USER="mini"
DB_PASS="Aa332623888"
DB_NAME="mini"

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/xboard_backup_$DATE.tar.gz"

# (Cron 管理部分保持不变，省略...)

# --- 2. 备份逻辑 (优化) ---
mkdir -p "$BACKUP_DIR"
echo "正在导出数据库..."
# 加入 --single-transaction 保证数据库一致性，不锁表不影响业务
docker exec "$DB_CONTAINER" /usr/bin/mysqldump --single-transaction --quick -u"$DB_USER" --password="$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/db.sql"

echo "正在压缩配置与数据..."
tar -czf "$BACKUP_FILE" -C "$PROJECT_DIR" docker-compose.yml -C "$BACKUP_DIR" db.sql

# --- 3. 远程同步与清理 ---
echo "正在上传至远端服务器..."
# 注意：若未做免密登录，这里需要手动输入密码，定时任务将失败
scp "$BACKUP_FILE" "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"

if [ $? -eq 0 ]; then
    echo "远程传输成功！正在执行清理..."
    find "$BACKUP_DIR" -name "xboard_backup_*.tar.gz" ! -name "$(basename "$BACKUP_FILE")" -type f -delete
    rm -f "$BACKUP_DIR/db.sql"
    # 远程清理
    ssh "$REMOTE_USER@$REMOTE_IP" "ls -t $REMOTE_PATH/xboard_backup_*.tar.gz | tail -n +2 | xargs rm -f"
    echo "--- 流程完成 ---"
else
    echo "错误: 传输失败。请检查是否已配置 SSH 免密登录 (ssh-copy-id)。"
fi
