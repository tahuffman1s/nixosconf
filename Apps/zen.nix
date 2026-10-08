{ config, pkgs, lib, ...}:
let 
  # Zen is a Flatpak, so it cannot read /etc/zen. Its Flatpak declares a
  # "systemconfig" extension point instead: whatever is placed under
  # /var/lib/flatpak/extension/app.zen_browser.zen.systemconfig/<arch>/stable
  # shows up inside the sandbox as /app/etc/zen, where Zen (like Firefox)
  # looks for policies/policies.json. The file has to be a real copy, since
  # a symlink into /nix/store would not resolve inside the sandbox.
  extensionDir = "/var/lib/flatpak/extension/app.zen_browser.zen.systemconfig/${pkgs.stdenv.hostPlatform.linuxArch}/stable";

  amo = slug: "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
  extension = slug: extra: {
    installation_mode = "normal_installed";   # installed, but the user may disable it
    install_url = amo slug;
  } // extra;

  policies = {
    policies = {
      # Carried over from the Flatpak's own distribution/policies.json, which
      # this file replaces.
      DisableAppUpdate = true;
      DontCheckDefaultBrowser = true;

      # Plain system DNS, no DNS over HTTPS.
      DNSOverHTTPS = {
        Enabled = false;
        Locked = true;
      };

      # Proton Pass handles credentials; do not store anything in the browser.
      PasswordManagerEnabled = false;
      OfferToSaveLogins = false;
      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;

      SearchEngines = {
        Default = "Brave";
        Add = [
          {
            Name = "Brave";
            Description = "Brave Search";
            Alias = "@brave";
            Method = "GET";
            URLTemplate = "https://search.brave.com/search?q={searchTerms}";
            SuggestURLTemplate = "https://search.brave.com/api/suggest?q={searchTerms}";
            IconURL = "https://brave.com/static-assets/images/brave-favicon.png";
          }
        ];
      };

      ExtensionSettings = {
        "78272b6fa58f4a1abaac99321d503a20@proton.me" = extension "proton-pass" { default_area = "navbar"; };
        "uBlock0@raymondhill.net" = extension "ublock-origin" { default_area = "navbar"; };
        "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" = extension "return-youtube-dislikes" { };
        "sponsorBlocker@ajay.app" = extension "sponsorblock" { };
        "{74145f27-f039-47ce-a470-a662b129930a}" = extension "clearurls" { };
        "jid1-MnnxcxisBPnSXQ@jetpack" = extension "privacy-badger17" { };
      };
    };
  };

  policiesFile = (pkgs.formats.json { }).generate "zen-policies.json" policies;
in 
{
  systemd.tmpfiles.settings."10-zen-policies" = {
    "${extensionDir}/policies".d = { mode = "0755"; };
    "${extensionDir}/policies/policies.json"."C+" = {
      argument = "${policiesFile}";
      mode = "0644";
    };
  };
}
