#!/bin/bash

# 更新系统包
sudo apt update

# 安装Git和Docker
sudo apt install -y git docker.io docker-compose

# 添加用户到docker组，以便无需sudo运行Docker命令
sudo usermod -aG docker $USER

# 等待docker组更改生效
newgrp docker

# 克隆vn.py仓库
git clone https://github.com/vnpy/vnpy.git
cd vnpy

# 创建Dockerfile
cat <<EOT > Dockerfile
# 使用官方Python镜像作为基础镜像
FROM python:3.8-slim

# 设置工作目录
WORKDIR /app

# 复制vn.py到容器中
COPY . /app

# 安装依赖
RUN pip install -r requirements.txt

# 暴露端口
EXPOSE 8888

# 运行vn.py
CMD ["python", "run.py"]
EOT

# 构建Docker镜像
docker build -t vnpy .

# 运行Docker容器
docker run -d -p 8888:8888 vnpy

# 打开防火墙端口
sudo ufw allow 8888/tcp
sudo ufw enable

echo "部署完成！"
