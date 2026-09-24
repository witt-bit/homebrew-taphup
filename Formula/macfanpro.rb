class Macfanpro < Formula
  desc "Apple Silicon fan control with English and Chinese menu bar app"
  homepage "https://github.com/macfanpro/macfanpro"
  url "https://github.com/macfanpro/macfanpro.git",
      tag: "v0.2.3.19",
      revision: "cab2c7715e65f2cfc6112881243cb0db7ec799e8"
  license "MIT"
  version_scheme 1

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox",
           "--force-resolved-versions"

    system ".build/release/macfanpro", "build-app",
           "--binary", ".build/release/MacFanProApp",
           "--icon", "MacFanPro.icns",
           "--dest", "#{prefix}/MacFanPro.app"

    system "codesign", "--force", "--deep", "--sign", "-",
           "#{prefix}/MacFanPro.app"

    bin.install ".build/release/macfanpro"

    pkgshare.install "LICENSE", "NOTICE.md", "ThirdPartyNotices"
  end

  def caveats
    <<~EOS
      Install or synchronize the root-owned daemon and menu bar app:
        sudo #{opt_bin}/macfanpro install

      Open /Applications/MacFanPro.app and enable Launch at Login if wanted.

      After brew upgrade:
        #{opt_bin}/macfanpro auto --stop-app
        sudo #{opt_bin}/macfanpro install
        open /Applications/MacFanPro.app

      Before brew uninstall:
        sudo macfanpro uninstall

      User profiles, calibration and logs are preserved unless --purge-data is used.
    EOS
  end

  test do
    assert_equal version.to_s,
                 shell_output("#{bin}/macfanpro --version").strip

    assert_match "Fan control",
                 shell_output("#{bin}/macfanpro --help")

    assert_match "--migrate-thermalforge",
                 shell_output("#{bin}/macfanpro install --help")

    app = prefix/"MacFanPro.app"

    bundle_id = shell_output(
      "/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' " \
      "#{app}/Contents/Info.plist"
    ).strip

    assert_equal "io.github.macfanpro.app", bundle_id

    assert_path_exists app/"Contents/Resources/LICENSE"
    assert_path_exists app/"Contents/Resources/MacFanPro_MacFanProLocalization.bundle"

    system "codesign", "--verify", "--deep", "--strict", app
  end
end