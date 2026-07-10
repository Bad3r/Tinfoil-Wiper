{
  bashNonInteractive,
  coreutils,
  cryptsetup,
  gawk,
  gnugrep,
  gnused,
  lib,
  makeWrapper,
  nvme-cli,
  shellcheck,
  stdenvNoCC,
  util-linux,
}:

let
  runtimeInputs = [
    coreutils
    cryptsetup
    gnugrep
    gnused
    nvme-cli
    util-linux
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "tinfoil-wiper";
  version = "2.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./LICENSE
      ./README.md
      ./tests
      ./tinfoil_wiper
    ];
  };

  strictDeps = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = runtimeInputs ++ [
    bashNonInteractive
    gawk
    shellcheck
  ];

  postPatch = ''
    patchShebangs tinfoil_wiper
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    bash -n tinfoil_wiper tests/*.sh
    test "$(bash tinfoil_wiper --version)" = "tinfoil_wiper ${finalAttrs.version}"
    bash tests/test_tinfoil_wiper.sh
    bash tests/test_dryrun.sh
    shellcheck tinfoil_wiper tests/*.sh

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 tinfoil_wiper "$out/bin/tinfoil_wiper"
    wrapProgram "$out/bin/tinfoil_wiper" \
      --set PATH ${lib.makeBinPath runtimeInputs}

    install -Dm644 README.md "$out/share/doc/tinfoil-wiper/README.md"
    install -Dm644 LICENSE "$out/share/licenses/tinfoil-wiper/LICENSE"

    runHook postInstall
  '';

  postFixup = ''
    test "$("$out/bin/tinfoil_wiper" --version)" = "tinfoil_wiper ${finalAttrs.version}"
  '';

  passthru = {
    inherit runtimeInputs;
  };

  meta = {
    description = "Securely erase NVMe SSDs using controller-native and software methods";
    homepage = "https://github.com/Bad3r/Tinfoil-Wiper";
    license = lib.licenses.mit;
    mainProgram = "tinfoil_wiper";
    platforms = lib.platforms.linux;
  };
})
