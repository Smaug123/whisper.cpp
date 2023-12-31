{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    model = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin?download=true";
      flake = false;
    };
  };

  outputs = inputs @ {
    self,
    flake-utils,
    nixpkgs,
    model,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages = {
        normalize = pkgs.stdenvNoCC.mkDerivation {
          name = "normalize.sh";
          src = ./normalize;
          nativeBuildInputs = [pkgs.ffmpeg];
          buildInputs = [pkgs.makeWrapper];
          doConfigure = false;
          doBuild = false;
          doCheck = false;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp ./normalize.sh $out/bin/
            chmod a+x $out/bin/normalize.sh
            wrapProgram $out/bin/normalize.sh --set FFMPEG "${pkgs.ffmpeg}/bin/ffmpeg"
            runHook postInstall
          '';
        };
        default = with pkgs;
        stdenv.mkDerivation rec {
          name = "whisper-cpp";
          src = ./.;
          nativeBuildInputs = [pkgs.makeWrapper];
          buildInputs = [pkgs.SDL2] ++ lib.optionals stdenv.isDarwin [pkgs.darwin.apple_sdk.frameworks.Accelerate pkgs.darwin.apple_sdk.frameworks.CoreGraphics pkgs.darwin.apple_sdk.frameworks.CoreVideo pkgs.darwin.apple_sdk.frameworks.MetalKit];

          makeFlags = ["main" "stream"];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp ./main $out/bin/whisper-cpp-bin
            echo '#!/bin/sh' > $out/bin/whisper-cpp
            echo "$out"'/bin/whisper-cpp-bin --model ${model} "$@"' >> $out/bin/whisper-cpp
            chmod a+x $out/bin/whisper-cpp
            cp ./stream $out/bin/whisper-cpp-stream
            cp models/download-ggml-model.sh $out/bin/whisper-cpp-download-ggml-model
            wrapProgram $out/bin/whisper-cpp-download-ggml-model \
              --prefix PATH : ${lib.makeBinPath [wget]}
            runHook postInstall
          '';

          meta = with lib; {
            description = "Port of OpenAI's Whisper model in C/C++";
            longDescription = ''
              To download the models as described in the project's readme, you may
              use the `whisper-cpp-download-ggml-model` binary from this package.
            '';
            homepage = "https://github.com/ggerganov/whisper.cpp";
            license = licenses.mit;
            platforms = platforms.all;
          };
        };
      };
    });
}
