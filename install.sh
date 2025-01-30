#!/bin/bash

# 版本定义
DOCKER_COMPOSE_VERSION="v2.27.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 恢复默认颜色

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：请使用 root 权限运行本脚本 (使用 sudo ./install.sh)${NC}"
        exit 1
    fi
}

# 检查系统兼容性
check_system_compatibility() {
    echo -e "${YELLOW}正在检查系统兼容性...${NC}"
    if ! grep -q "Ubuntu" /etc/os-release; then
        echo -e "${RED}错误：本脚本仅支持 Ubuntu 系统${NC}"
        exit 1
    fi
    
    VERSION=$(lsb_release -rs)
    if [[ "$VERSION" != "20.04" && "$VERSION" != "22.04" ]]; then
        echo -e "${YELLOW}警告：未经测试的 Ubuntu 版本${NC}"
    fi
    echo -e "${GREEN}✓ 系统兼容性检查通过${NC}"
}

# 检查网络连接
check_network() {
    echo -e "${YELLOW}正在检查网络连接...${NC}"
    echo "测试与 github.com 的连接..."
    if ! ping -c 1 github.com; then
        echo -e "${RED}错误：无法连接到 GitHub，请检查网络连接${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ 网络连接正常${NC}"
}

# 定义函数：安装 Docker 和 Docker Compose
install_docker() {
    echo -e "${YELLOW}[1/6] 正在安装 Docker 和 Docker Compose...${NC}"
    
    # 安装 Docker
    echo -e "${GREEN}[1/5] 更新软件包列表...${NC}"
    apt update
    
    echo -e "${GREEN}[2/5] 安装 Docker 依赖包...${NC}"
    apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common

    echo -e "${GREEN}[3/5] 添加 Docker 官方 GPG 密钥和软件源...${NC}"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    
    echo -e "${GREEN}[4/5] 安装 Docker...${NC}"
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io

    # 获取实际运行脚本的用户
    ACTUAL_USER=$(who am i | awk '{print $1}')
    if [ -z "$ACTUAL_USER" ]; then
        ACTUAL_USER=$(logname)
    fi

    # 添加用户到 docker 组
    usermod -aG docker $ACTUAL_USER
    echo -e "${GREEN}✓ 已添加用户 $ACTUAL_USER 到 docker 组，需要重新登录后生效${NC}"

    echo -e "${GREEN}[5/5] 安装 Docker Compose...${NC}"
    # 安装 Docker Compose
    echo "下载 Docker Compose ${DOCKER_COMPOSE_VERSION}..."
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # 验证安装
    echo -e "${GREEN}验证安装...${NC}"
    docker --version
    docker-compose --version
    
    echo -e "${GREEN}✓ Docker 和 Docker Compose 安装完成${NC}"
}

# 定义函数：创建 Freqtrade 数据目录
create_data_directory() {
    echo -e "${YELLOW}[2/6] 创建数据目录...${NC}"
    ACTUAL_USER=$(who am i | awk '{print $1}')
    if [ -z "$ACTUAL_USER" ]; then
        ACTUAL_USER=$(logname)
    fi
    
    echo "创建目录: /home/$ACTUAL_USER/freqtrade"
    FREQTRADE_DIR="/home/$ACTUAL_USER/freqtrade"
    mkdir -p $FREQTRADE_DIR/user_data
    chown -R $ACTUAL_USER:$ACTUAL_USER $FREQTRADE_DIR
    echo -e "${GREEN}✓ 目录创建完成${NC}"
    
    echo "切换到工作目录..."
    cd $FREQTRADE_DIR || exit 1
    echo -e "${GREEN}✓ 目录准备完成${NC}"
}

# 定义函数：下载 Docker 配置文件
download_docker_compose() {
    echo -e "${YELLOW}[3/6] 下载 Docker 配置文件...${NC}"
    echo "从 GitHub 下载 docker-compose.yml..."
    if ! wget -O docker-compose.yml https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml; then
        echo -e "${RED}× 无法下载 docker-compose.yml 文件${NC}"
        exit 1
    fi
    
    ACTUAL_USER=$(who am i | awk '{print $1}')
    if [ -z "$ACTUAL_USER" ]; then
        ACTUAL_USER=$(logname)
    fi
    chown $ACTUAL_USER:$ACTUAL_USER docker-compose.yml
    echo -e "${GREEN}✓ 配置文件下载完成${NC}"
}

# 定义函数：创建默认配置文件
create_default_config() {
    echo -e "${YELLOW}[4/6] 生成默认配置文件...${NC}"
    if [ ! -f user_data/config.json ]; then
        echo "创建新的配置文件..."
        cat > user_data/config.json << 'EOF'
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
        "enabled": false,
        "token": "",
        "chat_id": ""
    },
    "api_server": {
        "enabled": true,
        "listen_ip_address": "0.0.0.0",
        "listen_port": 8080,
        "username": "freqtrade",
        "password": "your_password"
    }
}
EOF

        ACTUAL_USER=$(who am i | awk '{print $1}')
        if [ -z "$ACTUAL_USER" ]; then
            ACTUAL_USER=$(logname)
        fi
        chown $ACTUAL_USER:$ACTUAL_USER user_data/config.json
        echo -e "${GREEN}✓ 配置文件已创建 (user_data/config.json)${NC}"
    else
        echo -e "${YELLOW}⚠ 配置文件已存在，跳过创建${NC}"
    fi
}

# 定义函数：交互式编辑配置
edit_config() {
    echo -e "${YELLOW}[5/6] 开始配置 Freqtrade...${NC}"
    
    # 临时存储用户输入
    local stake_currency
    local stake_amount
    local exchange_key
    local exchange_secret
    local telegram_token
    local telegram_chat_id
    local api_password
    local dry_run

    # 交互式配置
    echo -e "\n${GREEN}=== 基础配置 ===${NC}"
    read -p "交易币种 (默认: USDT): " stake_currency
    stake_currency=${stake_currency:-USDT}
    
    read -p "每次交易金额 (默认: 100): " stake_amount
    stake_amount=${stake_amount:-100}

    echo -e "\n是否启用实盘交易? (y/n)"
    read -p "默认为模拟交易模式 (n): " enable_live
    if [[ $enable_live == "y" || $enable_live == "Y" ]]; then
        dry_run="false"
        echo -e "${YELLOW}警告：您已启用实盘交易模式！${NC}"
    else
        dry_run="true"
        echo -e "${GREEN}已选择模拟交易模式${NC}"
    fi

    echo -e "\n${GREEN}=== 交易所配置 ===${NC}"
    read -p "Binance API Key (必填): " exchange_key
    while [[ -z "$exchange_key" ]]; do
        echo -e "${RED}API Key 不能为空${NC}"
        read -p "Binance API Key (必填): " exchange_key
    done

    read -p "Binance API Secret (必填): " exchange_secret
    while [[ -z "$exchange_secret" ]]; do
        echo -e "${RED}API Secret 不能为空${NC}"
        read -p "Binance API Secret (必填): " exchange_secret
    done

    echo -e "\n${GREEN}=== Telegram 配置 ===${NC}"
    echo "是否启用 Telegram 通知? (y/n)"
    read -p "默认: n: " enable_telegram
    if [[ $enable_telegram == "y" || $enable_telegram == "Y" ]]; then
        read -p "Telegram Bot Token: " telegram_token
        while [[ -z "$telegram_token" ]]; do
            echo -e "${RED}Bot Token 不能为空${NC}"
            read -p "Telegram Bot Token: " telegram_token
        done

        read -p "Telegram Chat ID: " telegram_chat_id
        while [[ -z "$telegram_chat_id" ]]; do
            echo -e "${RED}Chat ID 不能为空${NC}"
            read -p "Telegram Chat ID: " telegram_chat_id
        done
    fi

    echo -e "\n${GREEN}=== Web UI 配置 ===${NC}"
    read -p "Web UI 密码 (默认: your_password): " api_password
    api_password=${api_password:-your_password}

    # 创建新的配置文件
    cat > user_data/config.json << EOF
{
    "max_open_trades": 3,
    "stake_currency": "${stake_currency}",
    "stake_amount": ${stake_amount},
    "fiat_display_currency": "USD",
    "dry_run": ${dry_run},
    "timeframe": "5m",
    "exchange": {
        "name": "binance",
        "key": "${exchange_key}",
        "secret": "${exchange_secret}",
        "ccxt_config": {},
        "ccxt_async_config": {}
    },
    "telegram": {
        "enabled": $([[ $enable_telegram == "y" || $enable_telegram == "Y" ]] && echo "true" || echo "false"),
        "token": "${telegram_token:-}",
        "chat_id": "${telegram_chat_id:-}"
    },
    "api_server": {
        "enabled": true,
        "listen_ip_address": "0.0.0.0",
        "listen_port": 8080,
        "username": "freqtrade",
        "password": "${api_password}"
    }
}
EOF

    ACTUAL_USER=$(who am i | awk '{print $1}')
    if [ -z "$ACTUAL_USER" ]; then
        ACTUAL_USER=$(logname)
    fi
    chown $ACTUAL_USER:$ACTUAL_USER user_data/config.json

    echo -e "${GREEN}✓ 配置文件已更新${NC}"
    echo -e "${YELLOW}提示：配置文件保存在 user_data/config.json${NC}"
}

# 定义函数：启动容器
start_freqtrade() {
    echo -e "${YELLOW}[6/6] 启动 Freqtrade 容器...${NC}"
    
    # 检查配置文件存在性
    if [ ! -f user_data/config.json ]; then
        echo -e "${YELLOW}⚠ 未找到配置文件，将创建默认配置...${NC}"
        create_default_config
    fi

    ACTUAL_USER=$(who am i | awk '{print $1}')
    if [ -z "$ACTUAL_USER" ]; then
        ACTUAL_USER=$(logname)
    fi
    
    echo "启动 Docker 容器..."
    # 使用实际用户启动 docker-compose
    sudo -u $ACTUAL_USER docker-compose up -d
    
    echo "等待容器启动..."
    sleep 5
    
    echo "检查容器状态..."
    docker-compose ps
    
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
    echo "2) 交互式配置 (推荐有经验用户)"
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
    
    check_root
    check_system_compatibility
    check_network
    
    install_docker
    create_data_directory
    download_docker_compose
    show_menu
    start_freqtrade
}

# 执行主程序
main
