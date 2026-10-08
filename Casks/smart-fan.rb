cask "smart-fan" do
  version "1.0.0"
  # 由 SmartFan 仓库里的 `scripts/setup.sh cask` 写入：它打包、读 SHA256SUMS、更新这个文件。
  # 上传的必须是该命令生成的那两个文件——重新打包会得到不同的 sha（tar 记录时间戳），
  # 对不上就会报 checksum mismatch。
  sha256 "5fea18e79ce61b20eefaca89956ce2d94f2c86be26d7e41410a5dd72cc013c3b"

  # 解析后的地址（Homebrew 用这个下载，已实测通过校验）：
  #   https://github.com/witt-bit/smart-fan/releases/download/v1.0.0/SmartFan-1.0.0-macos-arm64.tar.gz
  # 用 #{version} 插值而不是写死，发版时 `scripts/setup.sh cask` 只要改 version 与 sha256 两行。
  url "https://github.com/witt-bit/smart-fan/releases/download/v#{version}/SmartFan-#{version}-macos-arm64.tar.gz"
  name "SmartFan"
  desc "Menu bar fan control for Apple Silicon Macs"
  homepage "https://github.com/witt-bit/smart-fan"

  livecheck do
    url :url
    strategy :github_latest
  end

  # 只支持 Apple Silicon：产物本身是 arm64，且风扇控制依赖 Apple Silicon 的 SMC 行为。
  depends_on arch: :arm64
  depends_on macos: :sonoma

  # 发行包外层套了一个以版本命名的目录，这样手动解压不会把文件散落一地；
  # 因此这里要指到解压后的那一层，而不是 staging 根目录。
  app "SmartFan-#{version}-macos-arm64/SmartFan.app"

  # 尝试在安装后以当前用户移除 quarantine（不会使用 sudo）。
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/SmartFan.app"],
        must_succeed: false, print_stdout: false, print_stderr: false
  end

  zap trash: [
    "~/Library/Application Support/SmartFan",
    "~/Library/Logs/SmartFan",
    "~/Library/Preferences/org.witt.smartfan.app.plist",
    "~/Library/Saved Application State/org.witt.smartfan.app.savedState",
  ]

  caveats <<~EOS
    SmartFan 首次运行时会请求一次管理员授权，用于安装后台服务
    （/Library/PrivilegedHelperTools/org.witt.smartfan.helper），之后不再需要密码。

    后台服务由 root 拥有，Homebrew 卸载本 cask 时不会清理它。需要一并移除时执行：
      sudo launchctl bootout system/org.witt.smartfan.daemon
      sudo rm -f /Library/PrivilegedHelperTools/org.witt.smartfan.helper \\
                 /Library/LaunchDaemons/org.witt.smartfan.daemon.plist

    当前构建未经 Apple 公证。若 macOS 提示无法验证开发者，请在“系统设置 → 隐私与安全性”
    里选择“仍要打开”。
  EOS
end
