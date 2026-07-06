{ pkgs
, system
, packageVersion
, artifactVersion ? packageVersion
, package
, bundlers
}:

let
  # fpm 1.13.1 is locked through nix-utils and is evaluated with Ruby 3.3
  # here. Ruby 3.3 removed File.exists?, but this fpm version still calls it
  # while assembling DEB/RPM payloads, so preload the compatibility alias only
  # for the fpm-backed package derivations below.
  fpmRuby33Compat = pkgs.writeText "fpm-ruby33-file-exists-compat.rb" ''
    class << File
      alias_method :exists?, :exist? unless method_defined?(:exists?)
      alias_method :cip113_original_write, :write unless method_defined?(:cip113_original_write)

      def write(path, content, *args)
        if path.to_s.end_with?(".spec") && content.include?("%install\n# noop")
          # nix-utils' fpm path generates an RPM spec with a no-op %install
          # section. Current rpmbuild then looks for files under BUILDROOT and
          # the RPM build fails with missing packaged files. Populate buildroot
          # from fpm's BUILD payload while leaving the generated metadata alone.
          content = content.sub("%install\n# noop", <<~'SPEC'.chomp)
    %install
    mkdir -p "%{buildroot}"
    find "%{_topdir}/BUILD" -mindepth 1 -maxdepth 1 ! -name "%{name}-%{version}-build" -exec cp -a '{}' "%{buildroot}/" ';'
    SPEC
        end
        cip113_original_write(path, content, *args)
      end
    end
  '';

  # Keep the Ruby preload scoped to DEB/RPM: AppImage does not go through fpm,
  # so it should not inherit this compatibility shim.
  withFpmRuby33Compat = drv:
    drv.overrideAttrs (old: {
      buildPhase = ''
        export RUBYOPT="${pkgs.lib.optionalString (old ? RUBYOPT) "${old.RUBYOPT} "}-r${fpmRuby33Compat}"
      '' + old.buildPhase;
    });

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

  # fpm packages the derivation's store path directly. Feeding packageWithCa to
  # DEB/RPM preserves the wrapper but also exposes the "-with-ca" symlinkJoin
  # output shape to fpm/rpmbuild. Use a plain package name for fpm while copying
  # the wrapped executable from packageWithCa; the copied wrapper keeps the
  # packageWithCa store reference in its script body, so extraction smoke tests
  # can still find and execute the wrapped "-with-ca" CLI in the closure.
  fpmPackage = pkgs.runCommand "cip113-cli-${packageVersion}" { } ''
    mkdir -p "$out/bin"
    mkdir -p "$out/nix-support"
    cp ${packageWithCa}/bin/cip113-cli "$out/bin/cip113-cli"
    echo ${packageWithCa} > "$out/nix-support/with-ca-path"
  '';

  appImage = bundlers.bundlers.${system}.toAppImage packageWithCa;
  deb = withFpmRuby33Compat (bundlers.bundlers.${system}.toDEB fpmPackage);
  rpm = withFpmRuby33Compat (bundlers.bundlers.${system}.toRPM fpmPackage);
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
