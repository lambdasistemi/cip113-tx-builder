{ pkgs
, system
, packageVersion
, artifactVersion ? packageVersion
, package
, bundlers
}:

let
  packageWithCa = pkgs.symlinkJoin {
    name = "cip113-cli-${packageVersion}-with-ca";
    paths = [ package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for prog in $out/bin/*; do
        if [ -L "$prog" ]; then
          target=$(readlink -f "$prog")
          rm "$prog"
          makeWrapper "$target" "$prog" \
            --set-default SSL_CERT_FILE \
              ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
            --set-default SYSTEM_CERTIFICATE_PATH \
              ${pkgs.cacert}/etc/ssl/certs
        fi
      done
    '';
  };

  appImage = bundlers.bundlers.${system}.toAppImage packageWithCa;
  deb = bundlers.bundlers.${system}.toDEB packageWithCa;
  rpm = bundlers.bundlers.${system}.toRPM packageWithCa;
in
pkgs.runCommand
  "cip113-cli-${artifactVersion}-${system}-artifacts"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.findutils ];
    passthru = {
      inherit appImage deb rpm packageWithCa;
    };
  } ''
  mkdir -p "$out"

  cp -L ${appImage} "$out/cip113-cli-${artifactVersion}-${system}.AppImage"
  cp -L ${appImage} "$out/cip113-cli.AppImage"

  deb_file="$(find ${deb} -maxdepth 1 -type f -name '*.deb' | head -1)"
  rpm_file="$(find ${rpm} -maxdepth 1 -type f -name '*.rpm' | head -1)"

  test -n "$deb_file"
  test -n "$rpm_file"

  cp "$deb_file" "$out/cip113-cli-${artifactVersion}-${system}.deb"
  cp "$rpm_file" "$out/cip113-cli-${artifactVersion}-${system}.rpm"

  (cd "$out" && sha256sum * > SHA256SUMS)
''
