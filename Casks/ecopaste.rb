cask "ecopaste" do
    version "0.6.0"

    if Hardware::CPU.intel?
      url "https://ghproxy.monkeyray.net/https://github.com/witt-bit/EcoPastePro/releases/download/v#{version}/EcoPaste_x64.app.tar.gz"
      sha256 "409b05b0e571fa2bcabc3694c92a1c037979e936b19b701133bc3b5cff23b8ed"
    else
      url "https://ghproxy.monkeyray.net/https://github.com/witt-bit/EcoPastePro/releases/download/v#{version}/EcoPaste_aarch64.app.tar.gz"
      sha256 "d732a88c05315b4fc658875cdb8597ac091955bab83cb1d758551e985a0a9e2f"
    end

    name "EcoPaste"
    desc "Open source clipboard management tools for Windows, Macos and Linux(x11)"
    homepage "https://github.com/witt-bit/EcoPastePro"

    livecheck do
      url :url
      strategy :github_latest
    end

    app "EcoPaste.app"

    # 尝试在安装后以当前用户移除 quarantine（不会使用 sudo）。
    postflight do
      begin
        system_command '/usr/bin/xattr',
                      args: ['-d', 'com.apple.quarantine', "#{appdir}/EcoPaste.app"],
                      print_stdout: false, print_stderr: false
      rescue => e
        # 如果失败，不要执行 sudo（不推荐自动提权）
        puts "NOTICE: Failed to remove com.apple.quarantine automatically: #{e}"
      end
    end

    caveats <<~EOS
      如果在 macOS 中将应用拖入 /Applications 后无法启动，请在终端运行：
        sudo xattr -d com.apple.quarantine /Applications/EcoPaste.app

      说明：安装脚本会尝试以当前用户移除隔离属性（不使用 sudo）。如果你的安装目标是系统级 /Applications 并且操作失败，请按上面命令手动运行（需要管理员权限）。
    EOS
  end