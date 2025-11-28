cask "tiny-rdm" do
  version "1.2.5"
  sha256 arm:   "0918611c8a96dbbda5a8e59c4c810659bca5033d82f780df865d4d1dfed25b8a",
         intel: "4415ff1bb28603c2bd18b57700ef6f515098bfd0d6b9b61f5aaccadc378a3c33"

  on_intel do
    url "https://github.com/tiny-craft/tiny-rdm/releases/download/v#{version}/TinyRDM_#{version}_mac_intel.dmg"
  end
  on_arm do
    url "https://github.com/tiny-craft/tiny-rdm/releases/download/v#{version}/TinyRDM_#{version}_mac_arm64.dmg"
  end

  name "Tiny RDM"
  desc "A lightweight Redis desktop manager"
  homepage "https://redis.tinycraft.cc/zh/"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Tiny RDM.app"

  # 尝试在安装后以当前用户移除 quarantine（不会使用 sudo）。
  postflight do
    begin
      system_command '/usr/bin/xattr',
                     args: ['-d', 'com.apple.quarantine', "#{appdir}/Tiny RDM.app"],
                     print_stdout: false, print_stderr: false
    rescue => e
      # 如果失败，不要执行 sudo（不推荐自动提权）
      puts "NOTICE: Failed to remove com.apple.quarantine automatically: #{e}"
    end
  end

  zap trash: [
    "~/Library/Application Support/tinyrdm",
    "~/Library/Caches/cc.tinycraft.tiny-rdm",
    "~/Library/Preferences/cc.tinycraft.tiny-rdm.plist",
    "~/Library/Saved Application State/cc.tinycraft.tiny-rdm.savedState",
  ]

  caveats <<~EOS
    如果在 macOS 中将应用拖入 /Applications 后无法启动，请在终端运行：
      sudo xattr -d com.apple.quarantine /Applications/Tiny\\ RDM.app

    说明：安装脚本会尝试以当前用户移除隔离属性（不使用 sudo）。如果你的安装目标是系统级 /Applications 并且操作失败，请按上面命令手动运行（需要管理员权限）。
  EOS
end