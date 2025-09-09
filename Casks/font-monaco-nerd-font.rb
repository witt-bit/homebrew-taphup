cask "font-monaco-nerd-font" do
  version "0.2.1"
  sha256 "b28f08eb0c921278a08cabd5cf72616ba8c1d354a0c79a62db864a5578194e60"

  url "https://github.com/thep0y/monaco-nerd-font/releases/download/v#{version}/MonacoNerdFont.zip"
  name "Monaco Nerd Font"
  desc "This font is modified from Monaco.ttf extracted from macOS Ventura, with bold, italic, and bold italic added"
  homepage "https://github.com/thep0y/monaco-nerd-font"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  font "MonacoNerdFont-Regular.ttf"
  font "MonacoNerdFont-Italic.ttf"
  font "MonacoNerdFont-Bold.ttf"
  font "MonacoNerdFont-BoldItalic.ttf"
  # No zap stanza required
end
