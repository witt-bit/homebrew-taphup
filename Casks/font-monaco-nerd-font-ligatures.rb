cask "font-monaco-nerd-font-ligatures" do
  version :latest
  sha256 :no_check

  url "https://github.com/RooobinYe/monaco-nerd-font-liga.git",
      branch:    "main",
      only_path: "fonts-liga-nerd"
  name "Monaco Nerd Font Ligatures"
  desc "Monaco Nerd Font with Ligature."
  homepage "https://github.com/RooobinYe/monaco-nerd-font-liga"

  font "LigaMonacoNerdFont-Bold.ttf"
  font "LigaMonacoNerdFont-BoldItalic.ttf"
  font "LigaMonacoNerdFont-Italic.ttf"
  font "LigaMonacoNerdFont-Regular.ttf"

  # No zap stanza required
end
