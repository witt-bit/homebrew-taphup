class Passbridge < Formula
  desc "Autofill iCloud Passwords in Chromium browsers"
  homepage "https://github.com/MehdiMamas/passbridge"
  url "https://github.com/MehdiMamas/passbridge/releases/download/v1.4.20/passbridge.zip"
  sha256 "b5bd56c42895204199a3765a341815e2679326e16b264429d53be3bc5b5e5bca"
  license "GPL-3.0-only"

  depends_on :macos

  # The helper ships as a second asset. passbridge-updater.py is deliberately left out: this formula
  # owns updates, so the extension must not replace its own files behind Homebrew's back.
  resource "helper" do
    url "https://github.com/MehdiMamas/passbridge/releases/download/v1.4.20/passbridge-macos-helper.zip"
    sha256 "95ed02826e2dee345d88c642c6495589d23174ade2e686d0e7328dac500512ac"
  end

  def install
    # The extension is loaded unpacked straight out of the Cellar; libexec keeps it away from bin/
    # and opt_libexec gives Chrome a path that survives brew upgrade.
    ext = libexec/"extension"
    ext.mkpath
    ext.install Dir["*"]

    # Updates are Homebrew's job here. Every copy of the defaults table says "check" and
    # "install automatically"; both are turned off so the 30-minute alarm goes quiet.
    # Minified bundles write boolean true as !0 and false as !1.
    flip = {
      "canCheckForUpdates: true" => "canCheckForUpdates: false",
      "autoInstallUpdates: true" => "autoInstallUpdates: false",
      "canCheckForUpdates:!0"    => "canCheckForUpdates:!1",
      "autoInstallUpdates:!0"    => "autoInstallUpdates:!1",
    }
    (ext/"src").glob("*.js").each do |file|
      body = file.read
      next unless body.match?(/canCheckForUpdates|autoInstallUpdates/)

      flip.each { |before, after| body = body.gsub(before, after) }
      # Homebrew's Pathname#write refuses to overwrite, and these files were just installed
      File.write(file.to_s, body)
    end

    # a release that renames or reshapes its defaults would slip through the flip above unnoticed
    leftover = /(canCheckForUpdates|autoInstallUpdates):\s*(true|!0)/
    stale = (ext/"src").glob("*.js").select { |file| file.read.match?(leftover) }
    odie "Update flags still on in #{stale.join(", ")}: the release changed shape, review the formula." if stale.any?

    install_helper
    install_setup
  end

  def install_helper
    # staged with an explicit target: the zip holds one top-level folder and a bare block
    # would leave us guessing which directory Homebrew landed us in
    staged = buildpath/"helper-stage"
    resource("helper").stage(staged)
    # Homebrew strips a lone top-level folder while staging, so the scripts may sit either way
    root = (staged/"passbridge-macos-helper").directory? ? staged/"passbridge-macos-helper" : staged
    odie("The helper zip no longer holds the helper scripts.") unless (root/"passbridge-policy.py").exist?

    (libexec/"helper").install root/"passbridge-policy.py",
                                root/"passbridge-agent.py",
                                root/"passbridge-agent-cli.py"
    chmod 0755, (libexec/"helper").children
  end

  def install_setup
    # the agent's command-line client is meant to be typed, not path-ed
    bin.install_symlink (libexec/"helper/passbridge-agent-cli.py") => "passbridge-agent"

    (libexec/"passbridge-setup").write setup_script
    chmod 0755, libexec/"passbridge-setup"
    bin.install_symlink libexec/"passbridge-setup"

    # No post_install_steps: Homebrew sandboxes post-install with deny_read_home, so a formula
    # cannot write the native messaging manifests into ~/Library. The caveats run the command once.
  end

  def caveats
    <<~EOS
      Run this once to register the helper and load the extension:

        #{opt_bin}/passbridge-setup

      Homebrew sandboxes post-install steps and cannot write into ~/Library, so this is a
      separate command rather than something `brew install` does for you. Quit Chrome first
      (Cmd+Q): the setup writes the native messaging hosts into each browser profile and can
      only switch the extension on while the browser is closed. Re-run it after adding a new
      browser.

      If PassBridge still is not in chrome://extensions, load it by hand:

        1. Open chrome://extensions
        2. Turn on Developer mode
        3. Click "Load unpacked" and pick #{opt_libexec}/extension

      Disable Apple's iCloud Passwords extension: it uses the same extension id as PassBridge.

      After `brew upgrade passbridge`, quit Chrome and run the setup again: the extension folder
      lives under the Cellar, and Chrome may hold the upgraded-away path until it is re-registered.

      In this build the extension's own updater is switched off and passbridge-updater.py is
      not installed, so `brew upgrade passbridge` is the only way PassBridge moves forward.
      If an earlier manual install left "Install updates automatically" on in PassBridge
      settings, turn it off there too.
    EOS
  end

  def setup_script
    # Single-quoted heredoc: nothing here is interpolated, the script locates itself at run time.
    <<~'PY'
      #!/usr/bin/python3
      # Register PassBridge's native messaging hosts and try to load the unpacked extension.
      # Safe to re-run; does nothing destructive. Lives in the Cellar, so it must not import anything.
      import glob
      import json
      import os
      import pwd
      import shutil
      import sys

      EXT_ID = "pejdijmoenmkgeppbflobdenhhabjlaj"
      HOSTS = ["com.passbridge.policy", "com.passbridge.agent"]
      # helper scripts this formula installs, and the ones it must not leave behind
      KEEP = ["passbridge-policy.py", "passbridge-agent.py", "passbridge-agent-cli.py"]
      DROP = ["passbridge-updater.py", "helper-version", "passbridge-autopair.py", "PassBridge Helper.app"]
      LEGACY_HOSTS = ["com.passbridge.updater", "com.passbridge.autopair", "com.openpasswords.policy", "com.openpasswords.autopair"]
      BROWSERS = [
          "Google/Chrome",
          "Google/Chrome Beta",
          "Google/Chrome Dev",
          "Google/Chrome Canary",
          "Microsoft Edge",
          "Chromium",
          "Arc/User Data",
          "Vivaldi",
          "BraveSoftware/Brave-Browser",
      ]
      UNPACKED = 4
      HOME = pwd.getpwuid(os.getuid()).pw_dir
      SUPPORT = os.path.join(HOME, "Library", "Application Support")
      APPDIR = os.path.join(SUPPORT, "PassBridge")
      QUIET = "--quiet" in sys.argv


      def say(msg):
          if not QUIET:
              print(msg)


      def warn(msg):
          print(msg, file=sys.stderr)


      def stable(path):
          """map /prefix/Cellar/passbridge/<version>/libexec to /prefix/opt/passbridge/libexec"""
          parts = path.split(os.sep)
          if "Cellar" not in parts:
              return path
          i = parts.index("Cellar")
          if len(parts) < i + 4:
              return path
          prefix, name, rest = os.sep.join(parts[: i]), parts[i + 1], parts[i + 3 :]
          return os.path.join(prefix, "opt", name, *rest)


      LIBEXEC = stable(os.path.dirname(os.path.realpath(__file__)))
      HELPER = os.path.join(LIBEXEC, "helper")
      EXTENSION = os.path.join(LIBEXEC, "extension")
      SCRIPT = {name: os.path.join(HELPER, name) for name in KEEP}


      def link_helper():
          os.makedirs(APPDIR, exist_ok=True)
          for name in KEEP:
              target = SCRIPT[name]
              link = os.path.join(APPDIR, name)
              if not os.path.exists(target):
                  warn("  missing helper script: " + target)
                  continue
              if os.path.islink(link) or os.path.exists(link):
                  os.remove(link)
              os.symlink(target, link)
              say("  linked " + link)
          for name in DROP:
              path = os.path.join(APPDIR, name)
              if os.path.islink(path) or os.path.isfile(path):
                  os.remove(path)
                  say("  removed " + path)
              elif os.path.isdir(path):
                  shutil.rmtree(path, ignore_errors=True)
                  say("  removed " + path)


      def host_dirs():
          found = []
          for browser in BROWSERS:
              base = os.path.join(SUPPORT, browser)
              if os.path.isdir(base):
                  found.append(os.path.join(base, "NativeMessagingHosts"))
          for base in glob.glob(os.path.join(SUPPORT, "BraveSoftware", "*")):
              if os.path.isdir(base):
                  found.append(os.path.join(base, "NativeMessagingHosts"))
          return found


      def write_hosts():
          dirs = host_dirs()
          for directory in dirs:
              os.makedirs(directory, exist_ok=True)
              for name in HOSTS:
                  script = "passbridge-policy.py" if name.endswith("policy") else "passbridge-agent.py"
                  entry = {
                      "name": name,
                      "description": "PassBridge " + ("policy helper" if name.endswith("policy") else "agent sign-in host"),
                      # through the symlink, so the browsers keep one stable path across upgrades
                      "path": os.path.join(APPDIR, script),
                      "type": "stdio",
                      "allowed_origins": ["chrome-extension://" + EXT_ID + "/"],
                  }
                  with open(os.path.join(directory, name + ".json"), "w", encoding="utf-8") as f:
                      json.dump(entry, f, indent=2)
                      f.write("\n")
              for name in LEGACY_HOSTS:
                  stale = os.path.join(directory, name + ".json")
                  if os.path.exists(stale):
                      os.remove(stale)
                      say("  removed stale host " + stale)
          if not dirs:
              warn("  no Chromium browser profile found yet; run passbridge-setup after installing one")
          return dirs


      def browser_running(browser):
          marker = os.path.join(SUPPORT, browser, "SingletonLock")
          return os.path.islink(marker) or os.path.exists(marker)


      def enable_extension(profiles):
          """best effort: an unpacked entry is location 4, state 1. Chrome may rewrite this itself."""
          try:
              with open(os.path.join(EXTENSION, "manifest.json"), encoding="utf-8") as f:
                  manifest = json.load(f)
          except (OSError, ValueError):
              warn("  extension manifest unreadable, skipping auto-load")
              return False
          perms = {"api": [p for p in manifest.get("permissions", []) if isinstance(p, str)],
                   "explicit_host": list(manifest.get("host_permissions", []))}
          entry = {
              "location": UNPACKED,
              "path": EXTENSION,
              "state": 1,
              "from_webstore": False,
              "was_installed_by_default": False,
              "was_installed_by_oem": False,
              "creation_flags": 38,
              "manifest": manifest,
              "active_permissions": perms,
              "granted_permissions": perms,
              "withheld_permissions": {"api": [], "explicit_host": [], "scriptable_host": []},
          }
          wrote = False
          for path in profiles:
              try:
                  with open(path, encoding="utf-8") as f:
                      prefs = json.load(f)
              except (OSError, ValueError):
                  warn("  unreadable profile: " + path)
                  continue
              settings = prefs.setdefault("extensions", {}).setdefault("settings", {})
              current = settings.get(EXT_ID) or {}
              current.update(entry)
              settings[EXT_ID] = current
              try:
                  tmp = path + ".passbridge-tmp"
                  with open(tmp, "w", encoding="utf-8") as f:
                      json.dump(prefs, f)
                  os.replace(tmp, path)
                  wrote = True
                  say("  enabled in " + path)
              except OSError as exc:
                  warn("  could not write " + path + ": " + str(exc))
          return wrote


      def profile_files(dirs, skip):
          out = []
          for directory in dirs:
              browser = os.path.dirname(directory)
              if os.path.realpath(browser) in skip:
                  continue
              for pattern in ("Preferences", "Secure Preferences"):
                  out += glob.glob(os.path.join(glob.escape(browser), "*", pattern))
          return out


      def main():
          if not os.path.isdir(HELPER):
              say("helper folder missing: " + HELPER)
              return 1
          say("PassBridge helper: " + HELPER)
          link_helper()
          dirs = write_hosts()
          running = {os.path.realpath(os.path.dirname(d)) for d in dirs if browser_running(os.path.dirname(d))}
          profiles = profile_files(dirs, running)
          if running:
              names = sorted(os.path.relpath(p, SUPPORT) for p in running)
              warn("  " + ", ".join(names) + " is running; left its profile alone")
              profiles = [p for p in profiles if os.path.realpath(os.path.dirname(os.path.dirname(p))) not in running]
          if profiles:
              enable_extension(profiles)
          else:
              say("  no writable browser profile found; use Load unpacked in chrome://extensions")
          say("")
          say("Extension folder: " + EXTENSION)
          say("Start (or restart) your browser. If PassBridge is not listed, use Load unpacked on that folder.")
          return 0


      if __name__ == "__main__":
          sys.exit(main())
    PY
  end

  test do
    assert_path_exists libexec/"extension/manifest.json"
    assert_match "\"version\": \"#{version}\"", (libexec/"extension/manifest.json").read
    assert_path_exists libexec/"extension/_locales/zh_CN/messages.json"
    assert_path_exists libexec/"extension/_locales/zh_TW/messages.json"

    # updates must be off in every bundled copy of the defaults table
    (libexec/"extension/src").glob("*.js").each do |file|
      refute_match(/(canCheckForUpdates|autoInstallUpdates):\s*(true|!0)/, file.read,
                   "#{file.basename} would still update itself")
    end

    assert_path_exists libexec/"helper/passbridge-policy.py"
    assert_path_exists libexec/"helper/passbridge-agent.py"
    assert_path_exists libexec/"helper/passbridge-agent-cli.py"
    refute_path_exists libexec/"helper/passbridge-updater.py"
    assert_predicate libexec/"helper/passbridge-policy.py", :executable?
    assert_predicate libexec/"passbridge-setup", :executable?

    # no managed profile forces the key, so the policy helper exits 3 for --forced
    assert_match "status=3",
                 shell_output("#{libexec}/helper/passbridge-policy.py --forced; echo status=$?")
  end
end
