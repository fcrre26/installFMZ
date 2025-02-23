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

function generate_config() {
    echo_block "生成配置文件"
    read -p "请输入配置文件路径 [user_data/config.json]: " config_path
    config_path=${config_path:-user_data/config.json}
    
    echo "请回答以下问题来生成配置文件："
    
    # 交易所选择
    echo -e "\n${GREEN}支持的交易所:${NC}"
    echo "1) Binance (推荐)"
    echo "2) Huobi"
    echo "3) OKX"
    echo "4) 其他"
    read -p "请选择交易所 [1]: " exchange_choice
    case $exchange_choice in
        2) exchange="huobi";;
        3) exchange="okx";;
        4) 
            read -p "请输入交易所名称: " exchange
            ;;
        *) exchange="binance";;
    esac
    
    # 交易对
    read -p "请输入交易对(例如: BTC/USDT ETH/USDT) [BTC/USDT]: " pairs
    pairs=${pairs:-"BTC/USDT"}
    
    # 策略选择
    echo -e "\n${GREEN}常用策略:${NC}"
    echo "1) SampleStrategy (样例策略)"
    echo "2) 自定义策略"
    read -p "请选择策略 [1]: " strategy_choice
    if [ "$strategy_choice" = "2" ]; then
        read -p "请输入策略类名: " strategy
    else
        strategy="SampleStrategy"
    fi
    
    # 生成基础配置
    freqtrade new-config \
        --config "$config_path" \
        -e "$exchange" \
        --pairs "$pairs" \
        --strategy "$strategy"
    
    echo -e "\n${GREEN}配置文件已生成: $config_path${NC}"
    echo "您可以手动编辑此文件来调整更多设置:"
    echo "- stake_amount: 每次交易金额"
    echo "- max_open_trades: 最大同时开仓数"
    echo "- minimal_roi: 最小利润率设置"
    echo "- stoploss: 止损设置"
    echo "- dry_run: 模拟交易模式"
    echo "- exchange.key: API密钥"
    echo "- exchange.secret: API密钥"
    echo "- telegram: 电报机器人设置"
}

function show_run_menu() {
    clear
    echo_block "Freqtrade 运行命令菜单"
    
    # 首先检查 freqtrade 目录
    check_freqtrade_dir || {
        read -p "按回车键返回主菜单..."
        show_menu
        return
    }
    
    # 检查是否在虚拟环境中
    if [ -z "${VIRTUAL_ENV}" ]; then
        echo -e "${YELLOW}提示: 正在激活虚拟环境...${NC}"
        if [ -f ".venv/bin/activate" ]; then
            source .venv/bin/activate
            echo "虚拟环境已激活"
        else
            echo -e "${RED}错误: 未找到虚拟环境${NC}"
            echo "请先运行安装选项 (1) 从头安装 Freqtrade"
            read -p "按回车键返回主菜单..."
            show_menu
            return
        fi
    fi
    
    echo -e "${GREEN}请选择要执行的命令:${NC}"
    echo
    echo "1) 查看版本信息"
    echo "2) 查看帮助文档"
    echo "3) 生成配置文件"
    echo "4) 运行交易机器人"
    echo "5) 运行回测"
    echo "6) 参数优化"
    echo "7) 下载市场数据"
    echo
    echo "0) 返回主菜单"
    echo
    read -p "请输入选项 [0-7]: " choice

    case $choice in
        1)
            echo_block "Freqtrade 版本信息"
            freqtrade --version
            read -p "按回车键继续..."
            show_run_menu
            ;;
        2)
            echo_block "Freqtrade 帮助文档"
            freqtrade --help
            read -p "按回车键继续..."
            show_run_menu
            ;;
        3)
            generate_config
            read -p "按回车键继续..."
            show_run_menu
            ;;
        4)
            echo_block "运行交易机器人"
            read -p "请输入配置文件路径 [user_data/config.json]: " config_path
            config_path=${config_path:-user_data/config.json}
            freqtrade trade -c "$config_path"
            read -p "按回车键继续..."
            show_run_menu
            ;;
        5)
            echo_block "运行回测"
            read -p "请输入配置文件路径 [user_data/config.json]: " config_path
            config_path=${config_path:-user_data/config.json}
            freqtrade backtesting -c "$config_path"
            read -p "按回车键继续..."
            show_run_menu
            ;;
        6)
            echo_block "参数优化"
            read -p "请输入配置文件路径 [user_data/config.json]: " config_path
            config_path=${config_path:-user_data/config.json}
            freqtrade hyperopt -c "$config_path"
            read -p "按回车键继续..."
            show_run_menu
            ;;
        7)
            echo_block "下载市场数据"
            read -p "请输入配置文件路径 [user_data/config.json]: " config_path
            config_path=${config_path:-user_data/config.json}
            freqtrade download-data -c "$config_path"
            read -p "按回车键继续..."
            show_run_menu
            ;;
        0)
            show_menu
            ;;
        *)
            echo -e "${RED}无效的选项，请重试${NC}"
            sleep 2
            show_run_menu
            ;;
    esac
}

function show_menu() {
    clear
    echo_block "Freqtrade 安装管理工具"
    echo -e "${YELLOW}系统信息:${NC}"
    echo "Python版本: $(${PYTHON} --version 2>&1)"
    echo "系统类型: $(uname -s)"
    echo "架构: $(uname -m)"
    echo
    echo -e "${GREEN}请选择操作:${NC}"
    echo
    echo "1) 从头安装 Freqtrade"
    echo "2) 更新 Freqtrade"
    echo "3) 重置开发/稳定分支"
    echo "4) 生成配置文件"
    echo "5) 安装绘图依赖"
    echo "6) 运行命令菜单"
    echo
    echo "0) 退出"
    echo
    read -p "请输入选项 [0-6]: " choice
    
    case $choice in
        1)
            echo_block "开始安装 Freqtrade"
            install
            read -p "按回车键返回主菜单..."
            show_menu
            ;;
        2)
            echo_block "开始更新 Freqtrade"
            update
            read -p "按回车键返回主菜单..."
            show_menu
            ;;
        3)
            echo_block "开始重置分支"
            reset
            read -p "按回车键返回主菜单..."
            show_menu
            ;;
        4)
            echo_block "生成配置文件"
            config
            read -p "按回车键返回主菜单..."
            show_menu
            ;;
        5)
            echo_block "安装绘图依赖"
            plot
            read -p "按回车键返回主菜单..."
            show_menu
            ;;
        6)
            show_run_menu
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
