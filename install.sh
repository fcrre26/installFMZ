#!/usr/bin/env bash
#encoding=utf8

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

    read -p "是否安装开发依赖（将进行完整安装，包含所有依赖）[y/N]？"
    dev=$REPLY
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        REQUIREMENTS=requirements-dev.txt
    else
        read -p "是否安装绘图依赖（plotly）[y/N]？"
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            REQUIREMENTS_PLOT="-r requirements-plot.txt"
        fi
        if [ "${SYS_ARCH}" == "armv7l" ] || [ "${SYS_ARCH}" == "armv6l" ]; then
            echo "检测到树莓派，正在安装 cython，跳过 hyperopt 安装。"
            ${PYTHON} -m pip install --upgrade cython
        else
            read -p "是否安装 hyperopt 依赖 [y/N]？"
            if [[ $REPLY =~ ^[Yy]$ ]]
            then
                REQUIREMENTS_HYPEROPT="-r requirements-hyperopt.txt"
            fi
        fi

        read -p "是否安装 freqai 依赖 [y/N]？"
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            REQUIREMENTS_FREQAI="-r requirements-freqai.txt --use-pep517"
            read -p "是否同时安装 freqai-rl 或 PyTorch 依赖（需要额外约 700MB 空间）[y/N]？"
            if [[ $REPLY =~ ^[Yy]$ ]]
            then
                REQUIREMENTS_FREQAI="-r requirements-freqai-rl.txt"
            fi
        fi
    fi
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
    if [[ $dev =~ ^[Yy]$ ]]; then
        ${PYTHON} -m pre_commit install
        if [ $? -ne 0 ]; then
            echo "安装 pre-commit 失败"
            exit 1
        fi
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
}

# 验证是否安装了 Python 3.10+
check_installed_python

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
exit 0
