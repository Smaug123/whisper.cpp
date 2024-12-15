{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    model = {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin?download=true";
      flake = false;
    };
  };

  outputs = {
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
          stdenv.mkDerivation {
            name = "whisper-cpp";
            src = ./.;
            buildInputs = [pkgs.makeWrapper pkgs.cmake pkgs.SDL2 pkgs.llvmPackages.openmp] ++ lib.optionals stdenv.isDarwin [pkgs.darwin.apple_sdk.frameworks.Accelerate pkgs.darwin.apple_sdk.frameworks.CoreGraphics pkgs.darwin.apple_sdk.frameworks.CoreVideo pkgs.darwin.apple_sdk.frameworks.MetalKit];

            configurePhase = ''
              runHook preConfigure
              cmake -B build
              runHook postConfigure
            '';

            cmakeFlags = [
              "-DCMAKE_BUILD_TYPE=Release"
              "-DBUILD_SHARED_LIBS=ON"
              "-DCMAKE_SKIP_BUILD_RPATH=OFF"
              "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"
              "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
              "-DCMAKE_INSTALL_RPATH=${placeholder "out"}/lib"
              "-DWHISPER_BUILD_SHARED=ON" # Explicitly request shared libraries
              "-DGGML_BUILD_SHARED=ON" # Explicitly request shared GGML library
            ];

            buildPhase = ''
              runHook preBuild
              cmake --build build --config Release
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/{bin,lib}

              # Copy whisper library
              cp ./build/src/libwhisper*.dylib $out/lib/

              # Copy all GGML libraries
              cp ./build/ggml/src/libggml*.dylib $out/lib/
              cp ./build/ggml/src/ggml-blas/libggml*.dylib $out/lib/
              cp ./build/ggml/src/ggml-metal/libggml*.dylib $out/lib/

              # Copy binaries
              cp ./build/bin/* $out/bin/
              mv $out/bin/main $out/bin/whisper-cpp-bin

              # Fix the RPATH on macOS for all libraries
              ${lib.optionalString stdenv.isDarwin ''
                install_name_tool -change @rpath/libwhisper.1.dylib $out/lib/libwhisper.1.dylib $out/bin/whisper-cpp-bin
                install_name_tool -change @rpath/libggml.dylib $out/lib/libggml.dylib $out/bin/whisper-cpp-bin
                install_name_tool -change @rpath/libggml-cpu.dylib $out/lib/libggml-cpu.dylib $out/bin/whisper-cpp-bin
                install_name_tool -change @rpath/libggml-blas.dylib $out/lib/libggml-blas.dylib $out/bin/whisper-cpp-bin
                install_name_tool -change @rpath/libggml-metal.dylib $out/lib/libggml-metal.dylib $out/bin/whisper-cpp-bin
                install_name_tool -change @rpath/libggml-base.dylib $out/lib/libggml-base.dylib $out/bin/whisper-cpp-bin
              ''}

              echo '#!/bin/sh' > $out/bin/whisper-cpp
              echo "$out"'/bin/whisper-cpp-bin --model ${model} "$@"' >> $out/bin/whisper-cpp
              chmod a+x $out/bin/whisper-cpp
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
