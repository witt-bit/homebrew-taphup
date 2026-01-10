# Homebrew Cask for ClashMac (source: 666OS/ClashMac)
# - 自动处理 Gatekeeper quarantine（preflight/postflight）
# - 在 staged 目录中递归查找 .app 并移动到根（解决 zip/dmg 内层目录导致找不到 .app 的问题）
# - 修正可执行位（Contents/MacOS/* -> 0755）
# 注意：
# - 已移除 deprecated 的 depends_on macos 行（brew 会提示该用法已弃用）
# - 请根据实际 DMG/ZIP 内的 app 名称调整 APP_NAME（默认为 "Clash.app"）
cask "clash-mac" do
  version "26.3"

  on_arm do
    sha256 "2cd26ebd3acf2818b35e214439a07488add6a94306319cb6c01359c496cbf3c4"
    url "https://github.com/666OS/ClashMac/releases/download/#{version}/ClashMac-#{version}-macos-arm64.zip"
  end

  on_intel do
    sha256 "b5aa33db55ccf67ea666267c5ea9c1080379b395e1d4a57dcccf96adcf9cb07b"
    url "https://github.com/666OS/ClashMac/releases/download/#{version}/ClashMac-#{version}-macos-x86_64.zip"
  end
  name "Clash for macOS"
  desc "GUI client for Clash on macOS (packaged by 666OS/ClashMac)"
  homepage "https://github.com/666OS/ClashMac"

  # 若 DMG/ZIP 中的 .app 名称不是 Clash.app，请修改此处
  app "Clash.app"

  # 在 staged 阶段尝试：1) 如果 .app 在子目录，则移动到 staged 根；2) 清除 quarantine；3) 修正可执行位
  preflight do
    APP_NAME = "Clash.app"
    staged_app = staged_path/APP_NAME

    # 如果没有在 staged 根找到 app，递归查找第一个 .app 并移动到 staged 根
    unless staged_app.exist?
      found = Dir[File.join(staged_path.to_s, "**", "*.app")].first
      if found
        # move the found app to staged root so cask can install it
        system_command '/bin/mv',
                       args: [found, staged_app.to_s],
                       sudo: false
      end
    end

    if staged_app.exist?
      # 移除 Gatekeeper quarantine 标记（递归）
      system_command '/usr/bin/xattr',
                     args: ['-r', '-d', 'com.apple.quarantine', staged_app.to_s],
                     sudo: false

      # 修正 Contents/MacOS 下的可执行文件权限为 0755，避免安装后无法执行的问题
      macos_dir = staged_app/"Contents"/"MacOS"
      if macos_dir.directory?
        Dir[File.join(macos_dir.to_s, "*")].each do |f|
          FileUtils.chmod 0755, f if File.file?(f) rescue nil
        end
      end
    end
  end

  # 安装后再次确保目标 /Applications 路径下清除 quarantine 并修正权限
  postflight do
    installed_app = "#{appdir}/Clash.app"
    if File.exist?(installed_app)
      system_command '/usr/bin/xattr',
                     args: ['-r', '-d', 'com.apple.quarantine', installed_app],
                     sudo: false

      macos_dir = File.join(installed_app, "Contents", "MacOS")
      if File.directory?(macos_dir)
        Dir[File.join(macos_dir, "*")].each do |f|
          FileUtils.chmod 0755, f rescue nil
        end
      end
    end
  end

  uninstall delete: "#{appdir}/Clash.app"

  zap trash: [
    "~/Library/Application Support/Clash",
    "~/Library/Preferences/com.clash.mac.plist",
  ]

  caveats <<~EOS
    如果 macOS Gatekeeper 在安装后仍阻止应用打开，请尝试：
    1. 打开“系统设置”→“隐私与安全”，在“安全性与隐私”中允许该应用；
    2. 在 Finder 中对应用右键，选择“打开”，在弹窗中选择“打开”以绕过限制；
    3. 需要时可在终端运行：sudo xattr -r -d com.apple.quarantine "/Applications/Clash.app"
    4. 若遇到“权限被拒绝”或无法执行的问题，请检查应用内可执行文件权限，并确保其为可执行 (chmod 755)。
    请根据实际应用名与安装路径调整上述命令。
  EOS
end
