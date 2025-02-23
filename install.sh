#!/usr/bin/env bash
#encoding=utf8

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'   # No Color

function echo_block() {
    echo "----------------------------"
    echo $1
    echo "----------------------------"
}

function check_installed_pip() {
   ${PYTHON} -m pip > /dev/null
   if [ $? -ne 0 ]; then
        echo_block "正在为 ${PYTHON} 安装 Pip"
        curl https://bootstrap.pypa.io/get-pip.py -s -o get-pip.py
        ${PYTHON} get-pip.py
        rm get-pip.py
   fi
}

function check_installed_python() {
    if [ -n "${VIRTUAL_ENV}" ]; then
        echo "运行 setup.sh 之前请先退出虚拟环境。"
        echo "您可以通过运行 'deactivate' 命令来实现。"
        exit 2
    fi

    for v in 12 11 10
    do
        PYTHON="python3.${v}"
        which $PYTHON
        if [ $? -eq 0 ]; then
            echo "使用 ${PYTHON}"
            check_installed_pip
            return
        fi
    done

    echo "未找到可用的 Python。请确保安装了 Python 3.10 或更新版本。"
    exit 1
}

function updateenv() {
    echo_block "正在更新您的虚拟环境"
    if [ ! -f .venv/bin/activate ]; then
        echo "出现错误，未找到虚拟环境。"
        exit 1
    fi
    source .venv/bin/activate
    SYS_ARCH=$(uname -m)
    echo "pip 安装进行中，请稍候..."
    ${PYTHON} -m pip install --upgrade pip wheel setuptools
    REQUIREMENTS_HYPEROPT=""
    REQUIREMENTS_PLOT=""
    REQUIREMENTS_FREQAI=""
    REQUIREMENTS_FREQAI_RL=""
    REQUIREMENTS=requirements.txt

    # 自动选择完整安装
    echo "选择完整安装（包含所有依赖）"
    REQUIREMENTS=requirements-dev.txt

    install_talib

    ${PYTHON} -m pip install --upgrade -r ${REQUIREMENTS} ${REQUIREMENTS_HYPEROPT} ${REQUIREMENTS_PLOT} ${REQUIREMENTS_FREQAI} ${REQUIREMENTS_FREQAI_RL}
    if [ $? -ne 0 ]; then
        echo "安装依赖失败"
        exit 1
    fi
    ${PYTHON} -m pip install -e .
    if [ $? -ne 0 ]; then
        echo "安装 Freqtrade 失败"
        exit 1
    fi

    echo "正在安装 freqUI"
    freqtrade install-ui

    echo "pip 安装完成"
    echo
    
    # 自动安装 pre-commit
    ${PYTHON} -m pre_commit install
    if [ $? -ne 0 ]; then
        echo "安装 pre-commit 失败"
        exit 1
    fi
}

function install_talib() {
    if [ -f /usr/local/lib/libta_lib.a ] || [ -f /usr/local/lib/libta_lib.so ] || [ -f /usr/lib/libta_lib.so ]; then
        echo "ta-lib 已安装，跳过"
        return
    fi

    cd build_helpers && ./install_ta-lib.sh

    if [ $? -ne 0 ]; then
        echo "退出。继续之前请修复上述错误。"
        cd ..
        exit 1
    fi;

    cd ..
}

function install_macos() {
    if [ ! -x "$(command -v brew)" ]
    then
        echo_block "正在安装 Brew"
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi

    brew install gettext libomp

    version=$(egrep -o 3.\[0-9\]+ <<< $PYTHON | sed 's/3.//g')
}

function install_debian() {
    sudo apt-get update
    sudo apt-get install -y gcc build-essential autoconf libtool pkg-config make wget git curl $(echo lib${PYTHON}-dev ${PYTHON}-venv)
}

function install_redhat() {
    sudo yum update
    sudo yum install -y gcc gcc-c++ make autoconf libtool pkg-config wget git $(echo ${PYTHON}-devel | sed 's/\.//g')
}

function update() {
    git pull
    if [ -f .env/bin/activate  ]; then
        recreate_environments
    fi
    updateenv
    echo "更新完成。"
    echo_block "别忘了使用 'source .venv/bin/activate' 激活虚拟环境！"
}

function check_git_changes() {
    if [ -z "$(git status --porcelain)" ]; then
        echo "Git 目录中没有变更"
        return 1
    else
        echo "Git 目录中有变更"
        return 0
    fi
}

function recreate_environments() {
    if [ -d ".env" ]; then
        echo "- 正在删除旧的虚拟环境"
        echo "注意：新的环境将位于 .venv！"
        rm -rf .env
    fi
    if [ -d ".venv" ]; then
        echo "- 正在删除旧的虚拟环境"
        rm -rf .venv
    fi

    echo
    ${PYTHON} -m venv .venv
    if [ $? -ne 0 ]; then
        echo "无法创建虚拟环境。正在退出"
        exit 1
    fi
}

function reset() {
    echo_block "正在重置分支和虚拟环境"

    if [ "1" == $(git branch -vv |grep -cE "\* develop|\* stable") ]
    then
        if check_git_changes; then
            read -p "是否保留本地更改？（否则将删除您所做的所有更改！）[Y/n]？"
            if [[ $REPLY =~ ^[Nn]$ ]]; then

                git fetch -a

                if [ "1" == $(git branch -vv | grep -c "* develop") ]
                then
                    echo "- 正在硬重置 'develop' 分支。"
                    git reset --hard origin/develop
                elif [ "1" == $(git branch -vv | grep -c "* stable") ]
                then
                    echo "- 正在硬重置 'stable' 分支。"
                    git reset --hard origin/stable
                fi
            fi
        fi
    else
        echo "因为您不在 'stable' 或 'develop' 分支上，跳过重置。"
    fi
    recreate_environments

    updateenv
}

function config() {
    echo_block "请使用 'freqtrade new-config -c user_data/config.json' 生成新的配置文件。"
}

function install() {
    echo_block "正在安装必要依赖"

    if [ "$(uname -s)" == "Darwin" ]; then
        echo "检测到 macOS。正在为该系统进行设置"
        install_macos
    elif [ -x "$(command -v apt-get)" ]; then
        echo "检测到 Debian/Ubuntu。正在为该系统进行设置"
        install_debian
    elif [ -x "$(command -v yum)" ]; then
        echo "检测到 Red Hat/CentOS。正在为该系统进行设置"
        install_redhat
    else
        echo "此脚本不支持您的操作系统。"
        echo "如果您已安装 Python 3.10 - 3.12、pip、virtualenv、ta-lib，则可以继续。"
        echo "等待 10 秒继续下一步安装，或使用 ctrl+c 中断。"
        sleep 10
    fi
    
    # 添加克隆代码仓库的步骤
    echo_block "克隆 Freqtrade 代码仓库"
    if [ ! -d "freqtrade" ]; then
        git clone https://github.com/freqtrade/freqtrade.git
        cd freqtrade
    else
        echo "freqtrade 目录已存在"
        cd freqtrade
        git fetch -a
    fi

    # 切换到稳定分支
    git checkout stable

    echo
    reset
    config
    echo_block "运行机器人！"
    echo "现在您可以通过执行 'source .venv/bin/activate; freqtrade <子命令>' 来使用机器人。"
    echo "您可以通过执行 'source .venv/bin/activate; freqtrade --help' 查看可用的机器人子命令列表。"
    echo "您可以通过运行 'source .venv/bin/activate; freqtrade --version' 验证 freqtrade 是否安装成功。"
    
    # 等待用户确认
    echo
    read -p "安装完成！按回车键返回主菜单..."
    show_menu
}

function plot() {
    echo_block "正在安装绘图脚本依赖"
    ${PYTHON} -m pip install plotly --upgrade
}

function help() {
    echo "用法："
    echo "	-i,--install    从头安装 freqtrade"
    echo "	-u,--update     执行 git pull 进行更新"
    echo "	-r,--reset      硬重置您的 develop/stable 分支"
    echo "	-c,--config     简易配置生成器（将覆盖现有文件）"
    echo "	-p,--plot       安装绘图脚本依赖"
    echo
    echo "提示：运行脚本时不带参数将启动交互式菜单。"
}

function check_freqtrade_dir() {
    if [ ! -d "freqtrade" ]; then
        echo -e "${RED}错误: 未找到 freqtrade 目录${NC}"
        echo "请先运行安装选项 (1) 从头安装 Freqtrade"
        return 1
    fi
    
    # 如果不在 freqtrade 目录下，则切换到该目录
    if [ "$(basename $PWD)" != "freqtrade" ]; then
        cd freqtrade
        echo "已切换到 freqtrade 目录"
    fi
    return 0
}

# 统一的环境检查函数
function check_environment() {
    # 检查 freqtrade 目录
    if [ -d "/root/freqtrade" ]; then
        cd /root/freqtrade
    elif [ -d "freqtrade" ]; then
        cd freqtrade
    elif [ "$(basename $PWD)" != "freqtrade" ]; then
        echo -e "${RED}错误: 未找到 freqtrade 目录${NC}"
        return 1
    fi

    # 检查虚拟环境
    if [ ! -f ".venv/bin/activate" ]; then
        echo -e "${RED}错误: 虚拟环境未找到${NC}"
        return 1
    fi

    # 激活虚拟环境并检查 freqtrade 命令
    source .venv/bin/activate
    if ! command -v freqtrade >/dev/null 2>&1; then
        deactivate
        echo -e "${RED}错误: freqtrade 命令未找到${NC}"
        return 1
    fi
    deactivate

    return 0
}

function generate_config() {
    echo_block "生成配置文件"
    
    # 确保在正确目录并检查环境
    local current_dir=$(pwd)
    if ! check_environment; then
        echo -e "${RED}错误: 环境检查失败${NC}"
        read -p "是否要安装 Freqtrade？[Y/n] " choice
        if [[ ! $choice =~ ^[Nn]$ ]]; then
            install_freqtrade
            if ! check_environment; then
                echo -e "${RED}安装失败，请检查错误信息${NC}"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    # 激活虚拟环境
    source .venv/bin/activate
    
    # 设置默认值
    local dry_run="false"  # 默认实盘交易
    local stake_currency="USDT"
    local stake_amount="unlimited"
    local max_trades=1     # 默认最大1个仓位
    local exchange="binance"
    local pairs="BTC/USDT"
    local strategy="SampleStrategy"
    local freqtrade_path="/root/freqtrade"
    
    # 配置文件路径
    local config_path="${freqtrade_path}/user_data/config.json"
    read -p "请输入配置文件路径 [${config_path}]: " input
    config_path=${input:-$config_path}
    echo -e "${GREEN}已设置: 配置文件路径 = ${config_path}${NC}"
    echo
    
    echo "请回答以下问题来生成配置文件："
    echo "（直接回车将使用 [括号] 内的默认值）"
    echo
    
    # 模拟交易模式
    read -p "是否启用模拟交易模式？[N/y] (默认: 实盘交易): " input
    if [[ $input =~ ^[Yy]$ ]]; then
        dry_run="true"
        echo -e "${GREEN}已设置: 模拟交易${NC}"
    else
        echo -e "${GREEN}已设置: 实盘交易${NC}"
    fi
    
    # 交易币种
    read -p "请输入交易币种 [${stake_currency}]: " input
    stake_currency=${input:-$stake_currency}
    echo -e "${GREEN}已设置: 交易币种 = ${stake_currency}${NC}"
    
    # 交易金额
    read -p "请输入每次交易金额（数字或'unlimited'）[${stake_amount}]: " input
    stake_amount=${input:-$stake_amount}
    echo -e "${GREEN}已设置: 交易金额 = ${stake_amount}${NC}"
    
    # 最大开仓数
    read -p "请输入最大同时开仓数 [${max_trades}] (默认: 1个仓位): " input
    max_trades=${input:-$max_trades}
    echo -e "${GREEN}已设置: 最大开仓数 = ${max_trades}${NC}"
    
    # 交易所选择
    echo -e "\n支持的交易所:"
    echo "1) Binance (推荐)"
    echo "2) Huobi"
    echo "3) OKX"
    echo "4) 其他"
    read -p "请选择交易所 [1] (默认: Binance): " input
    case $input in
        2) exchange="huobi";;
        3) exchange="okx";;
        4) read -p "请输入交易所名称: " exchange;;
        *) exchange="binance";;
    esac
    echo -e "${GREEN}已设置: 交易所 = ${exchange}${NC}"
    
    # 交易所选择后添加 API 配置
    echo -e "${GREEN}已设置: 交易所 = ${exchange}${NC}"
    
    # 如果是实盘交易，提示输入 API 密钥
    local api_key=""
    local api_secret=""
    if [ "$dry_run" = "false" ]; then
        echo -e "\n${YELLOW}注意: 实盘交易需要配置交易所 API 密钥${NC}"
        read -p "请输入 API Key: " api_key
        read -p "请输入 API Secret: " api_secret
        echo -e "${GREEN}已设置: API 配置${NC}"
    fi
    
    # 交易对
    read -p "请输入交易对(例如: BTC/USDT ETH/USDT) [${pairs}]: " input
    pairs=${input:-$pairs}
    echo -e "${GREEN}已设置: 交易对 = ${pairs}${NC}"
    
    # 策略选择
    echo -e "\n常用策略:"
    echo "1) SampleStrategy (样例策略)"
    echo "2) 自定义策略"
    read -p "请选择策略 [1] (默认: 示例策略): " strategy_choice
    
    if [ "$strategy_choice" = "2" ]; then
        read -p "请输入策略类名: " strategy
        local strategy_dir="${freqtrade_path}/user_data/strategies"
        local strategy_file="${strategy_dir}/${strategy}.py"
        mkdir -p "$strategy_dir"
        cp -n "${freqtrade_path}/freqtrade/templates/sample_strategy.py" "$strategy_file"
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 策略创建失败${NC}"
            return 1
        fi
        echo -e "${GREEN}已设置: 自定义策略 = ${strategy}${NC}"
        echo -e "${GREEN}策略文件已创建: ${strategy_file}${NC}"
    else
        strategy="SampleStrategy"
        echo -e "${GREEN}已设置: 使用示例策略${NC}"
    fi
    
    # 生成配置文件
    echo -e "\n${GREEN}配置总结:${NC}"
    echo "--------------------------------"
    echo -e "${GREEN}配置文件: ${config_path}${NC}"
    echo -e "${GREEN}交易模式: $([ "$dry_run" = "true" ] && echo "模拟交易" || echo "实盘交易")${NC}"
    echo -e "${GREEN}交易币种: ${stake_currency}${NC}"
    echo -e "${GREEN}交易金额: ${stake_amount}${NC}"
    echo -e "${GREEN}最大开仓: ${max_trades}${NC}"
    echo -e "${GREEN}交易所  : ${exchange}${NC}"
    echo -e "${GREEN}交易对  : ${pairs}${NC}"
    echo -e "${GREEN}策略    : ${strategy}${NC}"
    [ "$strategy_choice" = "2" ] && echo -e "${GREEN}策略文件: ${strategy_file}${NC}"
    echo "--------------------------------"
    
    # 生成随机用户名和密码
    local username=$(generate_random_username)
    local password=$(generate_random_password)
    
    # 生成配置文件
    cat > "$config_path" <<EOF
{
    "max_open_trades": $max_trades,
    "stake_currency": "$stake_currency",
    "stake_amount": "$stake_amount",
    "tradable_balance_ratio": 0.99,
    "dry_run": $dry_run,
    "dry_run_wallet": 1000,
    "fiat_display_currency": "USD",
    "timeframe": "5m",
    "stoploss": -0.1,
    "minimal_roi": {
        "60": 0.01,
        "30": 0.02,
        "0": 0.04
    },
    "entry_pricing": {
        "price_side": "same",
        "use_order_book": true,
        "order_book_top": 1,
        "check_depth_of_market": {
            "enabled": false,
            "bids_to_ask_delta": 1
        }
    },
    "exit_pricing": {
        "price_side": "same",
        "use_order_book": true,
        "order_book_top": 1
    },
    "strategy": "$strategy",
    "exchange": {
        "name": "$exchange",
        "key": "$api_key",
        "secret": "$api_secret",
        "ccxt_config": {},
        "ccxt_async_config": {},
        "pair_whitelist": [
            "BTC/USDT",
            "ETH/USDT",
            "BNB/USDT",
            "ADA/USDT",
            "XRP/USDT"
        ],
        "pair_blacklist": []
    },
    "pairlists": [
        {
            "method": "StaticPairList",
            "pairs": [
                "BTC/USDT",
                "ETH/USDT",
                "BNB/USDT",
                "ADA/USDT",
                "XRP/USDT"
            ]
        }
    ],
    "order_types": {
        "entry": "limit",
        "exit": "limit",
        "emergency_exit": "market",
        "force_entry": "market",
        "force_exit": "market",
        "stoploss": "market",
        "stoploss_on_exchange": false
    },
    "order_time_in_force": {
        "entry": "GTC",
        "exit": "GTC"
    },
    "bot_name": "freqtrade",
    "unfilledtimeout": {
        "entry": 10,
        "exit": 10,
        "exit_timeout_count": 0,
        "unit": "minutes"
    },
    "api_server": {
        "enabled": true,
        "listen_ip_address": "0.0.0.0",
        "listen_port": 8080,
        "verbosity": "error",
        "enable_openapi": true,
        "jwt_secret_key": "$(openssl rand -hex 32)",
        "CORS_origins": [],
        "username": "$username",
        "password": "$password"
    },
    "internals": {
        "process_throttle_secs": 5
    }
}
EOF
    
    echo -e "\n配置文件已生成: ${config_path}"
    echo "您可以手动编辑此文件来调整更多设置:"
    echo "- stake_amount: 每次交易金额（数字或'unlimited'）"
    echo "- max_open_trades: 最大同时开仓数"
    echo "- minimal_roi: 最小利润率设置"
    echo "- stoploss: 止损设置"
    echo "- dry_run: 模拟交易模式"
    echo "- exchange.key: API密钥"
    echo "- exchange.secret: API密钥"
    echo "- api_server: API服务器设置（用于网页界面）"
    echo "  * username: 登录用户名"
    echo "  * password: 登录密码"
    echo "  * jwt_secret_key: JWT密钥"
    echo
    echo "提示: 使用您喜欢的编辑器修改配置文件，例如:"
    echo "nano ${config_path}"
    echo "vim ${config_path}"
}

function configure_firewall() {
    echo_block "配置防火墙"
    local port=8080

    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}提示: 配置防火墙需要root权限${NC}"
        return
    fi

    # 检查并配置 UFW (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        echo "检测到 UFW 防火墙"
        if ! ufw status | grep -q "$port/tcp"; then
            echo "正在开放端口 $port..."
            ufw allow $port/tcp
            ufw reload
            echo -e "${GREEN}UFW防火墙端口已开放${NC}"
        else
            echo "端口 $port 已经开放"
        fi
        return
    fi

    # 检查并配置 FirewallD (CentOS/RHEL)
    if command -v firewall-cmd >/dev/null 2>&1; then
        echo "检测到 FirewallD 防火墙"
        if ! firewall-cmd --list-ports | grep -q "$port/tcp"; then
            echo "正在开放端口 $port..."
            firewall-cmd --zone=public --add-port=$port/tcp --permanent
            firewall-cmd --reload
            echo -e "${GREEN}FirewallD防火墙端口已开放${NC}"
        else
            echo "端口 $port 已经开放"
        fi
        return
    fi

    # 检查并配置 iptables
    if command -v iptables >/dev/null 2>&1; then
        echo "检测到 iptables"
        if ! iptables -L | grep -q "port $port"; then
            echo "正在开放端口 $port..."
            iptables -I INPUT -p tcp --dport $port -j ACCEPT
            # 保存 iptables 规则
            if command -v iptables-save >/dev/null 2>&1; then
                iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
                iptables-save > /etc/sysconfig/iptables 2>/dev/null
            fi
            echo -e "${GREEN}iptables防火墙端口已开放${NC}"
        else
            echo "端口 $port 已经开放"
        fi
        return
    fi

    echo -e "${YELLOW}未检测到支持的防火墙系统${NC}"
    echo "请手动确保端口 $port 已开放"
}

function generate_random_username() {
    # 生成8位随机用户名，只包含小写字母和数字
    echo "user_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)"
}

function generate_random_password() {
    # 生成16位随机密码，包含大小写字母、数字和特殊字符
    local length=16
    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
    tr -dc "$chars" < /dev/urandom | head -c $length
}

function start_webui() {
    echo_block "启动网页界面"
    
    # 确保在正确目录并检查环境
    if ! check_environment; then
        echo -e "${RED}错误: 环境检查失败${NC}"
        read -p "是否要安装 Freqtrade？[Y/n] " choice
        if [[ ! $choice =~ ^[Nn]$ ]]; then
            install_freqtrade
            if ! check_environment; then
                echo -e "${RED}安装失败，请检查错误信息${NC}"
                return 1
            fi
        else
            return 1
        fi
    fi

    # 配置防火墙
    echo "正在配置防火墙..."
    configure_firewall
    
    # 检查配置文件
    local config_file="/root/freqtrade/user_data/config.json"
    if [ ! -f "$config_file" ]; then
        echo "配置文件不存在，正在创建..."
        generate_config
    fi

    # 检查配置文件中的交易模式
    if ! grep -q '"dry_run": true' "$config_file"; then
        echo -e "\n${YELLOW}警告: 当前为实盘交易模式${NC}"
        if ! grep -q '"key": "[^"]\+"' "$config_file"; then
            echo -e "${RED}错误: 未配置交易所 API 密钥${NC}"
            read -p "是否现在配置 API 密钥？[Y/n] " choice
            if [[ ! $choice =~ ^[Nn]$ ]]; then
                generate_config
            else
                echo -e "${YELLOW}将以模拟交易模式启动${NC}"
                # 临时修改配置为模拟交易
                sed -i 's/"dry_run": false/"dry_run": true/' "$config_file"
            fi
        fi
    fi

    # 生成登录信息
    local username=$(generate_random_username)
    local password=$(generate_random_password)
    
    # 更新配置文件中的用户名和密码
    if [ -f "$config_file" ]; then
        sed -i "s/\"username\": \"[^\"]*\"/\"username\": \"$username\"/" "$config_file"
        sed -i "s/\"password\": \"[^\"]*\"/\"password\": \"$password\"/" "$config_file"
    fi
    
    echo -e "\n=========================================="
    echo "FreqUI 登录信息"
    echo "=========================================="
    echo "登录地址: http://$(curl -s ifconfig.me):8080"
    echo "用户名: ${username}"
    echo "密码: ${password}"
    echo "=========================================="
    
    # 保存登录信息
    mkdir -p user_data
    cat > user_data/login_info.txt <<EOF
==========================================
FreqUI 登录信息
登录地址: http://$(curl -s ifconfig.me):8080
用户名: ${username}
密码: ${password}
==========================================
EOF
    
    echo -e "\n登录信息已保存到: user_data/login_info.txt"
    read -p "请确认您已保存登录信息 [按回车继续]..."
    
    # 启动 UI
    echo -e "${GREEN}正在启动 Web UI...${NC}"
    echo -e "请在浏览器中访问: ${GREEN}http://$(curl -s ifconfig.me):8080${NC}"
    
    # 激活虚拟环境并启动
    cd /root/freqtrade
    source .venv/bin/activate
    
    # 使用完整路径启动
    .venv/bin/freqtrade trade \
        --config user_data/config.json \
        --strategy SampleStrategy \
        --db-url sqlite:///user_data/tradesv3.sqlite
    
    # 退出虚拟环境
    deactivate
}

function show_menu() {
    clear
    echo_block "Freqtrade 交易机器人"
    echo -e "${YELLOW}系统信息:${NC}"
    echo "Python版本: $(${PYTHON} --version 2>&1)"
    echo "系统类型: $(uname -s)"
    echo
    echo -e "${GREEN}请选择操作:${NC}"
    echo
    echo "1) 安装/更新"          # 默认完整安装所有依赖
    echo "2) 启动网页界面"       # 主要操作入口
    echo "3) 高级功能菜单"       # 备用的命令行操作
    echo
    echo "0) 退出"
    echo
    read -p "请输入选项 [0-3]: " choice
    
    case $choice in
        1)
            show_install_menu
            ;;
        2)
            start_webui
            read -p "按回车键返回主菜单..."
            show_menu
            ;;
        3)
            show_advanced_menu
            ;;
        0)
            echo_block "感谢使用！"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请重试${NC}"
            sleep 2
            show_menu
            ;;
    esac
}

function show_advanced_menu() {
    clear
    echo_block "高级功能菜单"
    echo
    echo "1) 手动修改配置"
    echo "2) 命令行运行机器人"
    echo "3) 命令行回测"
    echo "4) 命令行下载数据"
    echo "5) 查看版本信息"
    echo "6) 查看帮助文档"
    echo
    echo "0) 返回主菜单"
    echo
    read -p "请输入选项 [0-6]: " choice

    case $choice in
        1)
            # 检查并切换到 freqtrade 目录
            if [ -d "freqtrade" ]; then
                cd freqtrade
            elif [ "$(basename $PWD)" != "freqtrade" ]; then
                echo -e "${RED}错误: 未找到 freqtrade 目录${NC}"
                read -p "按回车键返回..."
                show_advanced_menu
                return
            fi

            # 激活虚拟环境（只在这里激活一次）
            if [ -f ".venv/bin/activate" ]; then
                echo "正在激活虚拟环境..."
                source .venv/bin/activate
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误: 虚拟环境激活失败${NC}"
                    read -p "按回车键返回..."
                    show_advanced_menu
                    return
                fi
                echo -e "${GREEN}虚拟环境已激活${NC}"
            else
                echo -e "${RED}错误: 虚拟环境未找到${NC}"
                echo "尝试重新安装..."
                read -p "是否重新安装？[Y/n]: " reinstall
                if [[ ! $reinstall =~ ^[Nn]$ ]]; then
                    install
                fi
                read -p "按回车键返回..."
                show_advanced_menu
                return
            fi

            # 提供编辑选项
            echo -e "\n${GREEN}选择编辑方式:${NC}"
            echo "1) 使用默认编辑器 (nano)"
            echo "2) 使用 vim"
            echo "3) 重新生成配置"
            echo "0) 返回"
            read -p "请选择 [0-3]: " edit_choice

            case $edit_choice in
                1)
                    nano user_data/config.json
                    ;;
                2)
                    vim user_data/config.json
                    ;;
                3)
                    generate_config  # 现在调用时已经在正确的目录且虚拟环境已激活
                    ;;
                0)
                    show_advanced_menu
                    return
                    ;;
                *)
                    echo -e "${RED}无效的选项${NC}"
                    ;;
            esac
            read -p "按回车键返回..."
            show_advanced_menu
            ;;
        2)
            # 命令行运行机器人
            if [ -d "freqtrade" ]; then
                cd freqtrade
                source .venv/bin/activate
                echo -e "${GREEN}可用命令:${NC}"
                echo "freqtrade trade --config user_data/config.json"
                read -p "按回车键返回..."
            else
                echo -e "${RED}错误: 未找到 freqtrade 目录${NC}"
                read -p "按回车键返回..."
            fi
            show_advanced_menu
            ;;
        3|4|5|6)
            echo -e "${YELLOW}功能开发中...${NC}"
            read -p "按回车键返回..."
            show_advanced_menu
            ;;
        0)
            show_menu
            ;;
        *)
            echo -e "${RED}无效的选项，请重试${NC}"
            sleep 2
            show_advanced_menu
            ;;
    esac
}

function show_install_menu() {
    clear
    echo_block "安装选项"
    echo
    echo "1) 基础安装（仅交易功能）"
    echo "2) 完整安装（含所有功能）"
    echo "3) 更新现有安装"
    echo "4) 重置到稳定版本"
    echo
    echo "0) 返回主菜单"
    echo
    read -p "请输入选项 [0-4]: " choice

    case $choice in
        1|2)
            if [ "$choice" -eq 1 ]; then
                REQUIREMENTS=requirements.txt
            else
                REQUIREMENTS=requirements-dev.txt
            fi
            install
            # 不需要额外的 show_menu，因为 install 函数会处理
            ;;
        3)
            update
            read -p "更新完成！按回车键返回主菜单..."
            show_menu
            ;;
        4)
            reset
            read -p "重置完成！按回车键返回主菜单..."
            show_menu
            ;;
        0)
            show_menu
            ;;
        *)
            echo -e "${RED}无效的选项，请重试${NC}"
            sleep 2
            show_install_menu
            ;;
    esac
}

# 验证是否安装了 Python 3.10+
check_installed_python

# 根据命令行参数执行操作或显示菜单
if [ $# -eq 0 ]; then
    show_menu
else
    case $* in
    --install|-i)
        install
        ;;
    --config|-c)
        config
        ;;
    --update|-u)
        update
        ;;
    --reset|-r)
        reset
        ;;
    --plot|-p)
        plot
        ;;
    *)
        help
        ;;
    esac
fi

exit 0
