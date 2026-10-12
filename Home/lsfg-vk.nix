{ config, lib, pkgs, ... }:
let
  # Lossless Scaling frame generation (lsfg-vk 2.x, LSFG 3.1 model) for the
  # games listed below. Generated into ~/.config/lsfg-vk/conf.toml, so edit
  # it here rather than in lsfg-vk-ui (the generated file is read-only).
  #
  # Needs Lossless Scaling on Steam, switched to its "lsfg-vk" branch, which
  # provides lsfg-vk.dll. The layer finds it in the default Steam library;
  # on a machine where Lossless Scaling lives in another library, setup.sh
  # records the path as lsfgDll in hardware.json.
  hw = { laptop = false; lsfgDll = null; }
    // builtins.fromJSON (builtins.readFile ../hardware.json);

  # Laptops get the lighter LSFG 3.1 model and coarser motion vectors.
  defaults = {
    multiplier = 2;
    flow_scale = if hw.laptop then 0.75 else 1.0;
    performance_mode = hw.laptop;
  };

  # One entry per game. active_in takes Linux binary names, Windows .exe
  # names (also under Wine/Proton), process names or Steam app IDs.
  # multiplier 3 or 4 is fine when the real frame rate is steady.
  profiles = [
    {
      name = "Minecraft Bedrock";
      active_in = [ "Minecraft.Windows.exe" ];
    }
  ];

  settings = {
    version = 2;
    global = {
      # The layer's messages; games and launchers often hide stderr.
      log_file = "~/.local/state/lsfg-vk.log";
    } // lib.optionalAttrs (hw.lsfgDll != null) { dll = hw.lsfgDll; };
    profile = map (p: defaults // p) profiles;
  };
in
{
  xdg.configFile."lsfg-vk/conf.toml".source =
    (pkgs.formats.toml { }).generate "lsfg-vk-conf.toml" settings;
}
