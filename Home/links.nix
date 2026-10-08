{ config, lib, pkgs, ...}:
let 
  backup = "/mnt/GD2/Backup";

  # Home entries that are replaced by symlinks into the backup drive.
  # Left side is the name in ~, right side is the path under ${backup}.
  links = {
    "Documents" = "Documents";
    "Downloads" = "Downloads";
    "Music" = "Music";
    "Pictures" = "Pictures";
    "Videos" = "Videos";
    ".ssh" = ".ssh";
    "Calibre Library" = "Books/Calibre Library";
    "Manga Library" = "Books/Manga Library";
    "Textbook Library" = "Books/Textbook Library";
    "Audiobooks" = "Books/Audiobooks";
  };

  # The local folders that get removed before the links are created.
  replaced = [ "Documents" "Downloads" "Music" "Pictures" "Videos" ".ssh" ];
in 
{
  home.file = lib.mapAttrs (name: target: {
    source = config.lib.file.mkOutOfStoreSymlink "${backup}/${target}";
  }) links;

  # Runs on every rebuild, before home-manager checks for files in the way.
  # Only acts on real directories; once a name is a symlink it is left alone.
  # Anything still inside a folder is moved into its backup target rather than
  # thrown away, so nothing is lost if the folder was not emptied first.
  home.activation.replaceHomeDirs = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    if [ -z "$HOME" ]; then
      echo "links.nix: HOME is not set, skipping" >&2
    elif ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/GD2 || [ ! -d "${backup}" ]; then
      echo "links.nix: ${backup} is not available, leaving home folders alone" >&2
    else
      # Make sure every link has somewhere to point.
      for target in ${lib.escapeShellArgs (map (t: "${backup}/${t}") (lib.attrValues links))}; do
        run mkdir -p "$target"
      done
      run chmod 700 "${backup}/.ssh"

      for name in ${lib.escapeShellArgs replaced}; do
        dir="$HOME/$name"
        [ -d "$dir" ] && [ ! -L "$dir" ] || continue
        target="${backup}/$name"
        if [ -n "$(ls -A "$dir")" ]; then
          echo "links.nix: moving contents of $dir into $target" >&2
          run ${pkgs.coreutils}/bin/mv -n "$dir"/* "$dir"/.[!.]* "$target"/ 2>/dev/null || true
          if [ -n "$(ls -A "$dir")" ]; then
            echo "links.nix: $dir still has files that also exist in $target; not removing it, sort those out by hand" >&2
            continue
          fi
        fi
        echo "links.nix: removing $dir" >&2
        run ${pkgs.coreutils}/bin/rm -rf "$dir"
      done
    fi
  '';
}
