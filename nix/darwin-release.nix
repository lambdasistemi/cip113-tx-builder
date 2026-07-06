{ inputs
, pkgs
, packageVersion
, artifactVersion ? packageVersion
, package
, releaseTag ? "v${packageVersion}"
, formulaName ? "cip113-cli"
, formulaClass ? "Cip113Cli"
, formulaVersion ? artifactVersion
, formulaExtraLines ? ""
}:

let
  mkDarwinHomebrewBundle =
    inputs.dev-assets.lib.mkDarwinHomebrewBundle { inherit pkgs; };
in
mkDarwinHomebrewBundle {
  pname = "cip113-cli";
  version = packageVersion;
  inherit artifactVersion releaseTag;
  owner = "lambdasistemi";
  repo = "cip113-tx-builder";
  desc = "Build CIP-113 programmable token transactions";
  homepage = "https://github.com/lambdasistemi/cip113-tx-builder";
  inherit formulaName formulaClass formulaVersion formulaExtraLines;
  executables = {
    cip113-cli = package;
  };
  executableNames = [ "cip113-cli" ];
  formulaTest = ''
    system "#{bin}/cip113-cli", "--help"
  '';
  smokeCommands = [ "cip113-cli --help >/dev/null" ];
}
