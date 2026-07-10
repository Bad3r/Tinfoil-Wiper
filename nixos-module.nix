{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.tinfoil-wiper;
in
{
  options.programs.tinfoil-wiper = {
    enable = lib.mkEnableOption "Tinfoil Wiper secure erase utility";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "inputs.tinfoil-wiper.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The Tinfoil Wiper package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
