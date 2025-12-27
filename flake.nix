{
  description = "Jekyll blog development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ruby = pkgs.ruby_3_3;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            ruby
            pkgs.bundler
            pkgs.pkg-config
            pkgs.libffi
            pkgs.zlib
            pkgs.libyaml
            pkgs.openssl
          ];

          shellHook = ''
            # Ensure Nix ruby comes before rbenv shims
            export PATH="${ruby}/bin:$PWD/.gems/bin:$PATH"
            export GEM_HOME="$PWD/.gems"
            export BUNDLE_PATH="$GEM_HOME"

            # Disable rbenv in this shell
            unset RBENV_VERSION

            if [ ! -d "$GEM_HOME" ]; then
              echo "Installing gems..."
              bundle install
            fi

            echo "Jekyll development environment ready!"
            echo "Commands:"
            echo "  bundle exec jekyll serve    - Start local server"
            echo "  bundle exec jekyll build    - Build the site"
          '';
        };

        packages.default = pkgs.writeShellScriptBin "jekyll-serve" ''
          export GEM_HOME="$PWD/.gems"
          export PATH="$GEM_HOME/bin:$PATH"
          export BUNDLE_PATH="$GEM_HOME"
          ${pkgs.bundler}/bin/bundle exec jekyll serve --livereload
        '';
      }
    );
}
