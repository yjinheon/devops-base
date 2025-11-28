
from diagrams import Diagram, Cluster, Edge
from diagrams.azure.compute import AKS, ContainerInstances
from diagrams.azure.database import SQLDatabases
from diagrams.azure.storage import BlobStorage
from diagrams.azure.network import (
    LoadBalancers,
    NetworkSecurityGroupsClassic,
)
from diagrams.onprem.client import Users
from diagrams.onprem.monitoring import Prometheus, Grafana
from diagrams.onprem.network import Internet, Nginx

with Diagram(
    "Azure MSA Architecture - AKS with NGINX Ingress Controller",
    show=False,
    direction="TB",
    filename="azure_msa_aks_nginx_simplified",
    outformat="pdf",
):
    # External Users
    users = Users("External Users")

    # Internet Gateway
    internet = Internet("Internet")

    with Cluster("Azure Virtual Network"):

        # Azure Load Balancer (for NGINX Ingress Controller)
        azure_lb = LoadBalancers("Azure Load Balancer\n(External - Public IP)")

        # NAT Gateway for outbound internet access from private subnet
        nat_gateway = Internet("NAT Gateway\n(Outbound Internet)")

        with Cluster("Public Subnet (DMZ)"):
            nsg_public = NetworkSecurityGroupsClassic("NSG - Public\n(Port 80,443)")

        with Cluster("Private Subnet - AKS Cluster"):
            nsg_private = NetworkSecurityGroupsClassic("NSG - Private\n(Internal only)")

            # AKS Cluster
            aks_cluster = AKS("AKS Cluster\n(Azure Kubernetes Service)")

            with Cluster("Ingress Namespace"):
                nginx_ingress = Nginx(
                    "NGINX Ingress Controller\n(LoadBalancer Service)\nPods"
                )

            with Cluster("API Gateway Namespace"):
                api_gateway = ContainerInstances(
                    "API Gateway\n(Spring Cloud Gateway)\nPods (HPA enabled)"
                )

            with Cluster("Core Services Namespace"):
                dynamic_api = ContainerInstances("Dynamic API\n(Spring Boot)\nPods")
                scv_service = ContainerInstances("SCV Service\n(Data Collection)\nPods")
                apim_server = ContainerInstances("APIM Server\n(APIM CRUD)\nPods")
                auth_server = ContainerInstances("Auth Server\nPods")
                data_processor = ContainerInstances(
                    "Data Processor\n(ETL Service)\nPods"
                )

            with Cluster("Monitoring Namespace"):
                prometheus = ContainerInstances("Prometheus\nPods")
                grafana = ContainerInstances("Grafana\nPods")
                loki = ContainerInstances("Loki\nPods")

    # Simplified Data Architecture
    with Cluster("Azure Database Services"):
        # Collection Database (수집 DB)
        collection_db = SQLDatabases(
            "Collection DB\n(Data Collection)\nRaw & Metadata"
        )

    with Cluster("Azure Storage"):
        # Object Storage for Data Lake
        object_storage = BlobStorage(
            "Azure Blob Storage\n(Object Storage)\nRaw Data Lake"
        )

        # Blob Storage for Files
        blob_storage = BlobStorage("Azure Blob Storage\n(Files, Logs, Assets)")

    # External Data Sources
    external_api = Users("Public Data APIs\n(External)")

    # Main Traffic Flow - Internet to NGINX Ingress
    (
        users
        >> Edge(label="HTTPS")
        >> internet
        >> Edge(label="Public IP")
        >> azure_lb
        >> Edge(label="Route to AKS")
        >> aks_cluster
        >> Edge(label="LoadBalancer Service")
        >> nginx_ingress
    )

    # NGINX Ingress to API Gateway
    nginx_ingress >> Edge(label="Ingress Rule\n(Path-based routing)") >> api_gateway

    # API Gateway to Private Services (Internal Service Mesh)
    api_gateway >> Edge(label="Service Mesh\n(Internal API)") >> dynamic_api
    api_gateway >> Edge(label="Service Mesh\n(Auth)") >> auth_server
    api_gateway >> Edge(label="Service Mesh\n(APIM CRUD)") >> apim_server

    # Simplified Data Flow
    # 1. Data Collection: External API -> Collection DB
    (
        external_api
        >> Edge(label="Data Collection\n(via NAT Gateway)")
        >> nat_gateway
        >> aks_cluster
        >> scv_service
        >> Edge(label="Store Raw Data", color="orange")
        >> collection_db
    )

    # 2. Data Export: Collection DB -> Object Storage
    (
        collection_db
        >> Edge(label="Export to\nObject Storage", color="blue")
        >> data_processor
        >> Edge(label="Store in Data Lake", color="blue")
        >> object_storage
    )

    # 3. Data Processing: Object Storage -> Preprocessing -> Serving
    (
        object_storage
        >> Edge(label="Read & Process\n(Aggregation, Transform)", color="gold")
        >> data_processor
        >> Edge(label="Serve Processed Data", color="gold")
        >> dynamic_api
    )

    # Service Connections
    dynamic_api >> Edge(label="Query raw data") >> collection_db
    dynamic_api >> Edge(label="Access files") >> blob_storage
    apim_server >> Edge(label="APIM metadata") >> collection_db
    auth_server >> Edge(label="User auth") >> collection_db
    scv_service >> Edge(label="Source metadata") >> collection_db

    # Kubernetes Native Monitoring
    api_gateway >> Edge(label="Metrics\n(Prometheus Operator)") >> prometheus
    dynamic_api >> Edge(label="Metrics") >> prometheus
    scv_service >> Edge(label="Metrics") >> prometheus
    apim_server >> Edge(label="Metrics") >> prometheus
    auth_server >> Edge(label="Metrics") >> prometheus
    data_processor >> Edge(label="Metrics") >> prometheus

    prometheus >> Edge(label="Query\n(Grafana Dashboards)") >> grafana
    loki >> Edge(label="Logs\n(Container Logs)") >> grafana

