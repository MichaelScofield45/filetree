{
    inputs = {
        nixpkgs = {
            url = "github:nixos/nixpkgs/nixos-unstable";
        };
    };

    outputs = { nixpkgs, ... }: 
    let
        system = "x86_64-linux";
        pkgs = import nixpkgs { inherit system; };
        lib = nixpkgs.lib;
    in
    {
        devShells.${system}.default = pkgs.mkShell {
            buildInputs = with pkgs; [
                xorg.libX11
                xorg.libXcursor
                xorg.libXrandr
                xorg.libXft
                xorg.libXinerama
                xorg.libXi
                libGL
            ];
        };
    };
}
