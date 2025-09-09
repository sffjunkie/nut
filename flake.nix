{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      test_lib = import ./lib/test.nix { inherit lib inputs; };
      lib = nixpkgs.lib.extend test_lib;

      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.callPackage ./pkgs/nut { inherit lib; };
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/nut";
          meta = {
            description = "Nix Unit Test";
            homepage = "https://github.com/sffjunkie/nut";
            license = lib.licenses.asl20;
          };
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
