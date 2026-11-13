# de-user (airflow / trino 전용 계정) Runbook

- 대상 클러스터: k3s `https://121.189.17.250:6443`
- 계정: ServiceAccount `airflow/de-user`
- 권한: `airflow`, `trino` 네임스페이스에 ClusterRole `edit` (RoleBinding으로 한정)
- 다른 네임스페이스, `kubectl get ns`, 노드 등 클러스터 리소스 → Forbidden

## 1. 생성 (admin 컨텍스트)

```bash
kubectl apply -f rbac/de-user.yaml
./rbac/make-kubeconfig.sh ~/.kube/config-de-user
```

## 2. 검증

```bash
SA=system:serviceaccount:airflow:de-user
kubectl auth can-i list pods -n airflow --as=$SA    # yes
kubectl auth can-i list pods -n trino   --as=$SA    # yes
kubectl auth can-i list pods -n default --as=$SA    # no
kubectl auth can-i list namespaces      --as=$SA    # no

# 실제 kubeconfig로
export KUBECONFIG=~/.kube/config-de-user
kubectl get pods                       # airflow
kubectl get pods -n trino              # trino
kubectl get pods -n monitoring         # Forbidden
kubectl get ns                         # Forbidden
unset KUBECONFIG
```

## 3. 사용자 전달

- `config-de-user` 파일 하나만 전달. 파일 안의 token이 곧 비밀번호.
- 1Password / Vault 등 보안 채널로만 전달. Slack, 메일, git 금지.
- 사용자 측:
  ```bash
  mv config-de-user ~/.kube/config-de-user && chmod 600 ~/.kube/config-de-user
  export KUBECONFIG=~/.kube/config-de-user
  kubectl config use-context de-user@trino   # 네임스페이스 전환
  ```
- k9s: 네임스페이스 목록 권한이 없어 `:ns` 화면은 비어 있음. 아래 중 하나로 이동
  - 실행 시 지정: `k9s -n trino` 또는 `k9s --context de-user@trino`
  - k9s 안에서: `:pods trino`
  - favorites 등록 후 숫자키(`0`=airflow, `1`=trino) 전환:
    `~/Library/Application Support/k9s/clusters/k3s/de-user@airflow/config.yaml`
    ```yaml
    namespace:
      active: airflow
      lockFavorites: true
      favorites: [airflow, trino]
    ```
- `-A` (`kgpa`) 는 클러스터 전체 list 권한이 필요해 Forbidden. RBAC로는 "일부 네임스페이스만 -A" 불가 → 루프로 대체:
  `kgpd() { for n in airflow trino; do kubectl get pods -n "$n" --no-headers "$@" | sed "s/^/$n  /"; done; }`

## 4. 권한 변경

- 읽기 전용으로: `de-user.yaml`의 `roleRef.name: edit` → `view` 후 apply
  (`roleRef`는 수정 불가 → `for n in airflow trino; do kubectl -n $n delete rolebinding de-user; done` 후 재apply)
- 네임스페이스 추가: RoleBinding 블록 복사 후 `metadata.namespace`만 변경

## 5. 토큰 회수 / 재발급

Secret 기반 토큰은 만료가 없음. 유출 의심 시:

```bash
kubectl -n airflow delete secret de-user-token     # 즉시 무효화
kubectl apply -f rbac/de-user.yaml                 # 새 토큰 생성
./rbac/make-kubeconfig.sh ~/.kube/config-de-user   # 새 kubeconfig 재전달
```

만료되는 토큰이 필요하면 Secret 대신:
`kubectl -n airflow create token de-user --duration=720h`

## 6. 삭제

```bash
kubectl delete -f rbac/de-user.yaml
rm ~/.kube/config-de-user
```
