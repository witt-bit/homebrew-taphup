cask "todesk" do
  version "4.8.8.9"
  sha256 :no_check

  url "https://www.todesk.com/download.html" # 占位用

  name "ToDesk"
  desc "个人版远程控制软件"
  homepage "https://www.todesk.com/"

  installer script: {
    executable: "/bin/bash",
    args: [
      "-c",
      <<~EOS
        set -e
        TMP_PKG="/tmp/ToDesk.pkg"
        /usr/bin/env wget \
          --progress=bar:force \
          -U 'Mozilla/5.0' \
          -O "$TMP_PKG" \
          https://dl.todesk.com/macos/ToDesk_#{version}.pkg

        sudo installer -pkg "$TMP_PKG" -target /
      EOS
    ]
  }

  uninstall pkgutil: "com.youqu.todesk.mac",
            delete:  "/Applications/ToDesk.app"
end