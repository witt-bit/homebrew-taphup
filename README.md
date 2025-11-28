# Witt Taps (homebrew-taphup)

这是个人的 Homebrew tap：witt-bit/homebrew-taphup。仓库包含若干自建 formula/cask（图形应用、字体、工具等），以及用于自动更新 cask 的 Upgrader 脚本与示例 workflow。

> 注意：本 README 以仓库 owner/repo 为 witt-bit/homebrew-taphup，对应的 tap 名称为 `witt/taphup`（你也可以直接使用带完整路径的安装方式）。

## 如何安装（用户）

1. 先添加 tap（只需一次）：
```bash
brew tap witt/taphup https://github.com/witt-bit/homebrew-taphup
```

2. 直接安装某个包：
```bash
# 通过 tap 全路径安装
brew install witt/taphup/<formula>

# 或者先 tap（见上）然后直接安装包名
brew install <formula>
```

## 仓库内已有的软件（示例）
以下是当前仓库中已包含或示例的包（请根据实际文件名替换 `<formula>`）：

- 小旺AI截图
  ```bash
  brew install witt/taphup/xw-screenshot
  ```
- 字体：Monaco Nerd Font Ligatures
  ```bash
  brew install witt/taphup/font-monaco-nerd-font-ligatures
  ```
- ToDesk
  ```bash
  brew install witt/taphup/todesk
  ```
- Tiny RDM (Redis Desktop Manager，作为 cask)
  ```bash
  brew install --cask tiny-rdm
  ```

（仓库可能随时增加/移除包，请以 `Casks/` 和 `Formula/` 目录为准）



## 常用命令速查
```bash
# tap 仓库
brew tap witt/taphup https://github.com/witt-bit/homebrew-taphup

# 通过 tap 安装某个包（示例）
brew install witt/taphup/xw-screenshot

# 安装 tiny-rdm (cask)
brew install --cask tiny-rdm

# 从本地 cask 安装（用于测试）
brew install --cask --appdir=~/Applications ./Casks/tiny-rdm.rb

# 运行 Upgrader（只更新文件）
./Upgrader/tiny-rdm.sh

# 运行 Upgrader 并提交、推送（创建远程分支）
./Upgrader/tiny-rdm.sh 1.2.5 --commit --push
```