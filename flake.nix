{
  description = "Flake for development workflows.";

  inputs = {
    rainix.url = "github:rainlanguage/rainix";
    rain.url = "github:rainlanguage/rain.cli";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils, rainix, rain }:
    flake-utils.lib.eachDefaultSystem (system:
      rec {
        packages = rec {
        } // rainix.packages.${system};

        devShells = rainix.devShells.${system};
      });
}
