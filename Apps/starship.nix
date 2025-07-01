{ config, pkgs, ...}:
let 
in 
{
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      scan_timeout = 10;
      format = "[┌─|$os > $directory$git_branch$fill|$cmd_duration$time|](bold green)\n[└─>](bold green) ";
      os = {
        format = "[$symbol](bold white)";
        disabled = false;
        symbols = {
          NixOS = "";
        };
      };
      fill = {
        symbol = "─";
        style = "bold green";
      };
      time = {
        disabled = false;
        use_12hr = true;
        format = "[$time]($style) [](bold green)";
      };
      cmd_duration = {
        min_time = 0;
        show_milliseconds = false;
        format = "[took](bold purple) [$duration]($style) at ";
      };
    };
  };
}