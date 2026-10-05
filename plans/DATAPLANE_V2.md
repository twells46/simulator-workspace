# GKE Dataplane V2: disable kube-proxy monitoring

Runbook drafted on 2026-10-01. Apply it **after** the `kipr` cluster (`us-central1-a`, project `kipr-321905`) moves to GKE Dataplane V2; before then it only removes working kube-proxy monitoring.

## Background

On 2026-10-01 the cluster was on `LEGACY_DATAPATH` (GKE 1.35, Regular channel) with kube-proxy on every node and no NetworkPolicy enforcement. Review of `Simulator`, `database`, and `kipr/kipr-yamls` found nothing else that depends on kube-proxy or iptables:

- No NetworkPolicy in these projects. The two existing cluster policies do not select Simulator, database, or Redis pods, but Dataplane V2 will start enforcing them.
- The ingress Service `default/nginx-ingress-nginx-ingress` uses `externalTrafficPolicy: Local`, so client IPs, and the Simulator rate limiter keyed on them, keep working.
- Pods with `hostNetwork` are GKE agents and node-exporter, which work on Dataplane V2.

Dataplane V2 removes kube-proxy, so the `prometheus-stack` kube-proxy target goes down and `KubeProxyDown` fires. [`../patches/kipr-yamls-disable-kube-proxy-monitoring.patch`](../patches/kipr-yamls-disable-kube-proxy-monitoring.patch) sets `kubeProxy.enabled: false` in `observability/prometheus-stack-values.yaml` of `kipr/kipr-yamls`. In `kube-prometheus-stack` 77.13.0, the version deployed, this removes:

- the kube-proxy Service in `kube-system`
- the ServiceMonitor `observability/prometheus-stack-kube-prom-kube-proxy`
- the `kubernetes-system-kube-proxy` rule group, including `KubeProxyDown`
- the Grafana proxy dashboard

## Before the migration

Replacing nodes can break image pulls for the Bitnami `redis-17.3.7` releases in `prod` and `prerelease`, since Bitnami moved most versioned images out of `docker.io/bitnami` in 2025. Check the image still exists:

```sh
kubectl get pods -n prod -l app.kubernetes.io/name=redis \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
docker manifest inspect <image>   # "manifest unknown" means it is gone
```

If it is gone, point the chart at `docker.io/bitnamilegacy/redis` or another Redis image before nodes are replaced.

## Confirm Dataplane V2 is active

```sh
gcloud container clusters describe kipr --zone us-central1-a --project kipr-321905 \
  --format="value(networkConfig.datapathProvider)"   # expect ADVANCED_DATAPATH
kubectl get pods -n kube-system | grep -E 'anetd|kube-proxy'   # expect anetd, no kube-proxy
```

## Commit the change to kipr-yamls

From the workspace directory:

```sh
gh repo clone kipr/kipr-yamls
cd kipr-yamls
git switch -c disable-kube-proxy-monitoring
git am ../simulator-workspace/patches/kipr-yamls-disable-kube-proxy-monitoring.patch
git push -u origin disable-kube-proxy-monitoring
gh pr create --fill
```

Merge it, then deploy from the updated `main`.

## Apply

On the host, from the `kipr-yamls` checkout, with the cluster's `kubectl` context.

1. Compare the deployed values with the file. `helm upgrade --values` replaces the release's current values, so anything set another way would be dropped:

   ```sh
   helm get values prometheus-stack -n observability -o yaml
   ```

   It should show only `prometheus.prometheusSpec.storageSpec`. Add anything else to `observability/prometheus-stack-values.yaml` first.

2. Note the current revision; the rollback returns to it. It was 2 on 2026-10-01.

   ```sh
   helm history prometheus-stack -n observability
   ```

3. Upgrade, pinned to the deployed chart version so the chart itself is not upgraded:

   ```sh
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
     --namespace observability \
     --version 77.13.0 \
     --values observability/prometheus-stack-values.yaml
   ```

   Add `--dry-run=server` to preview it first, or use `helm diff upgrade` with the same arguments if the `helm-diff` plugin is installed.

4. Verify. Each command should print nothing:

   ```sh
   kubectl get servicemonitor -n observability | grep kube-proxy
   kubectl get prometheusrule -n observability | grep kube-proxy
   kubectl get svc -n kube-system | grep kube-prom-kube-proxy
   ```

   In Prometheus (`kubectl port-forward -n observability svc/prometheus-stack-kube-prom-prometheus 9090:9090`, then `http://localhost:9090/targets`), the kube-proxy target is gone and `KubeProxyDown` has cleared.

## Roll back

Return to the revision noted before the upgrade:

```sh
helm rollback prometheus-stack <previous revision> -n observability
```

This restores the Service, ServiceMonitor, rules, and dashboard. Once Dataplane V2 is live it also brings back the failing `KubeProxyDown` alert, so roll back only if the upgrade itself goes wrong.

If the change should not stay, revert it in `kipr-yamls` too (`git revert <commit>` on `main`); otherwise the next upgrade from `main` disables kube-proxy monitoring again.
