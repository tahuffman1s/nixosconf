{ config, pkgs, ...}:
let 
  # The theme archives are shipped in this repo (Files/), so unpack them in a
  # derivation instead of downloading them from GitHub at evaluation time.
  unpack = name: src: pkgs.runCommand name { } ''
    mkdir -p "$out"
    tar --warning=no-unknown-keyword -xJf ${src} -C "$out"
  '';
  gtkTheme = unpack "dracula-gtk-theme" ../Files/Dracula.tar.xz;
  iconTheme = unpack "tela-circle-dracula-icons" ../Files/Tela-circle-dracula.tar.xz;
in 
{
  home.file = {
    ".themes" = {source = "${gtkTheme}";};
    ".icons" = {source = "${iconTheme}";};
    ".local/share/icons" = {source = "${iconTheme}";};
  };

  gtk = {
    enable = true;
    theme = {
      name = "Dracula";
    };
    # Keep applying the same theme to GTK4 apps (new home-manager default is none).
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name = "Tela-circle-dark";
    };
  };
}
