#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
사용법: k-last-applied.sh [옵션]

옵션:
  -K, --any-kind          리소스 타입을 fzf로 먼저 선택 (기본: services)
  -k, --kind KIND         특정 리소스 타입 지정 (예: services, deployments.apps, configmaps, pods 등)
  -A, --all-namespaces    모든 네임스페이스에서 검색 (기본)
  -n, --namespace NAMESPACE 특정 네임스페이스에서만 검색
  -o, --out FILE          결과 YAML을 파일로 저장 (기본: stdout)
  -h, --help              도움말
  k-last-applied.sh

  # 네임스페이스 kube-system 안의 서비스만 대상으로
  k-last-applied.sh -n kube-system

  # 리소스 종류부터 고르고 선택 (deployments.apps, ingresses 등도 가능)
  k-last-applied.sh --any-kind

  # 출력물을 파일로 저장
  k-last-applied.sh -o last-applied.yaml
USAGE
}

# 필수 커맨드 체크
need_cmds=(kubectl jq fzf yq)
missing=()
for c in "${need_cmds[@]}"; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "필수 도구 미설치: ${missing[*]}" >&2
  echo "설치 후 다시 실행하세요. (yq는 mikefarah/yq v4 권장)" >&2
  exit 1
fi

RESOURCE="services" # 기본 리소스
NS_ARGS=(-A)        # 기본: 모든 네임스페이스
OUT_FILE=""

# 인자 파싱
ANY_KIND=false
while [[ $# -gt 0 ]]; do
  case "$1" in
  -K | --any-kind)
    ANY_KIND=true
    shift
    ;;
  -k | --kind)
    RESOURCE="$2"
    shift 2
    ;;
  -A | --all-namespaces)
    NS_ARGS=(-A)
    shift
    ;;
  -n | --namespace)
    NS_ARGS=(-n "$2")
    shift 2
    ;;
  -o | --out)
    OUT_FILE="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "알 수 없는 옵션: $1" >&2
    usage
    exit 1
    ;;
  esac
done

# 리소스 타입을 먼저 고르고 싶다면
if $ANY_KIND; then
  # list 가능한 네임스페이스 리소스만 표시
  RESOURCE="$(kubectl api-resources --verbs=list --namespaced -o name |
    sort |
    fzf --prompt='리소스 타입 선택 > ' --height=60% --reverse \
      --border --header='예: services, deployments.apps, configmaps, ingresses.networking.k8s.io 등')"
  [[ -z "$RESOURCE" ]] && {
    echo "취소됨."
    exit 1
  }
fi

# 대상 리소스 목록 가져오기
# 출력 형식: <resource>\t<namespace>\t<name>\t<has_last_applied>
list_json="$(kubectl get "$RESOURCE" "${NS_ARGS[@]}" -o json 2>/dev/null || true)"

if [[ -z "$list_json" || "$list_json" == "null" ]]; then
  echo "리소스 조회 실패 또는 없음: $RESOURCE" >&2
  exit 1
fi

lines="$(
  jq -r --arg res "$RESOURCE" '
    .items[]? |
    [
      $res,
      (.metadata.namespace // "default"),
      .metadata.name,
      (if .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"] then "✓" else "✗" end)
    ] | @tsv
  ' <<<"$list_json"
)"

if [[ -z "$lines" ]]; then
  echo "표시할 항목이 없습니다. (리소스: $RESOURCE)" >&2
  exit 1
fi

# fzf로 리소스 선택 (미리보기에서 last-applied를 YAML로 보여줌)
# 필드: 1=resource 2=namespace 3=name 4=mark
selected="$(
  printf '%s\n' "$lines" |
    fzf \
      --prompt="리소스 선택 > " \
      --height=85% --reverse --border \
      --delimiter='\t' \
      --with-nth=2,3,4 \
      --header=$'표시: <NAMESPACE>\t<NAME>\t<LAST-APPLIED 유무(✓/✗)>\nEnter: 선택 / 오른쪽 미리보기' \
      --preview='
        RES=$(echo {} | awk -F"\t" "{print \$1}")
        NS=$(echo {}  | awk -F"\t" "{print \$2}")
        NAME=$(echo {}| awk -F"\t" "{print \$3}")

        # annotation 값(JSON 문자열)을 뽑아서 YAML로 변환
        kubectl get "$RES" "$NAME" -n "$NS" -o json 2>/dev/null \
        | jq -er ".metadata.annotations[\"kubectl.kubernetes.io/last-applied-configuration\"]" 2>/dev/null \
        | yq -p json -o yaml 2>/dev/null \
        || echo "⚠️ last-applied-configuration 없음 또는 변환 실패"
      ' \
      --preview-window=right:70%
)"

[[ -z "$selected" ]] && {
  echo "취소됨."
  exit 0
}

RES=$(awk -F'\t' '{print $1}' <<<"$selected")
NS=$(awk -F'\t' '{print $2}' <<<"$selected")
NAME=$(awk -F'\t' '{print $3}' <<<"$selected")

# 실제 last-applied YAML 출력
raw_json="$(
  kubectl get "$RES" "$NAME" -n "$NS" -o json |
    jq -er '.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]' ||
    true
)"

if [[ -z "$raw_json" ]]; then
  echo "⚠️ 선택한 리소스에 last-applied-configuration 주석이 없습니다."
  exit 2
fi

if [[ -n "$OUT_FILE" ]]; then
  echo "$raw_json" | yq -p json -o yaml >"$OUT_FILE"
  echo "✅ 저장됨: $OUT_FILE"
else
  echo "$raw_json" | yq -p json -o yaml
fi
