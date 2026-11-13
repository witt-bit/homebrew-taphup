class Passbridge < Formula
  desc "Autofill iCloud Passwords in Chromium browsers"
  homepage "https://github.com/MehdiMamas/passbridge"
  url "https://github.com/MehdiMamas/passbridge/releases/download/v1.4.31/passbridge.zip"
  sha256 "5778e6f7fa621dc6d18414aec28ab386316eefe44beb736ab80ad656cf6cff4f"
  license "GPL-3.0-only"

  depends_on :macos

  # The helper ships as a second asset. passbridge-updater.py is deliberately left out: this formula
  # owns updates, so the extension must not replace its own files behind Homebrew's back.
  resource "helper" do
    url "https://github.com/MehdiMamas/passbridge/releases/download/v1.4.31/passbridge-macos-helper.zip"
    sha256 "ca87e86cebe42abd03432aa91cef328f3bf28411eb8e996dd7f8ccc5404e0822"
  end

  def install
    # The browser records the path it loaded and resolves symlinks when it does, so pointing it at
    # libexec stores .../Cellar/passbridge/<version>/libexec/extension, which stops existing on the
    # next upgrade. var has no version in it and the build sandbox allows writing there, so the
    # recorded path stays valid and `brew upgrade` refreshes the files in place.
    ext = var/"passbridge/extension"
    rm_r ext if ext.exist?
    ext.mkpath
    ext.install Dir["*"]

    # managed.json next to manifest.json is the release's own way of saying "someone else owns
    # updates": with it true the extension turns its checks off, hides the Updates tab and stops
    # a badge, and a saved "check for updates" synced from another machine cannot undo that. The
    # zip ships {"managed": false}, and this folder is rewritten on every upgrade, so write it
    # each install. Homebrew's Pathname#write will not replace a file, hence File.write.
    File.write((ext/"managed.json").to_s, '{ "managed": true }')

    install_helper
    install_setup
  end

  # the extension lives outside the keg so the browser keeps a stable path, so removing
  # the keg alone would leave it behind
  def uninstall
    installed = var/"passbridge"
    rm_r installed if installed.exist?
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
      Run this once:

        #{opt_bin}/passbridge-setup

      Then, in each browser it opens:

        1. Turn on Developer mode
        2. Click "Load unpacked"
        3. Pick ~/Library/Application Support/PassBridge/extension

      Homebrew cannot write into ~/Library and Chromium discards extension entries it did not
      write itself, so the extension is loaded by hand once. The browser keeps it afterwards.

      Disable Apple's iCloud Passwords extension: it uses the same extension id as PassBridge.

      Updates come from `brew upgrade passbridge`. Do not re-run the setup command after one.
    EOS
  end

  def setup_script
    # Single-quoted heredoc: nothing here is interpolated, the script locates itself at run time.
    <<~'PY'
      #!/usr/bin/python3
      # Register PassBridge's native messaging hosts and report whether the unpacked extension is loaded.
      # Safe to re-run; does nothing destructive. Lives in the Cellar, so it imports only the stdlib.
      import json, os, pwd, shutil, subprocess, sys, time

      EXT_ID = "pejdijmoenmkgeppbflobdenhhabjlaj"
      HOSTS = {
          "com.passbridge.policy": ("passbridge-policy.py", "policy helper"),
          "com.passbridge.agent": ("passbridge-agent.py", "agent sign-in host"),
      }
      DROP = [
          "passbridge-policy.py", "passbridge-agent.py", "passbridge-agent-cli.py",
          "passbridge-updater.py", "helper-version", "passbridge-autopair.py",
          "PassBridge Helper.app",
      ]
      LEGACY_HOSTS = [
          "com.passbridge.updater", "com.passbridge.autopair",
          "com.openpasswords.policy", "com.openpasswords.autopair",
      ]

      # browser path -> (app name for osascript/open, bundle id for mdfind, display name)
      APPS = {
          "Google/Chrome": ("Google Chrome", "com.google.Chrome", "Google Chrome"),
          "Google/Chrome Beta": ("Google Chrome Beta", "com.google.Chrome.beta", "Chrome Beta"),
          "Google/Chrome Dev": ("Google Chrome Dev", "com.google.Chrome.dev", "Chrome Dev"),
          "Google/Chrome Canary": ("Google Chrome Canary", "com.google.Chrome.canary", "Chrome Canary"),
          "Microsoft Edge": ("Microsoft Edge", "com.microsoft.Edge", "Microsoft Edge"),
          "Chromium": ("Chromium", "org.chromium.Chromium", "Chromium"),
          "Arc/User Data": ("Arc", "company.thebrowser.Browser", "Arc"),
          "Vivaldi": ("Vivaldi", "com.vivaldi.Vivaldi", "Vivaldi"),
          "BraveSoftware/Brave-Browser": ("Brave Browser", "com.brave.Browser", "Brave"),
          "BraveSoftware/Brave-Browser-Beta": ("Brave Browser Beta", "com.brave.Browser.beta", "Brave Beta"),
          "BraveSoftware/Brave-Browser-Dev": ("Brave Browser Dev", "com.brave.Browser.dev", "Brave Dev"),
          "BraveSoftware/Brave-Browser-Nightly": ("Brave Browser Nightly", "com.brave.Browser.nightly", "Brave Nightly"),
      }

      HOME = pwd.getpwuid(os.getuid()).pw_dir
      SUPPORT = os.path.join(HOME, "Library", "Application Support")
      APPDIR = os.path.join(SUPPORT, "PassBridge")
      QUIET = "--quiet" in sys.argv
      # the folder the browser is asked to load; see extension_path()
      ALIAS = os.path.join(APPDIR, "extension")


      def say(msg):
          if not QUIET:
              print(msg)


      def warn(msg):
          print(msg, file=sys.stderr)

      def green(msg):
          """print in green for action guidance the user needs to take"""
          print("\033[32m" + msg + "\033[0m")

      def red(msg):
          """print in red for errors and failures"""
          print("\033[31m" + msg + "\033[0m")


      def stable(path):
          """map /prefix/Cellar/passbridge/<version>/libexec to /prefix/opt/passbridge/libexec"""
          parts = path.split(os.sep)
          if "Cellar" not in parts:
              return path
          i = parts.index("Cellar")
          if len(parts) < i + 4:
              return path
          return os.sep.join(parts[:i] + ["opt", parts[i + 1]] + parts[i + 3:])


      LIBEXEC = stable(os.path.dirname(os.path.realpath(__file__)))
      HELPER = os.path.join(LIBEXEC, "helper")
      # /prefix/opt/passbridge/libexec -> /prefix/var/passbridge/extension. The extension is kept
      # out of the Cellar on purpose: a browser records the path it loaded, so a versioned one
      # stops existing after an upgrade.
      _parts = LIBEXEC.split(os.sep)
      EXTENSION = os.path.join(os.sep.join(_parts[:_parts.index("passbridge") - 1]),
                               "var", "passbridge", "extension")


      def drop(path):
          if os.path.islink(path) or os.path.isfile(path):
              os.remove(path)
          elif os.path.isdir(path):
              shutil.rmtree(path, ignore_errors=True)
          else:
              return
          say("  removed " + path)


      def clean_appdir():
          if not os.path.isdir(APPDIR):
              return
          for name in DROP:
              drop(os.path.join(APPDIR, name))


      def info(browser):
          """(app_name, bundle_id, display_name) or (None, None, relpath)"""
          rel = os.path.relpath(browser, SUPPORT)
          return APPS.get(rel, (None, None, rel))


      def browsers():
          """installed Chromium browsers with a profile folder. SIP blocks glob.glob on
          ~/Library/Application Support, so check known paths directly."""
          return [
              os.path.join(SUPPORT, p) for p in APPS
              if os.path.isdir(os.path.join(SUPPORT, p)) and installed(os.path.join(SUPPORT, p))
          ]


      def installed(browser):
          bundle = info(browser)[1]
          if not bundle:
              return False
          r = subprocess.run(["mdfind", "kMDItemCFBundleIdentifier == '%s'" % bundle],
                             capture_output=True, text=True, timeout=30)
          return bool(r.stdout.strip())


      def write_hosts(bases):
          for base in bases:
              directory = os.path.join(base, "NativeMessagingHosts")
              os.makedirs(directory, exist_ok=True)
              for name, (script, what) in HOSTS.items():
                  entry = {
                      "name": name,
                      "description": "PassBridge " + what,
                      "path": os.path.join(HELPER, script),
                      "type": "stdio",
                      "allowed_origins": ["chrome-extension://" + EXT_ID + "/"],
                  }
                  with open(os.path.join(directory, name + ".json"), "w", encoding="utf-8") as f:
                      json.dump(entry, f, indent=2)
                      f.write("\n")
              for name in LEGACY_HOSTS:
                  stale = os.path.join(directory, name + ".json")
                  if os.path.exists(stale):
                      drop(stale)
          if not bases:
              warn("  no Chromium browser found yet; run passbridge-setup after installing one")


      def profile_files(bases):
          out = []
          for base in bases:
              for d in ["Default"] + ["Profile %d" % i for i in range(1, 20)]:
                  for name in ("Preferences", "Secure Preferences"):
                      path = os.path.join(base, d, name)
                      if os.path.exists(path):
                          out.append(path)
          return out

      def loaded(base):
          """True when a profile already holds PassBridge, False when none does,
          None when we cannot tell (no profile yet, or the files are unreadable)"""
          files = profile_files([base])
          if not files:
              return None
          found = False
          for path in files:
              try:
                  with open(path, encoding="utf-8") as f:
                      prefs = json.load(f)
              except PermissionError:
                  return None
              except (OSError, ValueError):
                  continue
              entry = prefs.get("extensions", {}).get("settings", {}).get(EXT_ID)
              # only the browser writes first_install_time; an entry without it came from the
              # profile writing this command used to do, which the browser then throws away.
              # a missing state means enabled, which is how unpacked entries are stored.
              if not entry or entry.get("location") != 4 or not entry.get("first_install_time"):
                  continue
              # a path that no longer exists means the browser kept a folder an upgrade removed,
              # which shows up as a broken extension until it is loaded again
              if not os.path.isdir(entry.get("path") or ""):
                  continue
              if entry.get("state", 1) == 1:
                  found = True
          return found


      def extension_path():
          """point a short, readable path at the extension. The files live under the Cellar,
          reached through /opt/homebrew/opt, which a native open panel makes you hunt for.
          This symlink keeps the browser pointing at one stable path across upgrades."""
          folder = os.path.dirname(ALIAS)
          try:
              os.makedirs(folder, exist_ok=True)
          except OSError:
              return None
          if os.path.islink(ALIAS):
              if os.path.realpath(ALIAS) == os.path.realpath(EXTENSION):
                  return ALIAS
              try:
                  os.remove(ALIAS)
              except OSError:
                  return None
          elif os.path.exists(ALIAS):
              warn("  %s is a real folder, leaving it alone" % ALIAS)
              return None
          try:
              os.symlink(EXTENSION, ALIAS)
          except OSError:
              return None
          return ALIAS


      # every engine brands its own extensions page and the scheme is not interchangeable
      PAGES = {
          "Arc": "arc://extensions",
          "Microsoft Edge": "edge://extensions",
          "Vivaldi": "vivaldi://extensions",
          "Brave Browser": "brave://extensions",
          "Brave Browser Beta": "brave://extensions",
          "Brave Browser Dev": "brave://extensions",
          "Brave Browser Nightly": "brave://extensions",
      }
      PAGE = "chrome://extensions"


      def ext_page(app):
          return PAGES.get(app, PAGE)


      def open_extensions(app):
          """show the extensions page in the given browser"""
          url = ext_page(app)
          r = subprocess.run(
              ["osascript", "-e",
               'tell application "%s" to open location "%s"' % (app.replace('"', '\\"'), url)],
              capture_output=True, text=True, timeout=30)
          if r.returncode != 0:
              subprocess.run(["open", "-a", app, url], capture_output=True, text=True, timeout=60)


      def main():
          if not os.path.isdir(HELPER):
              warn("helper folder missing: " + HELPER)
              return 1
          say("PassBridge helper: " + HELPER)
          clean_appdir()
          bases = browsers()
          write_hosts(bases)
          if not bases:
              warn("No Chromium browser found yet. Install one, start it once, then run this again.")
              say("Extension folder: " + EXTENSION)
              return 0

          # no profile writing here on purpose: Chromium MAC-signs the whole extensions
          # subtree in Secure Preferences, so an entry we inject is discarded on the next
          # start. Only the browser itself can record it, which is what Load unpacked does.
          say("")
          say("Extension:")
          pending = []
          for base in bases:
              app, _, name = info(base)
              state = loaded(base)
              if state is True:
                  say("  %-18s already loaded" % name)
              elif not profile_files([base]):
                  green("  %-18s no profile yet, start it once" % name)
                  pending.append((app, name))
              elif state is None:
                  red("  %-18s no access to profiles" % name)
                  pending.append((app, name))
              else:
                  green("  %-18s not loaded yet" % name)
                  pending.append((app, name))

          if pending:
              pick = extension_path() or EXTENSION
              say("")
              green("To finish -- one time only, per browser:")
              green("  1. Open the extensions page")
              green("  2. Turn on Developer mode")
              green('  3. Click "Load unpacked" and pick:')
              green("       " + pick)
              if pick == ALIAS:
                  green("     In the dialog press Cmd+Shift+G, paste the folder this one")
                  green("     sits in, then pick the \"extension\" folder:")
                  green("       " + os.path.dirname(pick))
              green("  It stays after this, so `brew upgrade` needs no reload.")
              say("")
              for app, name in pending:
                  say("  opening %s in %s" % (ext_page(app), name))
                  open_extensions(app)
          else:
              green("  Nothing to do: every browser already has it.")

          command = os.path.join(os.path.dirname(LIBEXEC), "bin", "passbridge-setup")
          say("")
          say("`brew upgrade` needs no re-run: the extension and helper live at a path that stays")
          say("put across versions. Run this again only after installing a new browser:")
          say("  " + command)
          return 0


      if __name__ == "__main__":
          sys.exit(main())
    PY
  end

  test do
    ext = var/"passbridge/extension"
    src = ext/"src"

    assert_path_exists ext/"manifest.json"
    assert_match "\"version\": \"#{version}\"", (ext/"manifest.json").read
    assert_path_exists ext/"_locales/zh_CN/messages.json"
    assert_path_exists ext/"_locales/zh_TW/messages.json"

    # Homebrew owns updates here, so the marker has to be on, and the bundles have to keep reading
    # it: a release that renames or drops the file would leave updates running under the formula.
    assert_match(/^\{\s*"managed":\s*true\s*\}$/, (ext/"managed.json").read, "updates are not marked as managed")
    assert_match "managed.json", (src/"options.js").read, "the options page no longer reads the marker"
    assert_match "managed.json", (src/"background.js").read, "the worker no longer reads the marker"

    assert_path_exists libexec/"helper/passbridge-policy.py"
    assert_path_exists libexec/"helper/passbridge-agent.py"
    assert_path_exists libexec/"helper/passbridge-agent-cli.py"
    refute_path_exists libexec/"helper/passbridge-updater.py"
    assert_predicate libexec/"helper/passbridge-policy.py", :executable?
    assert_predicate libexec/"passbridge-setup", :executable?

    # --forced answers 0 when a profile forces the keys and 3 when none does; both are the helper
    # working. Anything else, and the assertion below fails instead of the exit code going unnoticed.
    assert_match(/status=[03]/,
                 shell_output("#{libexec}/helper/passbridge-policy.py --forced; echo status=$?"))

    # the profile the switch writes has to cover saving and filling, whichever release ships it
    assert_match "PasswordManagerBlocklist", (libexec/"helper/passbridge-policy.py").read
  end
end
