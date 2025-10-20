from diagrams import Diagram, Cluster, Edge
from diagrams.azure.compute import VM
from diagrams.azure.database import SQLDatabases
from diagrams.azure.storage import BlobStorage
from diagrams.azure.network import (
    VirtualNetworks,
    LoadBalancers,
    ApplicationGateway,
    VirtualNetworkClassic,
    NetworkSecurityGroupsClassic,
    Subnets,
)
from diagrams.azure.security import KeyVaults
from diagrams.onprem.client import Users
from diagrams.onprem.monitoring import Prometheus, Grafana
from diagrams.onprem.network import Internet

with Diagram(
    "Azure MSA Architecture - Public API Data Collection with Medallion Architecture",
    show=False,
    direction="TB",
    filename="azure_msa_medallion",
    outformat="png",
):
    # External Users
    users = Users("External Users")

    # Internet Gateway
    internet = ApplicationGateway("Internet Gateway")

    with Cluster("Azure Virtual Network"):

        # Load Balancer for API Gateway HA
        lb = LoadBalancers("Azure Load Balancer\n(API Gateway HA)")

        # NAT Gateway for outbound internet access from private subnet
        nat_gateway = Internet("NAT Gateway\n(Outbound Internet)")

        with Cluster("Public Subnet (DMZ)"):
            # API Gateway in Public Subnet (Multiple instances for HA)
            api_gateway = VM("API Gateway\n(Spring Cloud Gateway)\nVM Scale Set")
            nsg_public = NetworkSecurityGroupsClassic("NSG - Public\n(Port 80,443)")

        with Cluster("Private Subnet"):
            nsg_private = NetworkSecurityGroupsClassic("NSG - Private\n(Internal only)")

            # Core Microservices
            dynamic_api = VM("Dynamic API\n(Spring Boot)\nVM")
            scv_service = VM("SCV Service\n(Data Collection)\nVM")
            apim_server = VM("APIM Server\n(APIM CRUD)\nVM")
            auth_server = VM("Auth Server\nVM")

            # Data Processing Service (for medallion architecture)
            data_processor = VM("Data Processor\n(ETL Service)\nVM")

            # Monitoring Stack (Independent)
            with Cluster("Monitoring Stack (Independent)"):
                prometheus = VM("Prometheus\nVM")
                grafana = VM("Grafana\nVM")
                loki = VM("Loki\nVM")

    # Medallion Architecture - Data Storage Layers
    with Cluster("Medallion Architecture - Data Layers"):
        with Cluster("Bronze Layer (Staging)"):
            staging_storage = BlobStorage(
                "Azure Blob Storage\n(Raw Data - Bronze)\nStaging Layer"
            )

        with Cluster("Silver Layer (Processed)"):
            collection_db = SQLDatabases(
                "Collection DB\n(Processed Data - Silver)\nCleaned & Validated"
            )

        with Cluster("Gold Layer (Refined)"):
            public_db = SQLDatabases(
                "Public API DB\n(Refined Data - Gold)\nBusiness Ready"
            )

    with Cluster("Azure Database Services"):
        # Application Metadata Database
        metadata_db = SQLDatabases(
            "Metadata DB\n(Application Metadata)\nSchemas, Lineage, Config"
        )

    with Cluster("Azure Storage & Security"):
        blob_storage = BlobStorage("Azure Blob Storage\n(Files, Logs, Assets)")
        key_vault = KeyVaults("Azure Key Vault\n(Secrets, Keys)")

    # External Data Sources
    external_api = Users("Public Data APIs\n(External)")

    # Main Traffic Flow
    (
        users
        >> Edge(label="HTTPS")
        >> internet
        >> Edge(label="Load Balance")
        >> lb
        >> Edge(label="Route")
        >> api_gateway
    )

    # API Gateway to Private Services (Internal Load Balancing)
    api_gateway >> Edge(label="Internal API") >> dynamic_api
    api_gateway >> Edge(label="Auth") >> auth_server
    api_gateway >> Edge(label="APIM CRUD") >> apim_server

    # Medallion Architecture Data Flow
    # Bronze Layer: Raw Data Collection
    (
        external_api
        >> Edge(label="Data Collection\n(via NAT Gateway)")
        >> nat_gateway
        >> scv_service
        >> Edge(label="Store Raw Data\n(Bronze Layer)", color="orange")
        >> staging_storage
    )

    # Silver Layer: Data Processing
    (
        staging_storage
        >> Edge(label="ETL Process\n(Clean & Validate)", color="blue")
        >> data_processor
        >> Edge(label="Store Processed\n(Silver Layer)", color="blue")
        >> collection_db
    )

    # Gold Layer: Business Ready Data
    (
        collection_db
        >> Edge(label="Data Refinement\n(Business Logic)", color="gold")
        >> data_processor
        >> Edge(label="Store Refined\n(Gold Layer)", color="gold")
        >> public_db
    )

    # Service Database Connections
    dynamic_api >> Edge(label="Query public data") >> public_db
    dynamic_api >> Edge(label="Access files") >> blob_storage
    apim_server >> Edge(label="APIM metadata") >> metadata_db
    auth_server >> Edge(label="User auth") >> metadata_db

    # Metadata Management
    data_processor >> Edge(label="Data Lineage\n& Schema Info") >> metadata_db
    scv_service >> Edge(label="Source Metadata") >> metadata_db
    dynamic_api >> Edge(label="API Metadata") >> metadata_db

    # Independent Monitoring (No external dependencies)
    api_gateway >> Edge(label="Metrics") >> prometheus
    dynamic_api >> Edge(label="Metrics") >> prometheus
    scv_service >> Edge(label="Metrics") >> prometheus
    apim_server >> Edge(label="Metrics") >> prometheus
    auth_server >> Edge(label="Metrics") >> prometheus
    data_processor >> Edge(label="Metrics") >> prometheus

    prometheus >> Edge(label="Query") >> grafana
    loki >> Edge(label="Logs") >> grafana

    # Security & Configuration
    auth_server >> Edge(label="Secrets") >> key_vault
    api_gateway >> Edge(label="SSL Certs") >> key_vault
    data_processor >> Edge(label="DB Credentials") >> key_vault
