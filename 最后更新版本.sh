#!/bin/bash

# 增加颜色输出，方便查看进度
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}--- 正在配置 Xboard 安装参数 ---${NC}"
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
MY_APP_KEY="base64:$(openssl rand -base64 32)"

echo -e "${GREEN}--- 正在部署 Xboard 环境 ---${NC}"
mkdir -p $PROJECT_DIR && cd $PROJECT_DIR

# 写入 docker-compose.yml
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
    networks:
      - xboard-net
    depends_on:
      - $DB_HOST
  $DB_HOST:
    image: mariadb:10.6
    container_name: $DB_HOST
    restart: always
    environment:
      MYSQL_DATABASE: $DB_NAME
      MYSQL_USER: $DB_USER
      MYSQL_PASSWORD: $DB_PASS
      MYSQL_ROOT_PASSWORD: $DB_PASS
    volumes:
      - ./mysql_data:/var/lib/mysql
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

# 使用更稳健的数据库等待检查
echo "等待数据库初始化就绪..."
until docker exec $DB_HOST mysqladmin ping -h localhost -u$DB_USER -p$DB_PASS --silent; do
  sleep 2
done

echo "正在执行系统初始化..."
docker exec -it xboard-app php artisan xboard:install

echo -e "${GREEN}--- 部署完成！ ---${NC}"