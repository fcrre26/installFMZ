#!/bin/bash

# 版本定义
DOCKER_COMPOSE_VERSION="v2.27.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 恢复默认颜色

# 定义函数：安装 Docker 和 Docker Compose
install_docker() {
    echo -e "${YELLOW}[1/6] 正在安装 Docker 和 Docker Compose...${NC}"
    
    # 安装 Docker
    sudo apt update > /dev/null 2>&1
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common > /dev/null 2>&1

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null 2>&1
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /dev/null 2>&1
    sudo apt update > /dev/null 2>&1
    sudo apt install -y docker-ce > /dev/null 2>&1

    # 添加用户到 docker 组
    sudo usermod -aG docker $USER
    echo -e "${GREEN}✓ 已添加当前用户到 docker 组，需要重新登录后生效${NC}"

    # 安装 Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose > /dev/null 2>&1
    sudo chmod +x /usr/local/bin/docker-compose
}

# 定义函数：创建 Freqtrade 数据目录
create_data_directory() {
    echo -e "${YELLOW}[2/6] 创建数据目录...${NC}"
    mkdir -p ~/freqtrade/user_data
    cd ~/freqtrade || exit 1
}

# 定义函数：下载 Docker 配置文件
download_docker_compose() {
    echo -e "${YELLOW}[3/6] 下载 Docker 配置文件...${NC}"
    if ! wget -q -O docker-compose.yml https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml; then
        echo -e "${RED}× 无法下载 docker-compose.yml 文件${NC}"
        exit 1
    fi
}

# 定义函数：创建默认配置文件
create_default_config() {
    echo -e "${YELLOW}[4/6] 生成默认配置文件...${NC}"
    if [ ! -f user_data/config.json ]; then
        cat <<EOF > user_data/config.json
{
    "max_open_trades": 3,
    "stake_currency": "USDT",
    "stake_amount": 100,
    "fiat_display_currency": "USD",
    "dry_run": true,
    "timeframe": "5m",
    "exchange": {
        "name": "binance",
        "key": "YOUR_API_KEY",
        "secret": "YOUR_API_SECRET",
        "ccxt_config": {},
        "ccxt_async_config": {}
    },
    "telegram": {
        "enabled": false
    },
    "api_server": {
        "enabled": false
    }
}
EOF
        echo -e "${GREEN}✓ 配置文件已创建 (user_data/config.json)${NC}"
    else
        echo -e "${YELLOW}⚠ 配置文件已存在，跳过创建${NC}"
    fi
}

# 定义函数：手动编辑配置
edit_config() {
    echo -e "${YELLOW}[5/6] 准备编辑配置文件...${NC}"
    
    # 确保 nano 已安装
    if ! command -v nano &> /dev/null; then
        echo "正在安装 nano 编辑器..."
        sudo apt install -y nano > /dev/null 2>&1
    fi
    
    nano user_data/config.json
    echo -e "${GREEN}✓ 配置文件编辑完成${NC}"
}

# 定义函数：启动容器
start_freqtrade() {
    echo -e "${YELLOW}[6/6] 启动 Freqtrade 容器...${NC}"
    
    # 检查配置文件存在性
    if [ ! -f user_data/config.json ]; then
        echo -e "${RED}× 错误：未找到配置文件 user_data/config.json${NC}"
        exit 1
    fi

    docker-compose up -d
    
    # 显示访问信息
    echo -e "\n${GREEN}启动成功！请按以下步骤操作：${NC}"
    echo "--------------------------------------------------"
    echo "1. Web 界面访问地址:"
    echo -e "   http://$(curl -s ifconfig.me):8080 (公网)"
    echo -e "   http://$(hostname -I | awk '{print $1}'):8080 (内网)"
    echo "   默认凭证：freqtrade/your_api_password"
    echo "--------------------------------------------------"
    echo "2. 检查容器状态：docker-compose ps"
    echo "3. 查看日志：docker-compose logs -f"
    echo "4. 停止容器：docker-compose down"
    echo "--------------------------------------------------"
    echo -e "${YELLOW}注意：首次启动可能需要几分钟下载镜像${NC}"
}

# 显示配置菜单
show_menu() {
    echo -e "\n${YELLOW}请选择配置方式：${NC}"
    echo "1) 自动生成配置文件 (推荐新手)"
    echo "2) 手动编辑配置文件 (推荐有经验用户)"
    echo "3) 跳过配置 (使用现有配置)"
    echo "4) 退出"
    
    while true; do
        read -p "请输入选项 (1-4): " choice
        case $choice in
            1)
                create_default_config
                break
                ;;
            2)
                create_default_config
                edit_config
                break
                ;;
            3)
                echo -e "${YELLOW}⚠ 跳过配置，请确保已有有效配置文件${NC}"
                break
                ;;
            4)
                echo "退出安装"
                exit 0
                ;;
            *)
                echo -e "${RED}无效输入，请重新选择${NC}"
                ;;
        esac
    done
}

# 主程序
main() {
    clear
    echo -e "${GREEN}"
    echo "--------------------------------------------------"
    echo " Freqtrade 自动化安装脚本"
    echo " 版本：2.4.1 | 支持 Ubuntu 20.04/22.04"
    echo "--------------------------------------------------"
    echo -e "${NC}"
    
    # 检查 root 权限
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}错误：请勿使用 root 用户运行本脚本${NC}"
        exit 1
    fi
    
    install_docker
    create_data_directory
    download_docker_compose
    show_menu
    start_freqtrade
}

# 执行主程序
main
