cask "smart-fan" do
  version "1.0.0"
  # 取自发行包的 SHA256SUMS。CI 构建的 tar 与本机不同，所以每次发版后都要用
  # release 里 SHA256SUMS 的值替换这一行；在第一个发行版创建之前，它只是占位。
  sha256 "023c59bbf9a14819e23e5857f26e0e11b9c519a130bbd1e7e5732c0149f6972b"

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

  app "SmartFan.app"

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
