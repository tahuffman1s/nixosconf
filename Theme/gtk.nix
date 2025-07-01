{ config, pkgs, ...}:
let 
  gtkTheme = builtins.fetchTarball {
    url = "https://github.com/tahuffman1s/nixosconf/raw/refs/heads/main/Files/Dracula.tar.xz";
    sha256 = "1xrbv4nw918xjm79qpwlbyviis7s86d4pn4j68ll0iqjic0fzkxa";
  };
  iconTheme = builtins.fetchTarball {
    url = "https://github.com/tahuffman1s/nixosconf/raw/refs/heads/main/Files/Tela-circle-dracula.tar.xz";
    sha256 = "1kqzw8ajm2hvn1fa0xbx977amq0jblkd2ipsxw7qrb9i0cxm6j6c";
  };
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
    iconTheme = {
      name = "Tela-circle-dark";
    };
  };
}