{ lib
, stdenv
, makeWrapper
, python3
, qt5
, qt6
, acpi
, adw-gtk3
, alsa-utils
, bc
, bluez
, brightnessctl
, ddcutil
, cava
, cliphist
, easyeffects
, fastfetch
, fd
, ffmpeg
, file
, gpu-screen-recorder
, grim
, imagemagick
, inotify-tools
, iw
, jq
, kitty
, libnotify
, lm_sensors
, matugen
, nautilus
, networkmanager
, pamixer
, pavucontrol
, pciutils
, playerctl
, power-profiles-daemon
, psmisc
, ripgrep
, satty
, slurp
, socat
, util-linux
, wf-recorder
, wget
, wireplumber
, wl-clipboard
, wl-gammarelay-rs
, wmctrl
, xdg-desktop-portal-gtk
, zbar
, quickshell
, libpulseaudio
, pipewire
, rev ? "dirty"
}:
let
  pname = "serpantinum";
  version = lib.strings.trim (builtins.readFile ../version.txt);
  pythonEnv = python3.withPackages (ps: [ ps.websockets ]);
  pathDeps = [
    acpi
    alsa-utils
    bc
    bluez
    brightnessctl
    ddcutil
    cava
    cliphist
    easyeffects
    fastfetch
    fd
    ffmpeg
    file
    gpu-screen-recorder
    grim
    imagemagick
    inotify-tools
    iw
    jq
    kitty
    libnotify
    lm_sensors
    matugen
    nautilus
    networkmanager
    pamixer
    pavucontrol
    pciutils
    playerctl
    power-profiles-daemon
    psmisc
    pythonEnv
    ripgrep
    satty
    slurp
    socat
    util-linux
    wf-recorder
    wget
    wireplumber
    wl-clipboard
    wl-gammarelay-rs
    wmctrl
    xdg-desktop-portal-gtk
    zbar
    quickshell		
  ];
  qtDeps = [
    quickshell
    qt6.qtwayland
    qt6.qtmultimedia
    qt6.qt5compat
    qt6.qtwebsockets
  ];
  qmlImportPath = lib.concatMapStringsSep ":" (pkg: "${pkg}/lib/qt-6/qml") qtDeps;
  qtPluginPath = lib.concatMapStringsSep ":" (pkg: "${pkg}/lib/qt-6/plugins") qtDeps;
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname version;
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions (
      map (p: ../. + "/${p}") [ "bin" "src" "config" "compositors" "version.txt" ]
    );
  };
  nativeBuildInputs = [ makeWrapper qt6.wrapQtAppsHook ];
  buildInputs = qtDeps ++ [ libpulseaudio pipewire ];
  dontConfigure = true;
  dontBuild = true;
  dontWrapQtApps = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/${finalAttrs.pname}"
    cp -r src/. "$out/share/${finalAttrs.pname}/"
    cp -r config "$out/share/${finalAttrs.pname}/config"
    find "$out/share/${finalAttrs.pname}" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
    install -Dm755 bin/serpantinum  "$out/bin/.serpantinum-wrapped"
    install -Dm755 bin/serpantinumd "$out/bin/.serpantinumd-wrapped"
    runHook postInstall
  '';
  postFixup = ''
    for bin in serpantinum serpantinumd; do
      makeWrapper "$out/bin/.$bin-wrapped" "$out/bin/$bin" \
        "''${qtWrapperArgs[@]}" \
        --prefix QML2_IMPORT_PATH : "${qmlImportPath}" \
        --prefix QT_PLUGIN_PATH : "${qtPluginPath}" \
        --set SERPANTINUM_DIR "$out/share/${finalAttrs.pname}" \
        --set SERPANTINUM_VERSION "${finalAttrs.version}" \
        --set SERPANTINUM_REV "${rev}" \
        --prefix PATH : "${lib.makeBinPath pathDeps}"
    done
  '';
  passthru = { inherit pathDeps qtDeps pythonEnv; };
  meta = with lib; {
    description = "A desktop shell built for YOU";
    homepage = "https://github.com/ilyamiro/serpantinum";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "serpantinum";
  };
})
