{
  config,
  lib,
  pkgs,
  ...
}:
let
  script = pkgs.writeScriptBin "nut" ''
    #!${lib.getExe pkgs.bash}
    $(nix flake show --json 2>/dev/null | jq -e .unitTests >/dev/null)
    if [ $? -eq 0 ]; then
      nix eval --raw ".#unitTests.''${system}"
    else
      echo "No tests output attribute found"
    fi
  '';
in
script
