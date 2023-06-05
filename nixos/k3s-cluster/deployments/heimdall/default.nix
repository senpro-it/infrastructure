{ config, pkgs, lib, ... }:

with lib;

{
  options = {
    senpro-it = {
      k3s-cluster = {
        deployments = {
          heimdall = {
            enable = mkEnableOption ''
              Whether to deploy heimdall on the k3s cluster.
            '';
            hostName = mkOption {
              type = types.str;
              description = lib.mdDoc ''
                Hostname to use for heimdall. It should be FQDN.
              '';
              example = "heimdall.local";
            };
          };
        };
      };
    };
  };
  config = (lib.mkIf config.senpro-it.k3s-cluster.deployments.heimdall.enable {
    systemd.services = {
      k3s-deployments-heimdall-provisioner = {
        enable = true;
        description = "Provisioner for k3s heimdall deployment.";
        restartIfChanged = true;
        preStart = ''
          ${pkgs.coreutils-full}/bin/printf "%s\n" \
            "apiVersion: v1" \
            "kind: Namespace" \
            "metadata:" \
            "  name: heimdall" \
            "---" \
            "apiVersion: v1" \
            "kind: PersistentVolumeClaim" \
            "" \
            "metadata:" \
            "  name: heimdall" \
            "  namespace: heimdall" \
            "spec:" \
            "  storageClassName: nfs-csi" \
            "  accessModes:" \
            "  - ReadWriteMany" \
            "  resources:" \
            "    requests:" \
            "      storage: 1G" \
            "---" \
            "apiVersion: apps/v1" \
            "kind: Deployment" \
            "" \
            "metadata:" \
            "  name: heimdall" \
            "  namespace: heimdall" \
            "  labels:" \
            "    app: heimdall" \
            "" \
            "spec:" \
            "  replicas: 1" \
            "  selector:" \
            "    matchLabels:" \
            "      app: heimdall" \
            "  strategy:" \
            "    rollingUpdate:" \
            "      maxSurge: 0" \
            "      maxUnavailable: 1" \
            "    type: RollingUpdate" \
            "  template:" \
            "    metadata:" \
            "      labels:" \
            "        app: heimdall" \
            "    spec:" \
            "      volumes:" \
            "      - name: heimdall" \
            "        persistentVolumeClaim:" \
            "          claimName: heimdall" \
            "      containers:" \
            "      - image: ghcr.io/linuxserver/heimdall:2.5.6" \
            "        name: heimdall" \
            "        imagePullPolicy: Always" \
            "        env:" \
            "          - name: PGID" \
            "            value: \"1000"\" \
            "          - name: PUID" \
            "            value: \"1000"\" \
            "          - name: TZ" \
            "            value: \"Europe/Berlin\"" \
            "        ports:" \
            "        - containerPort: 80" \
            "          name: web" \
            "          protocol: TCP" \
            "        volumeMounts:" \
            "        - mountPath: /config" \
            "          name: heimdall" \
            "---" \
            "apiVersion: v1" \
            "kind: Service" \
            "metadata:" \
            "  name: heimdall" \
            "  namespace: heimdall" \
            "spec:" \
            "  type: ClusterIP" \
            "  ports:" \
            "    - port: 80" \
            "      targetPort: 80" \
            "  selector:" \
            "    app: heimdall" \
            "---" \
            "apiVersion: traefik.containo.us/v1alpha1" \
            "kind: IngressRoute" \
            "metadata:" \
            "  name: heimdall" \
            "  namespace: heimdall" \
            "spec:" \
            "  entryPoints:" \
            "    - websecure" \
            "  routes:" \
            "    - kind: Rule" \
            "      match: Host(\`${config.senpro-it.k3s-cluster.deployments.heimdall.hostName}\`)" \
            "      services:" \
            "        - name: heimdall" \
            "          port: 80" > /var/lib/rancher/k3s/server/manifests/deployments-heimdall.yaml
        '';
        postStop = ''
          ${pkgs.coreutils-full}/bin/rm -f /var/lib/rancher/k3s/server/manifests/deployments-heimdall.yaml
        '';
        serviceConfig = { ExecStart = ''${pkgs.bashInteractive}/bin/bash -c "while true; do echo 'k3s-deployments-heimdall-provisioner is up & running'; sleep 1d; done"''; };
      };
    };
  });
}
