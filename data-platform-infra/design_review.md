# Data Platform 설계 리뷰 — topology · 데이터 흐름 · 효율화

> 기준일 2026-11-11. 근거는 live cluster(`kubectl top/describe`) + 각 repo 코드·문서 (`file:line`).
> 관점: 시스템 디자인(SPOF, 확장, 운영) + 데이터 엔지니어(정합성, 중복, 비용, 계보).
> 요약 다이어그램은 `html/`, 기존 개선점 10개는 `README.md`. 이 문서는 그걸 **왜/어떻게/무엇부터**로 확장한다.

---

## 0. 한 줄 결론

**구조의 뼈대(Iceberg medallion + atomic publish + CDC)는 맞다. 문제는 세 가지로 수렴한다.**

1. **같은 데이터를 여러 경로로 여러 번 옮긴다** — MariaDB `tma`는 batch(FullReplace)와 CDC로 이중 수집, 메타데이터는 data-catalog와 OpenMetadata로 이중 수집, 오케스트레이터는 3개(Airflow k3s / Airflow VM / Dagster).
2. **흐름 방향이 군데군데 거꾸로다** — tracking은 ClickHouse(serving)가 원본이고 lake가 그걸 다시 읽음, dbt 모델이 Trino로 `clickhouse.gold`를 읽음. serving DB가 사실상 system of record가 됨.
3. **자원은 남는데 한 노드에 몰려 있고, 장애는 아무도 모른다** — worker 160 core는 CPU 5–7%, control-plane 8 core/24GB는 메모리 79%. Prometheus 알림은 `null`.

---

## 1. 현재 구조 (as-is)

```
                    ┌──────────────── k3s ────────────────────────────────────┐
 Oracle/MySQL/PG ──►│ Airflow ingest (pyiceberg) ─► Iceberg bronze (RustFS+HMS)│
 SaaS API        ──►│        │                         │ dbt-trino            │
 MariaDB tma ──┬───►│ (FullReplace, */10)              ▼                      │
               │    │                         silver ─► gold ──publish──┐     │
               │    │                                  ▲ ③ Trino가 CH를 읽음 │
               └─CDC┤ Debezium ─► Kafka 2.4 ─► CH Kafka engine ─► RMT ─┤     │
         ① 이중수집 │                ▲                                  ▼     │
 AMC tracking ─────►│──────────────── tma-consumer(VM) ─────► ClickHouse 23.5 │
                    │                                    (단일 노드, SoR화)   │
                    │  ② daily: CH FINAL ─► iceberg.amc_bronze.tracking_log  │
                    └──────────────────────────────────────────────────────────┘
 메타: data-catalog(03:00) ─► CH data_catalog ┐
       OM cronjob(05:00~05:40) ─► OpenMetadata ┴─► datalab portal  ④ 이중수집
```

| 측정값 | control-plane `ma-tasonkr` | worker ×5 (각) |
|---|---|---|
| 사양 | 8 core / 24 GB | 32 core / 128 GB |
| 실사용 | CPU 41%, **MEM 79%** | **CPU 5–7%**, MEM 52–64% (CDH 포함) |
| limit 합 | CPU 245%, **MEM 121%** (overcommit) | CPU 94–128%, MEM 51–68% |
| pod | 30개 (airflow 8, monitoring 13, trino coordinator, registry, kube-system) | trino/spark/cdc/OM/airflow-worker |
| 원인 | worker 전부 `dedicated=trino:NoSchedule` taint → toleration 없는 pod는 전부 control-plane으로 | |

---

## 2. 잘 된 설계 (면접에서 먼저 말할 것)

| 결정 | 왜 좋은가 | 근거 |
|---|---|---|
| bronze write = 단일 트랜잭션 `delete + append` | rerun 멱등. 부분 실패 시 반쪽 데이터 없음 | `platform_sdk/iceberg/store/replace.py:71-136` |
| 적재 전략 4종 명시 (FullReplace / PartitionOverwrite+watermark / IncrementalAppend / FullSnapshot) | 테이블 특성별 선택을 코드로 강제 | `pipeline/ingest/load_strategies.py` |
| CH publish = staging → `EXCHANGE TABLES` / `REPLACE PARTITION` | 조회 중단 없는 atomic swap, 실패 시 기존 데이터 유지 | `pipeline/serving/staging.py:25,37` |
| CDC: `snapshot.mode=no_data` + signal topic 증분 스냅샷, `read.only=true` | 운영 DB에 lock 없이 baseline | `data-streaming/connectors/tma.json:15-19` |
| CDC 토픽 RF=3, `min.insync.replicas=2` | 브로커 1대 장애에도 유실 없음 | `scripts/topics.py:13-21` |
| CH `ReplacingMergeTree(cdc_version=GTID, is_deleted)` | 순서 역전·중복 이벤트에도 최종값 수렴, delete 반영 | `cdc_common/ch_ddl.py:61-92` |
| Iceberg 유지보수: commit 빈도 따라 snapshot 보존 7d/2d, orphan 정리는 crc32%7 샤딩 | 메타데이터 폭증·스토리지 누수 방지, 부하 분산 | `pipeline/maintenance/table_maintenance.py:59-106` |
| dbt 257 모델, 테스트 ~350개 + unit test 8 | 품질 게이트가 코드에 있음 | `dbt/models`, `dbt/tests` |
| 모든 DAG `on_failure_callback` → Teams, `max_active_runs=1` | 배치 실패는 즉시 인지 | `common/alerts/teams.py:105` |

---

## 3. 개선·효율화 포인트

각 항목: **현상(근거) → 왜 문제 → 제안 → 효과**. 우선순위는 §4.

### A. Topology / 인프라

#### A1. control-plane 과적재 vs worker 유휴 ★
- **현상**: 위 표. worker taint 때문에 monitoring 13개·Airflow 제어면·registry·trino coordinator가 8 core 노드 하나에. 10/16–17에 control-plane pod 다수가 같은 시각 재시작(metrics-server 20회, traefik 18회).
- **왜**: k3s server + etcd(sqlite)가 워크로드와 메모리를 다툼 → control-plane이 흔들리면 클러스터 전체가 흔들림. 동시에 worker CPU 95%는 놀고 있음.
- **제안**: (1) monitoring·registry·agentops에 `dedicated=trino` toleration + worker nodeSelector, (2) control-plane에 `CriticalAddonsOnly` 또는 `NoSchedule` taint로 k3s 시스템만 남김, (3) trino coordinator도 worker로 (메모리 여유 큼).
- **효과**: control-plane 메모리 ~50% 회수, 설정 변경만으로 가능. HA(3 server)보다 먼저 할 일.

#### A2. worker는 CPU가 아니라 메모리 바운드
- **현상**: CPU 5–7%인데 메모리 52–64% — CDH(YARN NM, HDFS DN) + Trino JVM + RustFS가 같은 호스트. Trino OOM으로 OM ingest가 358→254 테이블로 잘림(`data-discovery/backlog_260915_openmetadata_remaining.md`), dbt 224M row dedup에서 `CLUSTER_OUT_OF_MEMORY`(`dbt/dbt_project.yml:180`).
- **제안**: Trino `query.max-memory-per-node`·heap을 YARN 할당과 합쳐 호스트 총량 기준으로 재산정, spill-to-disk 활성화, 대형 dedup은 Spark(YARN, 여유 CPU) 쪽으로. 근본은 YARN 축소 → 노드 역할 분리.

#### A3. SPOF 지도
| 컴포넌트 | 대수 | 죽으면 | 최소 대응 |
|---|---|---|---|
| k3s server | 1 | 스케줄링·API 정지 (pod은 계속 동작) | datastore 정기 백업 → 이후 3 server |
| ClickHouse 23.5 | 1 | **모든 serving + tracking 원본 + CDC 반영** 정지 | 아래 B1과 함께: 원본을 lake로 옮기면 CH는 "재생성 가능한 캐시"가 됨 |
| RustFS endpoint (Trino 외 client) | 1 | ingest·Loki·CH `s3()` 정지 | endpoint 분산 (`backlog_261020_s3_endpoint_spread_remaining_clients.md`) |
| HMS `kr-hadoop01` | 1 | Iceberg 전체 read/write 정지 | HMS 2대 + DB HA, 장기적으로 REST catalog |
| Debezium Connect | 1 | CDC 지연 (offset 있으니 유실은 없음) | 우선순위 낮음 |
| PV (local-path) | — | 노드 장애 시 Prometheus/Loki/registry/OpenSearch 데이터 유실 | registry 50Gi와 OpenSearch 30Gi만이라도 백업 |

#### A4. EOL — Kafka 2.4, CentOS 7, CH 23.5, MariaDB 10.1
- 기능 영향이 큰 건 **CH 23.5**: `async_insert`·lightweight delete·Iceberg/S3 table function 성능이 이후 버전에서 크게 개선. `s3()` 직접 publish(B4)를 밀려면 업그레이드가 같이 가야 함.

### B. 데이터 흐름 (배치)

#### B1. tracking: serving DB가 원본, lake가 사본 (흐름 역전) ★
- **현상**: AMC tracking은 Kafka → tma-consumer → CH `tas.amc_tracking_log`가 최초 착지점. lake는 매일 00:00 **CH를 `FINAL`로 읽어서** `iceberg.amc_bronze.tracking_log`를 만든다(`domains/amc/tracking_bronze/tables.py:9,26`, `dag_amc_db_daily.py:52`). cdp-pipeline도 CH tracking을 직접 읽음.
- **왜**: CH에서 유실·key collision(아래 C1)이 나면 lake도 똑같이 잃는다 — 재처리 원천이 없음. Kafka 보존 7일이 지나면 복구 불가. 매일 `FINAL` 풀스캔 비용.
- **제안**: IMC request_log에 이미 있는 **Kafka → Spark AvailableNow → Iceberg bronze(10분)** 패턴(`dags/imc/stream/dag_imc_stream_request_log_intraday.py`)을 amc-* 토픽에 재사용. bronze를 원본으로, CH는 bronze에서 파생(또는 실시간 경로는 유지하되 lake가 Kafka에서 독립 착지).
- **효과**: 재처리 가능한 불변 원본 확보, CH 단일 노드의 위험이 "서빙 정지"로 축소, `FINAL` daily scan 제거. 새 코드 거의 없음(기존 패턴 재사용).

#### B2. MariaDB `tma` 이중 수집 ★
- **현상**: CDC 대상 9개 테이블(`connectors/tma.json` `table.include.list`) 중 8개(SITE_INFO, PROGRAM_MA, PROGRAM_MA_SCHD, …_CHANNEL, …_CNVRS, …_SCENARIO, MA_CONTENT_RESEND, TEST_USER_LIST)를 batch도 직접 읽는다(`domains/tma/ingest/tables.py`). tma는 19개가 FullReplace, intraday upstream이 `*/10`.
- **왜**: 운영 DB(MariaDB 10.1, EOL)에 10분마다 풀스캔 + binlog 읽기 이중 부하. 두 경로가 서로 다른 시점의 값을 갖게 돼 "batch mart vs CDC mart" 숫자 불일치의 원천(실제로 schd_channel diff gate가 cutover 전 대기 중, `data-streaming/11_IN_PROGRESS/COLD_START.md:8`).
- **제안**: CDC 토픽을 bronze의 단일 원천으로. Kafka → Iceberg(B1과 같은 Spark AvailableNow + `MERGE`, 또는 Iceberg Kafka Connect sink) 후 batch FullReplace 해당 8개 제거.
- **효과**: 운영 DB 부하 감소, 한 원천에서 batch/realtime 둘 다 파생 → 숫자 일치.

#### B3. 계보 순환: Trino가 ClickHouse gold를 읽음
- **현상**: dbt-trino 모델이 Trino `clickhouse` 카탈로그로 CH `gold.fct_tma_orders`를 source로 읽어 silver(Iceberg)를 만듦.
  - `int_tas__campaign_purchase.sql:19` ← `source('tas_campaign_clickhouse', 'fct_tma_orders')` (`01_staging/tas/campaign/_tas_campaign__sources.yml:4-6`, `database: clickhouse`)
  - tma campaign_user도 같은 방식 (`01_staging/tma/campaign_user/_tma_campaign_user__sources.yml:15-17`: "기존 TMA gold 마트(ClickHouse 네이티브)")
  - source 설명은 "ClickHouse 네이티브"라고 하지만 실제로는 **lake `iceberg.gold.fct_tma_orders`를 publish한 사본**(`domains/tma/serving/orders/targets.py:10-11`) → 진짜 순환: lake gold → CH → Trino → lake silver.
  - 2026-11-11 Trino 대조 결과 **완전 일치**: 전체 7,237,256행 / 키 중복 0 / `sum(actual_payment_amount)` 동일 / 기간 동일, 캠페인 대상 사이트(11163336, 152152) 218,812행, 키 diff lake_only 0 · ch_only 0. 읽기 시간은 lake 2.9s vs CH 16.5s(전체 집계).
  - dbt-clickhouse target 모델이 CH gold를 읽는 것(`fct_tma_site_id_health_daily`, `fct_tma_campaign_user_send_history`)은 같은 엔진 안이라 해당 없음.
- **왜**: lake 변환이 serving DB에 의존 → CH 장애·지연이 batch를 막고, 주문 데이터의 원본이 lake 밖에 있어 재처리·계보 추적이 CH에서 끊김.
- **제안**: 대조가 일치했으므로 두 source(`tas_campaign_clickhouse`, tma campaign_user)의 `fct_tma_orders`를 `ref('fct_tma_orders')`로 교체 — 이관 작업 불필요. 부수 효과로 dbt가 orders → campaign 의존을 알게 되고 lineage도 이어짐. 신규 모델이 같은 패턴을 늘리지 않게 `database: clickhouse` source 추가는 리뷰에서 막기.

#### B4. publish 경로가 Airflow worker 메모리를 통과
- **현상**: Trino → Python `fetchmany(500k)` → polars → CH insert(`pipeline/serving/transport.py:17,29`). campaign_user_send publish 하루 ~70분(`backlog_261024_...`). scheduler/worker OOM 회고 다수(`docs/retro_*_oom_*.md`). 반면 CH가 Iceberg Parquet을 `s3()`로 직접 읽는 경로는 이미 있음(`parquet_load.py:83`, 2곳만 사용).
- **왜**: 데이터가 worker를 경유 → 직렬화 2번 + OOM 위험 + worker 슬롯 점유.
- **제안**: `s3()` 경로를 기본값으로. 막힌 이유는 dbt `delete+insert`가 남긴 position-delete 파일(132개)을 CH가 못 읽기 때문(`backlog_261104_...`) → B5 해결이 선행 조건.
- **효과**: publish 시간·worker 메모리 대폭 감소, row-count 검증은 이미 있음.

#### B5. Iceberg 쓰기 속성 불일치 + position-delete 누적
- **현상**: zstd·`target-file-size=128MB`는 `provision.py` 경로만 설정, bronze `open_table`은 메타 보존 속성만 설정(`table_definition.py:16-19`). 파티션은 생성 후 Identity로 추가(`iceberg_sink.py:108-113`). dbt `delete+insert` 8개 모델이 merge-on-read delete 파일을 쌓음(`backlog_261110_iceberg_delete_insert_compaction.md`).
- **제안**: (1) 테이블 생성 공통 경로 하나에서 `write.format.default`, compression, target-file-size, `write.delete.mode`를 일괄 지정, (2) publish 대상 테이블은 `copy-on-write` 또는 dbt `insert_overwrite`로 전환(이미 OM 쪽에서 같은 해법으로 해결한 전례, `backlog_260915_openmetadata_remaining.md`), (3) 유지보수 DAG에 `rewrite_position_delete_files` 추가.

#### B6. FullReplace 비중 = 매 실행 전체 재적재
- **현상**: 65개 bronze 테이블 중 **39개 FullReplace**(tma 19 / tas 15 / imc 4 / tms 1). IncrementalAppend 5개는 lookback 중복을 dbt에서 사후 dedup(`int_tas__ebad_sends.sql:1`).
- **제안**: 행 수 상위 10개만 골라 `PartitionOverwrite + revision_column` watermark로(이미 구현된 전략). IncrementalAppend는 append 대신 lookback 구간 `PartitionOverwrite`로 바꾸면 dbt dedup 단계 자체가 사라짐. 작은 코드 테이블은 FullReplace 유지(그게 더 단순).

#### B7. CDC mart: 10분마다 `FINAL` 전체 재빌드
- **현상**: `fct_tma_campaign_schd_channel_cdc` = `materialized='table'`, 모든 source CTE `final where is_deleted=0`(`dbt/models/03_marts/tma/core/...cdc.sql:4-20`). ADR-0009 "전체 재빌드 2~5분".
- **왜**: 원천 테이블이 커질수록 비용이 선형 증가 → 10분 주기와 충돌하는 시점이 옴.
- **제안**: ADR-0008의 S2(닫힌 파티션 + raw tail union) 패턴으로 전환 기준을 미리 정해둘 것 — 예: 재빌드 > 주기의 50%.

#### B8. ClickHouse DDL이 dbt 밖에서 수기 관리
- **현상**: serving DDL 49개가 `domains/*/serving/**/ddl/*.sql`에 별도. dbt contract 없음, `dbt source freshness`는 GA4에만 선언되고 호출은 없음.
- **제안**: publish 대상 gold 모델에 dbt `contract: enforced` → 컬럼/타입 drift를 publish 전에 실패시킴. freshness는 ingest 직후 `dbt source freshness` 한 단계로.
- **참고**: gold를 전체 EXCHANGE하는 테이블이 `ReplacingMergeTree(loaded_at)`인 경우 dedup이 필요 없으니 `MergeTree`로 충분(FINAL 비용 제거).

### C. 실시간 (streaming / CDC)

#### C1. tma-consumer 정합성 — 알려진 유실 경로 3개 ★
| 경로 | 상태 | 근거 |
|---|---|---|
| Redis/MariaDB 실패를 per-message `catch(Exception)`로 삼키고 offset commit | **미착수, HIGH** | `tma-consumer/BACKLOG-260909-processor-infra-failure-swallow.md` |
| `ReplacingMergeTree` ORDER BY key가 서로 다른 이벤트를 같은 키로 → merge 시 소멸 | 2건 확인 | `BACKLOG-orderby-key-collision.md` |
| MV의 MySQL dictionary 의존 → MySQL 장애 시 전체 적재 정지 | HIGH | `BACKLOG-261021-mv-mysql-dependency.md` |
- **제안**:
  - 인프라 예외는 삼키지 말고 throw → `DefaultErrorHandler` backoff(이미 설정됨)가 재시도, 데이터 예외만 DLT. 코드 수십 줄.
  - tracking 로그는 append-only 이벤트 → **`MergeTree`** + 중복 제거가 필요하면 `event_id`를 ORDER BY에 포함. RMT는 "업데이트되는 엔티티"용.
  - enrichment(MySQL lookup)는 MV에서 빼서 조회 시점 dictionary join 또는 별도 배치로.
- **효과**: "재시작당 ~1k 유실" 해소. 면접 포인트: *at-least-once는 commit 위치가 아니라 실패 처리 정책에서 결정된다.*

#### C2. 작은 insert × 많은 스레드
- **현상**: concurrency 20 × topic, "insert당 ~10 rows, 80 threads"(`ClickHouseTrackingLogRepository.java:57`), `async_insert=1`로 CH가 대신 모음. part 폭증 회고 있음(`docs/retro-ch-insert-part-explosion.md`).
- **제안**: consumer 쪽에서 rows/시간 기준 배치(예: 10k rows 또는 1s) 후 insert, concurrency는 파티션 수 맞춰 낮춤. per-message lookup 비용(`BACKLOG-260909-per-message-lookup-cost`)도 배치 단위 lookup으로 같이 해결.

#### C3. CDC 스키마 계약 없음
- **현상**: JsonConverter `schemas.enable=false`, schema registry 없음(`tma.json:34-37`). CH는 `JSONAsString`으로 받아 파싱. `kafka_skip_broken_messages` 미설정.
- **판단**: skip 미설정은 **유실보다 정지를 택한 것이라 옳다** — 단, 정지를 알려주는 알림이 없다(D1). 스키마는 MariaDB DDL 변경이 잦지 않다면 지금은 schema history topic으로 충분; 소스가 늘면 registry.
- **처리량**: CDC 토픽 1 partition(순서 보장 목적, 정당). 병목이 되면 PK 해시 파티셔닝.

#### C4. 공유 Kafka 2.4
- tracking(20 partition × 6 topic)과 CDC가 같은 3 broker. tracking 폭주가 CDC 지연으로 번짐. 업그레이드(3.x KRaft) 시점에 quota 설정 또는 클러스터 분리 검토.

### D. 메타데이터 / 운영

#### D1. 알림: 배치는 있고, 플랫폼·데이터는 없다 ★
- **현상**: Airflow 실패 → Teams는 동작. 하지만 Prometheus rule 12개는 전부 CDH용이고 Alertmanager receiver는 `null`. CDC lag·consumer lag·freshness 알림은 **의도적 보류**(`data-monitoring/hold_261107_cdc_monitoring.md:7,20`). 데이터 수집 지표(kafka-exporter lag, Connect JMX)는 이미 Prometheus에 있음.
- **왜**: "DAG 성공 + 데이터 안 들어옴"(CDC 정지, consumer 정지, Kafka engine 정지)은 아무도 모른다. 실시간 경로는 DAG가 아니라서 `on_failure_callback`이 없다.
- **제안 (최소 3개)**: Teams receiver 연결 후
  1. `kafka_consumergroup_lag` 임계 초과 N분 (tma-consumer, CH Kafka engine group)
  2. CDC 대상 CH 테이블 최신 `cdc_version`/행 증가 정지 N분 (blackbox SQL 또는 chmonitor)
  3. 핵심 gold 테이블 freshness (`max(loaded_at)` 기준)
- 메트릭이 이미 있으니 rule 3개 + receiver 1개. 비용 대비 효과 최대.

#### D2. 메타데이터 이중 수집
- **현상**: data-catalog(03:00)와 OM cronjob(05:00–05:40)이 같은 소스(ch, mariadb, imc, tms-cloud, tason, trino-hive)를 각자 harvest. portal은 둘 다 읽음(`datalab-catalog/api/.../routes.py`, `sources/catalog_stats.py:14`). 같은 시간대에 Trino를 두 번 두드리고, OM 쪽은 Trino OOM으로 실패.
- **제안**: 스키마/계보는 OM 단일 원천, data-catalog는 **OM에 없는 것(통계, LLM 설명)만** 생성해 OM API로 push. portal은 OM 하나만 읽음.

#### D3. 오케스트레이터 3개 + 중복 job
- **현상**: dagster `tas_postman_ingest_job`(Oracle → HDFS, 05:00, 기본 활성)이 data-orchestrator tas ingest와 겹침. dagster gold schedule 11개 RUNNING. cdp-pipeline(VM Airflow)은 CH tracking과 Hive를 따로 읽어 `cdp.*` 생성. HHID registry는 writer 2개, dedup 규칙이 서로 다름(`backlog_261023_hhid_registry_dual_writer.md`).
- **제안**: 이관 완료된 dagster job은 즉시 STOPPED, 남은 것은 목록화 후 기한. 같은 테이블의 writer는 1개로(registry는 소유 DAG 하나).
- *운영 상태는 코드로만 확인 — 실제 실행 여부는 Dagster UI에서 확인 필요.*

#### D4. 배포 이미지가 무겁다
- **현상**: 단일 이미지에 Airflow + Spark + Hadoop + Oracle client + DuckDB + dbt + dags. `.dockerignore` 없음, `infra/deploy_airflow.sh:21`이 working tree 그대로 build → `dags/repo/data-catalog/.venv`(437MB), `dbt/target`(27MB) 포함 가능. dbt 모델 하나 바꿔도 이미지 재빌드 + 전체 pod 재기동.
- **제안**: `.dockerignore` 한 파일(즉시). 그 다음 base 이미지(런타임 의존성)와 code 레이어 분리 → 코드 변경 시 마지막 레이어만.

#### D5. 기타
- spark ns Completed pod 누적은 현재 미관측(Running 5) — 정리됐거나 TTL 적용 확인 필요, README #10에서 제외 가능.
- 보안(NodePort/TLS, HTTP registry, CH root, 평문 secret 이력)은 README #7 그대로.

---

## 4. 우선순위

| 순위 | 항목 | 효과 | 공수 | 비고 |
|---|---|---|---|---|
| 1 | D1 알림 3개 + Teams receiver | 사일런트 장애 제거 | 0.5일 | 메트릭 이미 있음 |
| 2 | C1 consumer 예외 처리 | 확인된 유실 제거 | 1일 | 코드 변경 작음 |
| 3 | A1 taint/toleration 재배치 | control-plane 안정 | 0.5일 | values 수정만 |
| 4 | D4 `.dockerignore` | 빌드 시간·이미지 크기 | 1시간 | |
| 5 | D3 중복 dagster job 정지 | 소스 DB 부하, 혼선 | 1시간 | 실행 여부 확인 후 |
| 6 | B3 `fct_tma_orders` source → `ref()` 교체 | lake 변환의 CH 의존 제거 | 0.5일 | 대조 완료: 완전 일치 (11-11) |
| 7 | B5 → B4 Iceberg 속성 정리 → `s3()` publish 기본화 | publish 70분↓, OOM↓ | 1–2주 | B5가 선행 |
| 8 | B1 + B2 Kafka → Iceberg bronze (tracking, CDC) | 원본 확보, 이중수집 제거 | 2–4주 | IMC 패턴 재사용 |
| 9 | D2 메타데이터 단일화 | Trino 부하·혼선 | 1–2주 | |
| 10 | A3/A4 HA·EOL 로드맵 | 장기 리스크 | 분기 | CH 업그레이드는 B4와 연동 |

**1–6은 이번 주 안에 끝나는 설정·소규모 코드 변경이고, 7–8이 구조 개선의 본체다.**

---

## 5. to-be (구조 개선 후)

```
 OLTP(MariaDB) ─CDC─┐
 AMC tracking ──────┼─► Kafka ─► Spark AvailableNow (10분) ─► Iceberg bronze  ◄── 유일한 원본
 Oracle/SaaS ─batch─┘                                            │ dbt-trino
                                                    silver ─► gold (contract 강제)
                                                                 │ CH s3() direct read
                                         실시간 필요분만 ─────►  ClickHouse (재생성 가능한 캐시)
                                         (Kafka engine 유지)        │
                                                                   ▼ dashboards / amc / portal
 메타: dbt manifest + OM (단일) ◄── data-catalog는 통계·LLM 설명만 push
 알림: Airflow 실패 + consumer lag + CDC 정지 + gold freshness → Teams
```

원칙 세 줄:
1. **원본은 lake 한 곳**, CH는 언제든 lake에서 다시 만들 수 있어야 한다.
2. **소스 하나 = 수집 경로 하나 = writer 하나.**
3. **"성공했는데 데이터가 없다"를 알림으로 잡는다** (실패 알림만으로는 부족).

---

## 6. 규모가 커지면 다시 볼 것

| 트리거 | 다시 볼 결정 |
|---|---|
| CDC mart 재빌드 > 주기의 50% | B7 S2 증분 패턴 |
| tracking 일 수억 건 / CH 디스크 70% | CH replica·shard, 23.5 → 최신 LTS |
| CDC 소스 DB 추가 | schema registry(Avro), 토픽 파티셔닝 |
| 팀/도메인 증가 | HMS → Iceberg REST catalog, 도메인별 Trino resource group |
| 노드 장애 1회 발생 | local-path → replicated storage, k3s 3 server |

---

## 7. 면접용 요약 (30초 버전)

> "k3s 위에 Airflow·Trino·Iceberg로 medallion을 만들고, bronze 적재는 단일 트랜잭션 delete+append로 멱등하게, ClickHouse publish는 staging + EXCHANGE로 atomic하게 했습니다. CDC는 Debezium no_data 스냅샷 + GTID 버전 RMT로 운영 DB 부하 없이 최종 일관성을 맞췄습니다.
> 리뷰해 보니 개선점은 세 가지였습니다. 같은 소스를 batch와 CDC로 이중 수집하는 것, tracking처럼 serving DB가 원본이 되어 lake가 거꾸로 복사하는 흐름, 그리고 실패는 알리지만 '데이터가 안 들어오는 상태'는 감지 못하는 것. 그래서 Kafka → Iceberg를 단일 원본으로 만들고, CH는 재생성 가능한 서빙 캐시로, 알림은 lag·freshness 기준으로 바꾸는 로드맵을 잡았습니다."
