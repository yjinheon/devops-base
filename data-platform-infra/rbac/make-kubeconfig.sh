#!/usr/bin/env bash
# 사용법: ./make-kubeconfig.sh [출력경로]   (admin kubeconfig 컨텍스트에서 실행)
set -euo pipefail

SA=de-user
NS=airflow
OUT=${1:-${SA}.kubeconfig}

SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl -n "$NS" get secret "${SA}-token" -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl -n "$NS" get secret "${SA}-token" -o jsonpath='{.data.token}' | base64 -d)
[[ -n "$CA" && -n "$TOKEN" ]] || { echo "token secret not ready: ${NS}/${SA}-token" >&2; exit 1; }

umask 077
cat > "$OUT" <<KCFG
apiVersion: v1
kind: Config
clusters:
- name: k3s
  cluster:
    server: ${SERVER}
    certificate-authority-data: ${CA}
users:
- name: ${SA}
  user:
    token: ${TOKEN}
contexts:
- name: ${SA}@airflow
  context: {cluster: k3s, user: ${SA}, namespace: airflow}
- name: ${SA}@trino
  context: {cluster: k3s, user: ${SA}, namespace: trino}
current-context: ${SA}@airflow
KCFG
echo "wrote $OUT"
