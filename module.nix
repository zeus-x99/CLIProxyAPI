{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalAttrs
    optionalString
    types
    ;

  cfg = config.services.cliproxyapi;
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
  yamlFormat = pkgs.formats.yaml { };

  scalarValueType = types.oneOf [
    types.bool
    types.float
    types.int
    types.str
  ];

  yamlValueType = types.nullOr (
    types.oneOf [
      scalarValueType
      (types.listOf yamlValueType)
      (types.attrsOf yamlValueType)
    ]
  );

  defaultUser = "cliproxyapi";
  defaultGroup = "cliproxyapi";

  effectiveAuthDir = if cfg.authDir != null then cfg.authDir else "${cfg.stateDir}/auths";
  effectiveWritablePath = if cfg.writablePath != null then cfg.writablePath else cfg.stateDir;

  managedConfigPath = "${cfg.stateDir}/config/config.yaml";
  activeConfigPath = if cfg.configFile != null then cfg.configFile else managedConfigPath;

  reservedSettingNames = [
    "host"
    "port"
    "auth-dir"
    "api-keys"
  ];

  conflictingSettingNames = lib.intersectLists reservedSettingNames (builtins.attrNames cfg.settings);

  generatedConfig = yamlFormat.generate "cliproxyapi-config.yaml" (
    lib.recursiveUpdate
      {
        host = cfg.host;
        port = cfg.port;
        "auth-dir" = effectiveAuthDir;
      }
      cfg.settings
  );

  pathIsEqualOrUnder = prefix: path: path == prefix || lib.hasPrefix "${prefix}/" path;
  homeSensitivePaths = [
    cfg.stateDir
    effectiveWritablePath
  ]
  ++ optional (cfg.configFile != null) cfg.configFile
  ++ optional (cfg.environmentFile != null) cfg.environmentFile
  ++ cfg.apiKeyFiles;
  protectHome =
    !lib.any (
      path:
      builtins.isString path
      && lib.any (prefix: pathIsEqualOrUnder prefix path) [
        "/home"
        "/root"
        "/run/user"
      ]
    ) homeSensitivePaths;
in
{
  options.services.cliproxyapi = {
    enable = mkEnableOption "CLIProxyAPI service";

    package = mkOption {
      type = types.package;
      default = packages.default;
    };

    user = mkOption {
      type = types.str;
      default = defaultUser;
    };

    group = mkOption {
      type = types.str;
      default = defaultGroup;
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/cliproxyapi";
    };

    writablePath = mkOption {
      type = types.nullOr types.str;
      default = null;
      defaultText = literalExpression "config.services.cliproxyapi.stateDir";
      example = literalExpression "/var/lib/cliproxyapi";
      description = ''
        导出给 `WRITABLE_PATH` 的目录。默认跟随 `stateDir`。
      '';
    };

    configFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = literalExpression "/run/secrets/cliproxyapi-config.yaml";
      description = ''
        外部 `config.yaml` 绝对路径。设置后，module 不再生成配置文件。
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = literalExpression "/run/secrets/cliproxyapi.env";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = literalExpression ''
        {
          PGSTORE_DSN = "postgres://user:password@127.0.0.1:5432/cliproxyapi?sslmode=disable";
        }
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--local-model" ];
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        仅在 `configFile = null` 时写入生成配置。
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8317;
      description = ''
        生成配置与防火墙开放端口都使用该值。若使用外部 `configFile`，需要你自己保证二者一致。
      '';
    };

    authDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      defaultText = literalExpression ''"${config.services.cliproxyapi.stateDir}/auths"'';
      description = ''
        仅在 `configFile = null` 时写入生成配置。
      '';
    };

    apiKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "replace-with-a-random-string" ];
      description = ''
        顶层 `api-keys`。仅在 `configFile = null` 时写入生成配置。
      '';
    };

    apiKeyFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "/run/secrets/cliproxyapi-api-key" ];
      description = ''
        运行时从这些文件读取 `api-keys`，适合配合 `sops-nix` 等 secret 管理。
        仅在 `configFile = null` 时生效。
      '';
    };

    allowUnauthenticated = mkOption {
      type = types.bool;
      default = false;
      description = ''
        允许生成一个没有 `api-keys` 的配置。默认关闭，避免意外生成匿名可访问实例。
      '';
    };

    settings = mkOption {
      type = types.attrsOf yamlValueType;
      default = { };
      example = literalExpression ''
        {
          debug = false;
          "remote-management" = {
            "allow-remote" = false;
            "secret-key" = "replace-with-another-random-string";
          };
        }
      '';
      description = ''
        额外写入 `config.yaml` 的配置。不能覆盖 `host`、`port`、`auth-dir`、`api-keys`。
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = conflictingSettingNames == [ ];
        message =
          "services.cliproxyapi.settings 不能覆盖模块保留字段: " + lib.concatStringsSep ", " conflictingSettingNames;
      }
      {
        assertion = lib.hasPrefix "/" cfg.stateDir;
        message = "services.cliproxyapi.stateDir 必须是绝对路径";
      }
      {
        assertion = !lib.hasPrefix "/nix/store" cfg.stateDir;
        message = "services.cliproxyapi.stateDir 不能位于 /nix/store";
      }
      {
        assertion = cfg.writablePath == null || lib.hasPrefix "/" cfg.writablePath;
        message = "services.cliproxyapi.writablePath 必须是绝对路径";
      }
      {
        assertion = cfg.configFile == null || lib.hasPrefix "/" cfg.configFile;
        message = "services.cliproxyapi.configFile 必须是绝对路径";
      }
      {
        assertion = cfg.environmentFile == null || lib.hasPrefix "/" cfg.environmentFile;
        message = "services.cliproxyapi.environmentFile 必须是绝对路径";
      }
      {
        assertion = cfg.authDir == null || lib.hasPrefix "/" cfg.authDir;
        message = "services.cliproxyapi.authDir 必须是绝对路径";
      }
      {
        assertion = lib.all (path: lib.hasPrefix "/" path) cfg.apiKeyFiles;
        message = "services.cliproxyapi.apiKeyFiles 必须全部是绝对路径";
      }
      {
        assertion = cfg.configFile == null || cfg.apiKeyFiles == [ ];
        message = "services.cliproxyapi.configFile 与 services.cliproxyapi.apiKeyFiles 不能同时使用";
      }
      {
        assertion = cfg.configFile != null || cfg.allowUnauthenticated || cfg.apiKeys != [ ] || cfg.apiKeyFiles != [ ];
        message = "services.cliproxyapi.apiKeys/apiKeyFiles 为空；如确实要匿名访问，请显式设置 services.cliproxyapi.allowUnauthenticated = true";
      }
    ];

    users.groups = mkIf (cfg.group == defaultGroup) {
      "${cfg.group}" = { };
    };

    users.users = mkIf (cfg.user == defaultUser) {
      "${cfg.user}" = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        createHome = false;
      };
    };

    systemd.services.cliproxyapi = {
      description = "CLIProxyAPI";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        WRITABLE_PATH = effectiveWritablePath;
      }
      // cfg.extraEnvironment;

      preStart = ''
        install -d -m0750 -o ${cfg.user} -g ${cfg.group} ${lib.escapeShellArg cfg.stateDir}
        install -d -m0750 -o ${cfg.user} -g ${cfg.group} ${lib.escapeShellArg effectiveWritablePath}
      ''
      + optionalString (cfg.configFile == null) ''
        install -d -m0750 -o ${cfg.user} -g ${cfg.group} ${lib.escapeShellArg "${cfg.stateDir}/config"}
        install -d -m0750 -o ${cfg.user} -g ${cfg.group} ${lib.escapeShellArg effectiveAuthDir}
        install -m0640 -o ${cfg.user} -g ${cfg.group} ${generatedConfig} ${lib.escapeShellArg managedConfigPath}
        if [ ${toString (builtins.length cfg.apiKeys + builtins.length cfg.apiKeyFiles)} -gt 0 ]; then
          cat >> ${lib.escapeShellArg managedConfigPath} <<'EOF'
        api-keys:
        EOF
        ${lib.concatMapStrings (key: ''
          printf '  - %s\n' ${lib.escapeShellArg (builtins.toJSON key)} >> ${lib.escapeShellArg managedConfigPath}
        '') cfg.apiKeys}
          for keyFile in ${lib.escapeShellArgs cfg.apiKeyFiles}; do
            key="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$keyFile")"
            escaped="$(printf '%s' "$key" | ${pkgs.gnused}/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
            printf '  - "%s"\n' "$escaped" >> ${lib.escapeShellArg managedConfigPath}
          done
        fi
      '';

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
          WorkingDirectory = "/";
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe cfg.package)
            "--config"
            activeConfigPath
          ]
          ++ cfg.extraArgs
        );
          Restart = "on-failure";
          RestartSec = 5;
          UMask = "0077";
          PrivateTmp = true;
          NoNewPrivileges = true;
          PermissionsStartOnly = true;
          ProtectHome = protectHome;
        }
      // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
