#!/bin/bash
# grafana-agent-debug.sh

NAMESPACE="monitoring"
AGENT_POD=$(kubectl get pods -n $NAMESPACE -l app=grafana-agent -o jsonpath='{.items[0].metadata.name}')

echo "=== Grafana Agent Pod: $AGENT_POD ==="
echo ""

echo "=== 1. Agent 로그 (최근 50줄) ==="
kubectl logs -n $NAMESPACE $AGENT_POD --tail=50
echo ""

echo "=== 2. Positions 파일 ==="
kubectl exec -n $NAMESPACE $AGENT_POD -- cat /var/lib/grafana-agent/positions.yaml 2>/dev/null || echo "positions 파일 없음"
echo ""

echo "=== 3. /var/log/pods 디렉토리 확인 ==="
kubectl exec -n $NAMESPACE $AGENT_POD -- ls -la /var/log/pods/ | head -20
echo ""

echo "=== 4. scv 네임스페이스 Pod 로그 파일 ==="
kubectl exec -n $NAMESPACE $AGENT_POD -- find /var/log/pods -path "*scv*" -name "*.log" | head -10
echo ""

echo "=== 5. 메트릭 확인 ==="
kubectl exec -n $NAMESPACE $AGENT_POD -- wget -qO- http://localhost:12345/metrics 2>/dev/null | grep -E "(loki_process|promtail_sent|promtail_dropped)" || echo "메트릭 수집 실패"
