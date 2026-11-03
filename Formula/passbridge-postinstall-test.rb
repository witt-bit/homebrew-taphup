class PassbridgePostinstallTest < Formula
  desc "Probe what a formula's post_install_steps may write outside the Cellar"
  homepage "https://github.com/MehdiMamas/passbridge"
  url "https://github.com/MehdiMamas/passbridge/releases/download/v1.4.20/passbridge.zip"
  sha256 "b5bd56c42895204199a3765a341815e2679326e16b264429d53be3bc5b5e5bca"
  license "GPL-3.0-only"

  # The question this formula answers: can a post-install step write the native messaging
  # manifests into ~/Library/Application Support, the way passbridge needs?
  #
  # Brew's post-install runs inside a sandbox whose rules include Homebrew's deny_read_home, so
  # the expectation is that every ~/Library write is denied while Cellar and TMPDIR writes land.
  # The script is inlined because a post_install_steps block only accepts literal values.

  def install
    (libexec/"installed-by").write "install step\n"
  end

  post_install_steps do
    run "sh", args: ["-c", <<~'SH'], print_stdout: true
      echo "--- who and where ---"
      echo "uid=$(id -u) user=$(id -un)"
      echo "HOME=$HOME"
      echo "TMPDIR=$TMPDIR"
      echo "PWD=$PWD"

      # $HOME is a throwaway directory here, so probing it proves nothing: resolve the real one
      REAL_HOME="$(eval echo "~$(id -un)")"
      echo "REAL_HOME=$REAL_HOME"
      if [ "$REAL_HOME" = "$HOME" ]; then
        echo "NOTE: HOME was not redirected, so this run says nothing about the real home"
      fi

      echo "--- the folders passbridge needs to write (real home) ---"
      for dir in \
        "$REAL_HOME/Library/Application Support/PassBridge-postinstall-probe" \
        "$REAL_HOME/Library/Application Support/PassBridge" \
        "$REAL_HOME/Library/Logs/PassBridge-postinstall-probe"
      do
        if mkdir -p "$dir" 2>/dev/null && printf 'probe\n' > "$dir/probe.txt" 2>/dev/null; then
          echo "WRITE OK      $dir"
          rm -rf "$dir"
        else
          echo "WRITE DENIED  $dir"
        fi
      done

      echo "--- the same paths under the throwaway HOME ---"
      for dir in "$HOME/Library/Application Support/PassBridge-postinstall-probe"
      do
        if mkdir -p "$dir" 2>/dev/null && printf 'probe\n' > "$dir/probe.txt" 2>/dev/null; then
          echo "WRITE OK      $dir (this is the sandbox HOME, not yours)"
          rm -rf "$dir"
        else
          echo "WRITE DENIED  $dir"
        fi
      done

      echo "--- controls that should always work ---"
      for dir in "$TMPDIR/passbridge-postinstall-probe" "$PWD/../probe"
      do
        if mkdir -p "$dir" 2>/dev/null && printf 'probe\n' > "$dir/probe.txt" 2>/dev/null; then
          echo "WRITE OK      $dir"
          rm -rf "$dir"
        else
          echo "WRITE DENIED  $dir"
        fi
      done

      echo "--- can we even read the browser support folders? ---"
      for dir in "$REAL_HOME/Library/Application Support/Google/Chrome" \
                 "$REAL_HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
      do
        if [ -d "$dir" ]; then
          if ls "$dir" >/dev/null 2>&1; then echo "READ OK       $dir"; else echo "READ DENIED   $dir"; fi
        else
          echo "MISSING       $dir"
        fi
      done

      echo "--- the real setup, if passbridge is installed ---"
      setup="$(brew --prefix 2>/dev/null)/opt/passbridge/bin/passbridge-setup"
      if [ -x "$setup" ]; then
        "$setup" --quiet
        echo "passbridge-setup exit=$?"
      else
        echo "skipped: $setup is not installed"
      fi
    SH
  end

  def caveats
    <<~EOS
      Nothing useful was installed; this formula only reports what post-install may write.

      Probe output:
        brew install witt/taps/passbridge-postinstall-test --verbose

      The sandbox rules Homebrew applied are logged at:
        ~/Library/Logs/Homebrew/passbridge-postinstall-test/postinstall.sandbox.log

      Re-run only the post-install step:
        brew postinstall witt/taps/passbridge-postinstall-test

      Remove it with:
        brew uninstall passbridge-postinstall-test
    EOS
  end

  test do
    assert_path_exists libexec/"installed-by"
  end
end
