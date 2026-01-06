# 自动加载.bashrc文件
if test -f ~/.bashrc ; then
	source ~/.bashrc
fi
alias gs='git status'
alias gb='git branch'
alias gd='git diff'
alias gp='git pull'
#alias gl='git log --pretty'
alias gl='git lg'
#alias make='bear make'
alias nv='nvim'
alias ..='cd ..'
alias fd='fd -I'
alias ra='ranger'

export PATH=~/bin/pc_hdc_v120a:~/bin:$PATH
# 定义动态的 gpush 函数
function gpush() {
  # 检查是否提供了分支名
  if [ -z "$1" ]; then
    echo "Usage: gpush <branch>"
    return 1
  fi

  # 使用提供的分支名生成并执行 git push 命令
  git push origin HEAD:refs/for/"$1"
}

export PATH="$PATH:$(find ~/server-cloud-computer -type d -not -path '*/.git/*' | tr '\n' ':')"
export VISUAL=nvim
export EDITOR=nvim

# openharmony-build: ccached
export CCACHE_BASE=/home/chenzigui
export CCACHE_LOCAL_DIR=ccache
export USE_CCACHE=1
export CCACHE_MAXSIZE=500G

# 自动挂载 /hdd1/chenzigui/src 到 /home/chenzigui/src
SRC_MOUNT="/home/chenzigui/src"
SRC_DEVICE="/hdd1/chenzigui/src"

if ! mountpoint -q "$SRC_MOUNT"; then
    echo "[mount] $SRC_MOUNT not mounted, mounting..."
    mkdir -p "$SRC_MOUNT"
    sudo mount --bind "$SRC_DEVICE" "$SRC_MOUNT"
else
    echo "[mount] $SRC_MOUNT already mounted."
fi
