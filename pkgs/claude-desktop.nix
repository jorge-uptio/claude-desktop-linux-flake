{
  lib,
  stdenvNoCC,
  fetchurl,
  electron,
  p7zip,
  icoutils,
  nodePackages,
  imagemagick,
  makeDesktopItem,
  makeWrapper,
  patchy-cnb,
}: let
  pname = "claude-desktop";
  version = "0.8.0";
  srcExe = fetchurl {
    # NOTE: `?v=0.8.0` doesn't actually request a specific version. It's only being used here as a cache buster.
    url = "https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe?v=0.8.0";
    hash = "sha256-nDUIeLPWp1ScyfoLjvMhG79TolnkI8hedF1FVIaPhPw=";
  };
in
  stdenvNoCC.mkDerivation rec {
    inherit pname version;

    src = ./.;

    nativeBuildInputs = [
      p7zip
      nodePackages.asar
      makeWrapper
      imagemagick
      icoutils
    ];

    desktopItem = makeDesktopItem {
      name = "claude-desktop";
      exec = "claude-desktop %u";
      icon = "claude-desktop";
      type = "Application";
      terminal = false;
      desktopName = "Claude";
      genericName = "Claude Desktop";
      categories = [
        "Office"
        "Utility"
      ];
      mimeTypes = ["x-scheme-handler/claude"];
    };

    buildPhase = ''
      runHook preBuild

      # Create temp working directory
      mkdir -p $TMPDIR/build
      cd $TMPDIR/build

      # Extract installer exe, and nupkg within it
      7z x -y ${srcExe}
      7z x -y "AnthropicClaude-${version}-full.nupkg"

      # Package the icons from claude.exe
      wrestool -x -t 14 lib/net45/claude.exe -o claude.ico
      icotool -x claude.ico

      for size in 16 24 32 48 64 256; do
        mkdir -p $TMPDIR/build/icons/hicolor/"$size"x"$size"/apps
        install -Dm 644 claude_*"$size"x"$size"x32.png \
          $TMPDIR/build/icons/hicolor/"$size"x"$size"/apps/claude.png
      done

      rm claude.ico

      # Process app.asar files
      # We need to replace claude-native-bindings.node in both the
      # app.asar package and .unpacked directory
      mkdir -p electron-app
      cp "lib/net45/resources/app.asar" electron-app/
      cp -r "lib/net45/resources/app.asar.unpacked" electron-app/

      cd electron-app
      asar extract app.asar app.asar.contents

      # Replace native bindings
      cp ${patchy-cnb}/lib/patchy-cnb.*.node app.asar.contents/node_modules/claude-native/claude-native-binding.node
      cp ${patchy-cnb}/lib/patchy-cnb.*.node app.asar.unpacked/node_modules/claude-native/claude-native-binding.node

      # .vite/build/index.js in the app.asar expects the Tray icons t do be
      # placed inside the app.asar.
      mkdir -p app.asar.contents/resources
      ls ../lib/net45/resources/
      cp ../lib/net45/resources/Tray* app.asar.contents/resources/

      # Copy i18n json files
      mkdir -p app.asar.contents/resources/i18n
      cp ../lib/net45/resources/*.json app.asar.contents/resources/i18n/

      # Repackage app.asar
      asar pack app.asar.contents app.asar

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Electron directory structure
      mkdir -p $out/lib/$pname
      cp -r $TMPDIR/build/electron-app/app.asar $out/lib/$pname/
      cp -r $TMPDIR/build/electron-app/app.asar.unpacked $out/lib/$pname/

      # Install icons
      mkdir -p $out/share/icons
      cp -r $TMPDIR/build/icons/* $out/share/icons

      # Install .desktop file
      mkdir -p $out/share/applications
      install -Dm0644 {${desktopItem},$out}/share/applications/$pname.desktop

      # Copy localization files to Electron's resources directory
      mkdir -p $out/lib/$pname/locales
      
      # Find all localization files and copy them
      cd $TMPDIR/build
      for jsonFile in lib/net45/resources/*.json; do
        basename=$(basename "$jsonFile")
        # Extract locale from filename (assuming format like en-US.json)
        locale=$(echo "$basename" | cut -d'.' -f1)
        if [[ -n "$locale" ]]; then
          cp "$jsonFile" $out/lib/$pname/locales/$basename
        fi
      done
      
      # Create the resources directory and copy the localization file
      # This is needed because the app looks for localization files in specific paths
      mkdir -p $out/lib/$pname/resources
      
      # Copy the file directly instead of using a symlink to avoid broken links
      if [ -f ${electron}/libexec/electron/resources/en-US.json ]; then
        cp -f ${electron}/libexec/electron/resources/en-US.json $out/lib/$pname/resources/
      else
        # Create an empty file as fallback if the source doesn't exist
        echo "{}" > $out/lib/$pname/resources/en-US.json
      fi
      
      # Create a symlink structure in /tmp that mimics the electron resource path
      # The app is hardcoded to look for files in the electron store path
      mkdir -p $out/lib/$pname/electron-shim/libexec/electron/resources
      cp $out/lib/$pname/resources/en-US.json $out/lib/$pname/electron-shim/libexec/electron/resources/

      # Create wrapper
      mkdir -p $out/bin
      # Create a patch script to find the correct electron store path at runtime
      cat > $out/lib/$pname/patch-electron-path.sh <<EOF
#!/bin/sh
# This script patches the claude-desktop app to use the current electron store path
# It's needed because the app hardcodes paths to the electron binary

# Get the current electron store path from the environment
ELECTRON_PATH=\${ELECTRON_OVERRIDE_DIST_PATH:-${electron}/libexec/electron}

# Create the resources directory in the current electron path if it doesn't exist
mkdir -p \$ELECTRON_PATH/resources

# Copy our localization files to the correct location
cp $out/lib/$pname/resources/en-US.json \$ELECTRON_PATH/resources/
EOF
      chmod +x $out/lib/$pname/patch-electron-path.sh

      makeWrapper ${electron}/bin/electron $out/bin/$pname \
        --add-flags "$out/lib/$pname/app.asar" \
        --add-flags "--disable-gpu-vsync" \
        --add-flags "--disable-frame-rate-limit" \
        --add-flags "\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations}" \
        --set ELECTRON_OVERRIDE_DIST_PATH ${electron}/libexec/electron \
        --set ELECTRON_ENABLE_LOGGING 1 \
        --run "$out/lib/$pname/patch-electron-path.sh"

      runHook postInstall
    '';

    dontUnpack = true;
    dontConfigure = true;

    meta = with lib; {
      description = "Claude Desktop for Linux";
      license = licenses.unfree;
      platforms = platforms.unix;
      sourceProvenance = with sourceTypes; [binaryNativeCode];
      mainProgram = pname;
    };
  }
