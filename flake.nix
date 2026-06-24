{
  description = "minimalbase + slskd service";
  inputs = {
    # slskd is built from nixpkgs (pkgs.slskd) — NOT pinned in this repo.
    # nixpkgs is its own input (not `follows`) so update-flake-lock can bump it,
    # which is what advances slskd to the latest packaged release. nixpkgs builds
    # it properly (buildDotnetModule + bundled React frontend), avoiding the
    # single-file self-contained problem of the upstream release zips.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    minimalbase.url = "github:nonrootdocker/minimalbase";
  };
  outputs = { self, nixpkgs, minimalbase }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # slskd, straight from nixpkgs (.NET backend + bundled frontend). No pin here.
    slskd = pkgs.slskd;

    # ----------------------------
    # User database configuration (/etc/passwd)
    # ----------------------------
    passwdFile = pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      slskd:x:1000:1000:slskd:/data:/bin/sh
    '';

    # ----------------------------
    # ABI descriptor for container-init
    # ----------------------------
    slskdAbi = pkgs.writeTextFile {
      name = "slskd-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          exec = "${slskd}/bin/slskd";
          args = [ ];
        };
      };
      destination = "/app/main";
    };

  in {
    packages.${system} = {
      default = self.packages.${system}.slskd-image;
      # Authoritative version from nixpkgs' slskd; exposed for CI tagging.
      version = pkgs.writeText "slskd-version" slskd.version;
      slskd-image = pkgs.dockerTools.buildImage {
        name = "slskd";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;
        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            slskd
            slskdAbi
            passwdFile
          ];
        };
        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];
          User = "1000:1000";
          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
            "SLSKD_APP_DIR=/data"
            "SLSKD_HTTP_PORT=5030"
            "SLSKD_HTTPS_PORT=5031"
            "SLSKD_SLSK_LISTEN_PORT=50300"
          ];
        };
      };
    };
  };
}
