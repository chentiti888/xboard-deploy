#!/bin/bash

echo "--- 正在配置 Xboard 安装参数 ---"
read -p "请输入域名 (例如 https://www.ailook.com):" APP_URL
read -p "请输入数据库密码:" DB_PASS
read -p "请输入数据库用户名 (默认为 xboard):" DB_USER
[ -z "$DB_USER" ] && DB_USER="xboard"
read -p "请输入数据库名称 (默认为 xboard):" DB_NAME
[ -z "$DB_NAME" ] && DB_NAME="xboard"
read -p "请输入数据库地址 (容器内地址,默认为 xboard-mysql):" DB_HOST
[ -z "$DB_HOST" ] && DB_HOST="xboard-mysql"

RED_PASS=$DB_PASS
PROJECT_DIR="/opt/xboard"
# 生成固定的 APP_KEY
MY_APP_KEY="base64:$(openssl rand -base64 32)"

echo "--- 正在清理并部署 Xboard 环境 ---"

cd $PROJECT_DIR 2>/dev/null
docker compose down -v 2>/dev/null
rm -rf $PROJECT_DIR
mkdir -p $PROJECT_DIR && cd $PROJECT_DIR

cat <<EOF > docker-compose.yml
services:
  xboard:
    image: ghcr.io/chentiti888/xboard:latest
    container_name: xboard-app
    restart: always
    environment:
      APP_URL: $APP_URL
      DB_HOST: $DB_HOST
      DB_PORT: 3306
      DB_DATABASE: $DB_NAME
      DB_USERNAME: $DB_USER
      DB_PASSWORD: $DB_PASS
      REDIS_HOST: xboard-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: $RED_PASS
      APP_KEY: $MY_APP_KEY
    ports:
      - "7001:7001"
    depends_on:
      - $DB_HOST
      - xboard-redis
    networks:
      - xboard-net
  $DB_HOST:
    image: mariadb:10.6
    container_name: $DB_HOST
    restart: always
    environment:
      MYSQL_DATABASE: $DB_NAME
      MYSQL_USER: $DB_USER
      MYSQL_PASSWORD: $DB_PASS
      MYSQL_ROOT_PASSWORD: $DB_PASS
    networks:
      - xboard-net
  xboard-redis:
    image: redis:alpine
    container_name: xboard-redis
    restart: always
    command: redis-server --requirepass $RED_PASS
    networks:
      - xboard-net
networks:
  xboard-net:
    driver: bridge
EOF

docker compose up -d
echo "等待数据库启动中..."
sleep 25

echo "正在注入配置文件 ($DB_HOST)..."
docker exec -it xboard-app /bin/sh -c "cat <<EOF > /www/.env
APP_NAME=Xboard
APP_ENV=production
APP_KEY=$MY_APP_KEY
APP_DEBUG=false
APP_URL=$APP_URL
DB_CONNECTION=mysql
DB_HOST=$DB_HOST
DB_PORT=3306
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS
REDIS_HOST=xboard-redis
REDIS_PORT=6379
REDIS_PASSWORD=$RED_PASS
EOF"

echo "正在执行系统初始化..."
docker exec -it xboard-app php artisan xboard:install

echo "正在执行域名绑定..."
docker exec -it xboard-app sed -i "s|^APP_URL=.*|APP_URL=$APP_URL|g" /www/.env
docker restart xboard-app

echo "--- 部署完成！ ---"
