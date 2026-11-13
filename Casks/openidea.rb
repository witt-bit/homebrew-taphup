cask "openidea" do
  version "0.1.43"
  sha256 arm:   "4abcfc0d53acd9a9d70604e22f94ff60d2811897fc26fe21d2872bb52cac8dba",
         intel: "032140de9faee375292c56c5cf63aba9270fe964a8377c561df897b9c990ac07"

  # 上游按 aarch64 / x64 分别发布单架构 DMG，两包的 app 名与版本一致。
  on_intel do
    url "https://github.com/l0ng-ai/openidea/releases/download/v#{version}/OpenIDEA_#{version}_x64.dmg"
  end
  on_arm do
    url "https://github.com/l0ng-ai/openidea/releases/download/v#{version}/OpenIDEA_#{version}_aarch64.dmg"
  end

  name "OpenIDEA"
  desc "AI-ready IDE rebuilt in Rust with IntelliJ IDEA-style keymap"
  homepage "https://openidea.sh"

  livecheck do
    url :url
    strategy :github_latest
  end

  # 应用通过自带的 Tauri updater 更新，声明后 brew upgrade 不会与之冲突。
  auto_updates true

  # 应用自身 LSMinimumSystemVersion 为 11.0（Big Sur）。
  depends_on macos: :big_sur

  app "OpenIDEA.app"

  # 尝试在安装后以当前用户移除 quarantine（不会使用 sudo）。
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-d", "com.apple.quarantine", "{{appdir}}/OpenIDEA.app"],
        must_succeed: false, print_stdout: false, print_stderr: false
  end

  zap trash: [
    "~/Library/Application Support/ai.l0ng.openidea",
    "~/Library/Caches/ai.l0ng.openidea",
    "~/Library/Logs/ai.l0ng.openidea",
    "~/Library/Preferences/ai.l0ng.openidea.plist",
    "~/Library/Saved Application State/ai.l0ng.openidea.savedState",
    "~/Library/WebKit/ai.l0ng.openidea",
  ]

  caveats <<~EOS
    如果在 macOS 中将应用拖入 /Applications 后无法启动，请在终端运行：
      sudo xattr -d com.apple.quarantine /Applications/OpenIDEA.app

    说明：安装脚本会尝试以当前用户移除隔离属性（不使用 sudo）。如果你的安装目标是系统级 /Applications 并且操作失败，请按上面命令手动运行（需要管理员权限）。
  EOS
end