"""k3s data platform architecture diagrams.

Run: uv run python arch.py  ->  out/01_topology.png, out/02_data_flow.png, out/03_ops.png
Facts come from the live cluster (kubectl/helm, 2026-11-11) + repo docs.
Red nodes/edges = known risk / improvement point (see README.md).
"""

import os

from diagrams import Cluster, Diagram, Edge
from diagrams.gcp.analytics import Bigquery, DataCatalog
from diagrams.generic.storage import Storage
from diagrams.k8s.compute import Cronjob, Deployment
from diagrams.onprem.analytics import Dbt, Hadoop, Hive, Spark, Trino
from diagrams.onprem.ci import Jenkins
from diagrams.onprem.client import Users
from diagrams.onprem.container import K3S, Docker
from diagrams.onprem.database import ClickHouse, MariaDB, MySQL, Oracle, PostgreSQL
from diagrams.onprem.inmemory import Redis
from diagrams.onprem.logging import Loki
from diagrams.onprem.monitoring import Grafana, Prometheus
from diagrams.onprem.network import Internet
from diagrams.onprem.queue import Celery, Kafka
from diagrams.onprem.vcs import Git
from diagrams.onprem.workflow import Airflow
from diagrams.programming.framework import FastAPI, Svelte
from diagrams.programming.language import Java, Python
from diagrams.saas.chat import Teams

OUT = "out"
GRAPH = {
    "fontsize": "22",
    "pad": "0.5",
    "nodesep": "0.6",
    "ranksep": "1.0",
    "splines": "spline",
}
RISK = {"bgcolor": "#fdecea", "pencolor": "#d93025"}
OTHER = {"bgcolor": "#f1f3f4", "style": "dashed"}

BATCH = {"color": "black"}
STREAM = {"color": "darkorange", "style": "bold"}
CDC = {"color": "purple", "style": "bold"}
PUBLISH = {"color": "darkgreen", "style": "bold"}
META = {"color": "royalblue", "style": "dashed"}
LEGACY = {"color": "gray", "style": "dashed"}
GAP = {"color": "red", "style": "dashed"}


def e(style: dict, label: str = "") -> Edge:
    """Fresh styled edge (an Edge instance is bound to one connection)."""
    return Edge(label=label, **style)


def topology() -> None:
    """Physical view: which process runs on which host, inside/outside k3s."""
    with Diagram(
        "k3s Data Platform - Physical Topology",
        filename=f"{OUT}/01_topology",
        show=False,
        direction="TB",
        graph_attr=GRAPH,
    ):
        with Cluster(
            "k3s cluster  (1 control-plane, NodePort only, no Ingress/TLS, local-path PV)"
        ):
            with Cluster(
                "ma-tasonkr 121.189.17.250  control-plane | Rocky 8 | k3s 1.35",
                graph_attr=RISK,
            ):
                k3s = K3S("k3s server\n(SPOF)")
                af_ctrl = Airflow("airflow\napi x2 / scheduler\ndag-proc / triggerer")
                redis = Redis("airflow-redis\n(Celery broker)")
                coord = Trino("trino-coordinator\n(SPOF)")
                grafana = Grafana("grafana :30881")
                registry = Docker("docker-registry\n:30500 (HTTP)")
                tma = Java("tma-consumer\ncontent-api\n(bare JVM, not k3s)")

            with Cluster(
                "trino-worker-01..05 = CDH Hadoop hosts 10.147.1.125-129\n"
                "CentOS 7 (EOL) | k3s 1.34 | co-located, memory contention",
                graph_attr=RISK,
            ):
                tw = Trino("trino-worker x5")
                cw = Celery("airflow-worker x3\n+ KubernetesExecutor pods")
                sp = Spark("spark ns\ndriver/executor pods")
                dbz = Deployment("cdc-connect\nDebezium 2.7 (x1)")
                om = DataCatalog("openmetadata\n+ opensearch")
                rustfs = Storage("RustFS x5 :19010\n(host process, S3)")
                cdh = Hadoop("HDFS DN / YARN NM\n(host process)")

        with Cluster("External (VM / bare metal)"):
            hms = Hive("Hive Metastore\nkr-hadoop01:9083")
            nn = Hadoop("HDFS NN / YARN RM\nhadoop-ms01")
            ch = ClickHouse("ClickHouse 23.5\n10.147.1.53 (single node)")
            kafka = Kafka("Kafka 2.4 x3 (EOL)\n10.147.1.29-31")
            pg = PostgreSQL("Airflow metaDB\n(external Postgres)")
            portal = Svelte("datalab portal\n10.147.1.46 (pm2)")

        k3s >> e(BATCH) >> [tw, cw, sp, dbz, om]
        af_ctrl >> redis >> cw
        af_ctrl >> pg
        coord >> tw
        tw >> [rustfs, hms]
        sp >> e(BATCH, "jars/staging") >> nn
        cdh >> nn
        registry >> e(BATCH, "image pull") >> [af_ctrl, cw]
        dbz >> e(CDC) >> kafka
        tma << e(STREAM) << kafka
        tma >> e(STREAM) >> ch
        portal >> e(META, "REST :30885") >> om
        grafana >> e(META) >> ch


def data_flow() -> None:
    """Logical view: source -> ingest -> lakehouse -> serving -> consumers."""
    with Diagram(
        "k3s Data Platform - End-to-End Data Flow",
        filename=f"{OUT}/02_data_flow",
        show=False,
        direction="LR",
        graph_attr=GRAPH,
    ):
        with Cluster("Sources"):
            oracle = Oracle("Oracle\nPOSTMANDB")
            maria = MariaDB("MariaDB tma\n(10.1, binlog)")
            mysql = MySQL("MySQL IMC")
            pg_src = PostgreSQL("Postgres n8n\nTMS Cloud")
            apis = Internet("SaaS APIs\nCafe24 / Makeshop\nGoogle Trends")
            ga4 = Bigquery("GA4\nBigQuery")
            trackers = Users("AMC tracking\n(edge -> amc-api)")

        with Cluster("Streaming (real-time)"):
            kafka = Kafka("Kafka 2.4\namc-* / cdc.tma.*")
            dbz = Deployment("Debezium\nMariaDbConnector")
            tma = Java("tma-consumer\n(group amc-trk)")

        with Cluster("Orchestration  (ns airflow, Airflow 3.2 Celery+K8s)"):
            airflow = Airflow("Airflow\nAssets-driven")
            ingest = Python("ingest\npyiceberg / polars")
            spark = Spark("Spark 3.5\nYARN (orch) / k8s (cdp)")
            dbt = Dbt("dbt-trino\ndbt-clickhouse")

        with Cluster("Lakehouse (Iceberg medallion)"):
            trino = Trino("Trino 480\nns trino")
            hms = Hive("HMS\nkr-hadoop01")
            with Cluster("RustFS s3://datalake"):
                bronze = Storage("bronze\n(tma/tason/..)")
                silver = Storage("silver")
                gold = Storage("gold")

        with Cluster("Serving"):
            ch_gold = ClickHouse("ClickHouse gold.*\n(atomic swap)")
            ch_rt = ClickHouse("ClickHouse tas.* / cdc RMT\n(Kafka engine + MV)")
            content = Java("content-api :9610")

        with Cluster("Consumers / Catalog"):
            dash = Grafana("TMA / CDP\ndashboards")
            om = DataCatalog("OpenMetadata\n(om-cronjob ingest)")
            catalog = Python("data-catalog\n(stats + LLM desc)")
            portal = FastAPI("datalab portal\nFastAPI + SvelteKit")
            amc = Users("amc service")

        # batch medallion: (A) ingest -> (B) transform -> (C) publish
        [oracle, mysql, pg_src, apis, ga4] >> e(BATCH) >> ingest
        airflow >> e(BATCH, "trigger") >> [ingest, spark, dbt]
        ingest >> e(BATCH, "(A) append") >> bronze
        kafka >> e(STREAM, "IMC request_log") >> spark >> e(BATCH) >> bronze
        dbt >> e(BATCH, "(B) SQL") >> trino
        trino >> e(BATCH) >> hms
        bronze >> e(BATCH) >> silver >> e(BATCH) >> gold
        gold >> e(PUBLISH, "(C) publish") >> ch_gold

        # streaming / CDC
        (
            trackers
            >> e(STREAM)
            >> kafka
            >> e(STREAM, "amc-*-dev")
            >> tma
            >> e(STREAM)
            >> ch_rt
        )
        maria >> e(CDC, "binlog") >> dbz >> e(CDC, "cdc.tma.*") >> kafka
        kafka >> e(CDC, "Kafka engine") >> ch_rt
        dbt >> e(BATCH, "marts 2-5min") >> ch_rt
        ch_rt >> content >> amc

        # serving & metadata
        [ch_gold, ch_rt] >> e(PUBLISH) >> dash
        [trino, ch_gold, maria] >> e(META, "05:00 ingest") >> om
        dbt >> e(META, "manifest.json") >> om
        catalog >> e(META, "03:00 stats") >> ch_gold
        [om, ch_gold] >> e(META) >> portal

        with Cluster("Other systems (separate, shared infra)", graph_attr=OTHER):
            cdp = Airflow("cdp-pipeline\nAirflow docker-compose\n10.147.1.140")
            dagster = Python("dagster-pipeline\n(migrating -> orchestrator)")
            minio = Storage("MinIO tkc-bucket\n(iceberg_minio)")
        cdp >> e(LEGACY, "spark_k8s") >> spark
        cdp >> e(LEGACY) >> minio >> e(LEGACY, "JDBC catalog") >> trino
        dagster >> e(LEGACY, "hive catalog") >> trino


def ops() -> None:
    """Ops view: CI/CD path + observability + alerting gap."""
    with Diagram(
        "k3s Data Platform - CI/CD & Observability",
        filename=f"{OUT}/03_ops",
        show=False,
        direction="LR",
        graph_attr=GRAPH,
    ):
        with Cluster("CI/CD (push-based, no GitOps)"):
            git = Git("Bitbucket")
            jenkins = Jenkins("Jenkins\nsyntax/boundary check")
            build = Docker("docker build\non ma-tasonkr")
            registry = Docker("registry :30500")
        git >> jenkins >> build >> registry

        with Cluster("k3s"):
            helm = K3S("helm upgrade\n--image-tag <sha>")
            airflow = Airflow("airflow\n(dags+src+dbt in 1 image)")
            trino = Trino("trino")
            dbz = Deployment("cdc-connect")
            with Cluster("ns monitoring"):
                prom = Prometheus("kube-prometheus-stack\n(cdh-prometheus)")
                prom_tma = Prometheus("prometheus-tma")
                exporters = Cronjob(
                    "yarn-exporter / blackbox\nkafka-exporter / chmonitor\nspark-app-collector"
                )
                alloy = Deployment("alloy\n(airflow ns only)")
                loki = Loki("loki\n(S3 on RustFS, 30d)")
                grafana = Grafana("grafana\nsingle pane")
                am = Prometheus("alertmanager\nnull receiver")
        registry >> e(BATCH, "image") >> helm >> airflow
        (
            jenkins
            >> e(BATCH, "ssh + nohup / pm2")
            >> Java("tma-consumer\ndatalab portal (VMs)")
        )

        with Cluster("External targets"):
            cdh = Hadoop("CDH hosts\nnode-exporter / JMX")
            ch = ClickHouse("ClickHouse\n(root user)")
            kafka = Kafka("Kafka 2.4")
            hostlogs = Loki("host alloy\n(CDH logs)")

        [cdh, exporters] >> e(BATCH, "scrape") >> prom
        [kafka, dbz] >> e(BATCH, "scrape") >> prom_tma
        airflow >> e(BATCH, "pod logs") >> alloy >> loki
        hostlogs >> loki
        [prom, prom_tma, loki, ch] >> e(META) >> grafana
        (
            [trino, airflow]
            >> e(GAP, "no ServiceMonitor\n(trino JMX, airflow statsd)")
            >> prom
        )
        (
            prom
            >> e(BATCH, "12 rules")
            >> am
            >> e(GAP, "not wired")
            >> Teams("Teams\n(pending)")
        )
        exporters >> e(BATCH) >> ch


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    topology()
    data_flow()
    ops()
