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
alias nv='vim'
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
# 按照夏总的意思取消，home对应/home/chenzigui，ccache默认就在/home了
#export CCACHE_DIR=/cchace/chenzigui
#export CCACHE_BASE=/cchace/chenzigui
