{ lib, python3Packages, qt6 }:

python3Packages.buildPythonApplication {
  pname = "nixos-updater";
  version = "1.0";
  format = "other";
  src = ./.;

  nativeBuildInputs = [ qt6.wrapQtAppsHook ];
  buildInputs = [ qt6.qtbase ];
  propagatedBuildInputs = [ python3Packages.pyqt6 ];

  # The Python wrapper gets the Qt environment instead of a second wrapper.
  dontWrapQtApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${qtWrapperArgs[@]}")
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 nixos_updater.py $out/bin/nixos-updater
    install -Dm755 nixos-updater-helper $out/libexec/nixos-updater-helper
    install -Dm644 nixos-updater.desktop $out/share/applications/nixos-updater.desktop
    install -Dm644 nixos-updater.svg $out/share/icons/hicolor/scalable/apps/nixos-updater.svg
    mkdir -p $out/share/polkit-1/actions
    substitute org.nixos.updater.policy.in $out/share/polkit-1/actions/org.nixos.updater.policy \
      --replace-fail @helper@ $out/libexec/nixos-updater-helper
    runHook postInstall
  '';

  meta = {
    description = "Update this NixOS machine from its flake and keep the Flatpak config in sync";
    mainProgram = "nixos-updater";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
