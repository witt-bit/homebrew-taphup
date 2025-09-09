cask "todesk" do
  version "4.7.8.3"
  sha256 "f1f5a3cb75390418e8e98064022a331aae2810fdff56891093a7aa5766c8ba36"

  url "https://dl.todesk.com/macos/ToDesk_#{version}.pkg",
      user_agent: :fake
  name "ToDesk"
  desc "个人版远程控制软件"
  homepage "https://www.todesk.com/"

  livecheck do
    url "https://www.todesk.com/download.html"
    regex(/mac_version\s*[:=]\s*["']?(\d+(?:\.\d+)+)/i)
  end

  pkg "ToDesk_#{version}.pkg"

  uninstall pkgutil: "com.youqu.todesk.mac",
            delete:  "/Applications/ToDesk.app"
end
