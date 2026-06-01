cask "imfile" do
  version "2.0.5"
  sha256 arm:   "df792e55bfeae23679ba0bb1b53b9857067b91eaf0329dfe7e4c58372f2af88c",
         intel: "e7abf89f4e782963ee8423a36e819b00e10ff319fd7980246ca91976f5c21838"

  on_intel do
    url "https://github.com/imfile-io/imfile-desktop/releases/download/v#{version}/imFile-#{version}.dmg"
  end
  on_arm do
    url "https://github.com/imfile-io/imfile-deop/releases/download/v#{version}/imFile-#{version}-arm64.dmg"
  end

  name "imFile"
  desc "A feature-rich download manager"
  homepage "https://github.com/imfile-io/imfile-desktop"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "imFile.app"

  postflight do
    begin
      system_command '/usr/bin/xattr',
                     args: ['-d', 'com.apple.quarantine', "#{appdir}/imFile.app"],
                     print_stdout: false, print_stderr: false
    rescue => e
      puts "NOTICE: Failed to remove com.apple.quarantine automatically: #{e}"
    end
  end

  caveats <<~EOS
    如果在 macOS 中将应用拖入 /Applications 后无法启动，请在终端运行：
      sudo xattr -d com.apple.quarantine /Applications/imFile.app

    说明：安装脚本会尝试以当前用户移除隔离属性（不使用 sudo）。如果你的安装目标是系统级 /Applications 并且操作失败，请按上面命令手动运行（需要管理员权限）。
  EOS
end
