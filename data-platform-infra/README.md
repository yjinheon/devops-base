# data-platform-infra

k3s 기반 데이터 플랫폼 아키텍처 다이어그램.

> 설계 리뷰(개선·효율화, 우선순위, to-be): [`design_review.md`](design_review.md)

## 면접용 HTML (diagram-design, 브라우저로 열기)

| 파일 | 내용 |
|---|---|
| `html/01_platform_overview.html` | 전체 개요: 소스 → 코어 → 소비처, ClickHouse 수렴 SPOF |
| `html/02_deployment.html` | 배포 토폴로지: 호스트별 워크로드, control-plane SPOF, CDH 동거 |
| `html/03_medallion.html` | 배치: bronze → silver → gold → ClickHouse publish (A/B/C) |
| `html/04_realtime.html` | 실시간: Tracking · CDC → Kafka → ClickHouse, offset 유실 |
| `html/05_ops.html` | CI/CD · 관측성, 알림 미연결 · 메트릭 미수집 |

## 상세 다이어그램 (python `diagrams`, 전체 컴포넌트)

```bash
brew install graphviz   # 최초 1회
uv run python arch.py   # -> out/*.png
```

| 파일 | 관점 | 면접에서 쓰는 질문 |
|---|---|---|
| `out/01_topology.png` | 물리: 노드·ns·k3s 밖 프로세스 | "클러스터 어떻게 구성했나" |
| `out/02_data_flow.png` | 논리: 소스→ingest→medallion→serving→catalog | "데이터 흐름 설명해봐" |
| `out/03_ops.png` | CI/CD + 관측성 + 알림 공백 | "운영/배포는 어떻게" |

엣지 색: 검정=batch, 주황=streaming, 보라=CDC, 초록=publish, 파랑 점선=metadata, 회색 점선=타 시스템, **빨강=gap**.
근거: live cluster(kubectl/helm, 2026-11-11) + 각 repo 문서.

## 전체 흐름 요약

1. **Batch (A→B→C)**: Oracle/MariaDB/MySQL/Postgres/SaaS API → Airflow(Celery+K8s executor) ingest(pyiceberg, Spark-on-YARN) → Iceberg bronze(RustFS + HMS) → dbt-trino silver/gold → ClickHouse `gold.*` atomic swap.
2. **Streaming**: AMC tracking → Kafka 2.4 → tma-consumer → ClickHouse `tas.amc_tracking_log` → content-api.
3. **CDC**: MariaDB `tma` binlog → Debezium(ns cdc) → `cdc.tma.*` → CH Kafka engine → RMT → dbt-clickhouse marts(2–5분).
4. **Metadata**: data-catalog(03:00) → CH `data_catalog`; dbt manifest(04:30) + om-cronjob(05:00) → OpenMetadata → datalab portal.
5. **타 시스템**: cdp-pipeline(VM Airflow)이 k3s `spark` ns·Trino `iceberg_minio`를 공유, dagster는 orchestrator로 이관 중.

## 개선점 (우선순위 순)

| # | 영역 | 현상 (근거) | 개선 방향 |
|---|---|---|---|
| 1 | 알림 | Alertmanager `null` receiver뿐, rule 12개가 아무에게도 안 감 (data-monitoring `hold_261107`) | Teams webhook 연결, CDC lag/Airflow 실패 rule 추가 |
| 2 | SPOF | control-plane 1대, Trino coordinator 1대, ClickHouse 단일 노드, Connect x1, HMS 1대 | k3s HA(3 server) 또는 etcd 백업 최소화, CH replica 검토 |
| 3 | 자원 경합 | k3s worker = CDH 호스트 (Trino·YARN·RustFS·Spark 메모리 경합, airflow-worker OOM) (`backlog_261027_spark_on_k8s`) | 노드 역할 분리 or k8s 리소스 reservation + YARN 축소 |
| 4 | EOL | Kafka 2.4, CentOS 7 worker, CH 23.5, MariaDB 10.1 | OS→Rocky 8/9, Kafka 3.x(KRaft) 업그레이드 로드맵 |
| 5 | 데이터 정합 | tma-consumer 실패 시에도 offset commit → 재시작당 ~1k 유실 (`end-to-end-tracking-flow.md`) | 실패 시 commit 중단 + DLQ |
| 6 | 관측성 공백 | Trino·Airflow statsd에 ServiceMonitor 없음, tma-consumer는 plain JMX, alloy는 airflow ns만 수집 | ServiceMonitor 추가, jmx_exporter, alloy 전 ns |
| 7 | 보안 | NodePort 노출·TLS 없음, HTTP registry, CH `root` 계정 사용, `k8s_work/`에 평문 secret 이력 | Traefik Ingress+TLS, read-only CH user, secret rotate + SealedSecret |
| 8 | 배포 일관성 | k3s는 helm, tma-consumer/portal은 ssh+nohup/pm2, values image tag stale | 전부 k3s로 + GitOps(Argo CD) |
| 9 | 스토리지 | PV 전부 local-path (노드 죽으면 Loki/Prometheus/registry 데이터 유실), RustFS endpoint health check 없음 | Longhorn 등 replicated SC, RustFS 앞 LB/health check |
| 10 | 위생 | spark ns Completed pod 46개 누적, 메타데이터 이중 수집(data-catalog vs OM), 문서 gitignore | driver pod TTL, OM 단일화, 문서 커밋 |
