{
  description = "Fullstack Development Environment";
  
  # ツール(パッケージ)の仕入れ先
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # システムの定義
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # 一部オープンソースではない（ライセンス制限がある）ツールの使用を許可
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        # ツール(パッケージ)の種類
        buildInputs = with pkgs; [
          awscli2
          nodejs_22
          docker-compose
        ];

        shellHook = ''

        '';
      };
    };
}
