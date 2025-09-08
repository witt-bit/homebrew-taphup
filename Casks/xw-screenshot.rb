cask "xw-screenshot" do
  version "1.2.7"

  # 根据架构选择 URL 和 sha256
  if Hardware::CPU.intel?
    url "https://ai-search-static.dangbei.net/ai-screenshot-updates/xw-screenshot_x64.dmg"
    sha256 "313adf294fd7cf6c107b0a6ee865fc2cc30ebc1d522e38746500a3b83e593335"
  elsif Hardware::CPU.arm?
    url "https://ai-search-static.dangbei.net/ai-screenshot-updates/xw-screenshot_aarch64.dmg"
    sha256 "7a849967c7bcc9cd57bb0429955c9a0f83c43db07e12237b5783ab7e016a5067"
  end

  name "XW Screenshot"
  desc "首款接入DeepSeek的AI截图神器！轻巧、好用、免费、无广告！"
  homepage "https://www.xiaowang.com/"

  app "小旺AI截图.app"

  binary "#{appdir}/小旺AI截图.app/Contents/MacOS/wang-screenshot", target: "xw-screenshot"

  uninstall quit: "com.wangscreenshot.app"

  # 自动检查更新
  livecheck do
    url "https://www.xiaowang.com/update.html"
    regex(/V?(\d+(?:\.\d+)+)/i)
  end
end