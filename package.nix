{
  lib,
  buildGo126Module,
  version,
  buildDate,
  revision ? null,
}:
buildGo126Module rec {
  pname = "cliproxyapi";
  inherit version;

  src = lib.cleanSource ./.;

  vendorHash = "sha256-qvQO7c/780UWxvM/Lp/KHqcd/pFqzyJx6ILaOeZId7A=";

  subPackages = [ "cmd/server" ];

  doCheck = false;

  env = {
    CGO_ENABLED = 0;
  };

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=v${version}"
    "-X main.Commit=${if revision != null then revision else "unknown"}"
    "-X main.BuildDate=${buildDate}"
  ];

  postInstall = ''
    mv "$out/bin/server" "$out/bin/CLIProxyAPI"
    install -Dm644 config.example.yaml "$out/share/cliproxyapi/config.example.yaml"
    install -Dm644 README.md "$out/share/doc/cliproxyapi/README.md"
  '';

  meta = {
    description = "OpenAI/Gemini/Claude/Codex compatible API proxy server for CLI tools";
    homepage = "https://github.com/zeus-x99/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "CLIProxyAPI";
    platforms = lib.platforms.linux;
  };
}
