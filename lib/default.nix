{
  lib,
  inputs,
  ...
}:
final: prev: {
  enabled = {
    enable = true;
  };
  disabled = {
    enable = false;
  };

  test = import ./test.nix { inherit lib; };
}
