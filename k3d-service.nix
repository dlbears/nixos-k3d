{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.k3d;
in {
  options.services.k3d = {
    enable = mkEnableOption "k3d service";
    clusters = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          servers = mkOption {
            type = types.int;
            default = 1;
            description = "Number of server nodes";
          };
          agents = mkOption {
            type = types.int;
            default = 0;
            description = "Number of agent nodes";
          };
        };
      });
      default = {};
      description = "k3d cluster configurations";
    };
  };

  config = mkIf cfg.enable {
    systemd.services = mapAttrs' (clusterName: clusterConfig:
      nameValuePair "k3d-${clusterName}" {
        description = "k3d cluster ${clusterName}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "docker.service" ];
        restartIfChanged = true;
        # after should usually include
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = ''
            ${pkgs.stdenv.shell} -c 'mkdir -p /etc/kubernetes'
           '';
          ExecStart = ''
            ${pkgs.k3d}/bin/k3d cluster create ${clusterName} \
              --servers ${toString clusterConfig.servers} \
              --agents ${toString clusterConfig.agents} \
              --wait
          '';
          ExecStop = ''
            ${pkgs.stdenv.shell} -c '${pkgs.k3d}/bin/k3d cluster delete ${clusterName}'
          '';
          ExecStartPost = ''
            ${pkgs.stdenv.shell} -c '${pkgs.k3d}/bin/k3d kubeconfig get ${clusterName} > /etc/kubernetes/${clusterName}-kubeconfig.yaml'
             ${pkgs.stdenv.shell} -c 'chmod 644 /etc/kubernetes/${clusterName}-kubeconfig.yaml'
          '';
        };
      }
    ) cfg.clusters;

    environment.variables = mapAttrs' (clusterName: _:
        nameValuePair "KUBECONFIG" "/etc/kubernetes/${clusterName}-kubeconfig.yaml"
    ) cfg.clusters;
  };
}
