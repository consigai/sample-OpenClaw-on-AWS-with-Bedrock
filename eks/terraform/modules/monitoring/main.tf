################################################################################
# Monitoring Module - Prometheus + Grafana via kube-prometheus-stack
################################################################################

locals {
  # Image registry: use private ECR mirror for China, upstream for global
  img = var.ecr_host != "" ? var.ecr_host : ""

  prometheus_image     = var.ecr_host != "" ? "${var.ecr_host}/prometheus/prometheus" : "quay.io/prometheus/prometheus"
  prom_operator_image  = var.ecr_host != "" ? "${var.ecr_host}/prometheus-operator/prometheus-operator" : "quay.io/prometheus-operator/prometheus-operator"
  config_reloader_image = var.ecr_host != "" ? "${var.ecr_host}/prometheus-operator/prometheus-config-reloader" : "quay.io/prometheus-operator/prometheus-config-reloader"
  webhook_certgen_image = var.ecr_host != "" ? "${var.ecr_host}/ingress-nginx/kube-webhook-certgen" : "registry.k8s.io/ingress-nginx/kube-webhook-certgen"
  kube_state_image     = var.ecr_host != "" ? "${var.ecr_host}/kube-state-metrics/kube-state-metrics" : "registry.k8s.io/kube-state-metrics/kube-state-metrics"
  node_exporter_image  = var.ecr_host != "" ? "${var.ecr_host}/prometheus/node-exporter" : "quay.io/prometheus/node-exporter"
  grafana_image        = var.ecr_host != "" ? "${var.ecr_host}/grafana/grafana" : "docker.io/grafana/grafana"
  sidecar_image        = var.ecr_host != "" ? "${var.ecr_host}/kiwigrid/k8s-sidecar" : "quay.io/kiwigrid/k8s-sidecar"
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = var.cluster_name
    }
  }
}

################################################################################
# Grafana admin password
################################################################################

resource "random_password" "grafana_admin" {
  length  = 16
  special = true
}

################################################################################
# kube-prometheus-stack (Prometheus + Operator + exporters)
################################################################################

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = var.chart_repository != "" ? var.chart_repository : "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "65.1.0"

  timeout = 600

  values = [
    yamlencode({
      # ----------------------------------------------------------------
      # Prometheus Server
      # ----------------------------------------------------------------
      prometheus = {
        prometheusSpec = {
          image = {
            registry   = ""
            repository = local.prometheus_image
            tag        = "v2.54.1"
          }
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "ebs-sc"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }
          retention = "15d"
          resources = {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
          # Enable ServiceMonitor auto-discovery across all namespaces
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false
        }
      }

      # ----------------------------------------------------------------
      # Prometheus Operator
      # ----------------------------------------------------------------
      prometheusOperator = {
        image = {
          registry   = ""
          repository = local.prom_operator_image
          tag        = "v0.77.1"
        }
        prometheusConfigReloader = {
          image = {
            registry   = ""
            repository = local.config_reloader_image
            tag        = "v0.77.1"
          }
        }
        admissionWebhooks = {
          patch = {
            image = {
              registry   = ""
              repository = local.webhook_certgen_image
              tag        = "v20221220-controller-v1.5.1-58-g787ea74b6"
            }
          }
        }
      }

      # ----------------------------------------------------------------
      # kube-state-metrics
      # ----------------------------------------------------------------
      kube-state-metrics = {
        image = {
          registry   = ""
          repository = local.kube_state_image
          tag        = "v2.13.0"
        }
      }

      # ----------------------------------------------------------------
      # node-exporter
      # ----------------------------------------------------------------
      prometheus-node-exporter = {
        image = {
          registry   = ""
          repository = local.node_exporter_image
          tag        = "1.8.2"
        }
      }

      # ----------------------------------------------------------------
      # Disable Grafana inside the stack -- we deploy it separately below
      # so we can configure datasources, persistence, and sidecar images.
      # ----------------------------------------------------------------
      grafana = {
        enabled = false
      }

      # Alertmanager disabled -- users can enable it via a wrapper variable
      # in a future iteration.
      alertmanager = {
        enabled = false
      }
    })
  ]
}

################################################################################
# Grafana (standalone Helm release)
################################################################################

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = var.chart_repository != "" ? var.chart_repository : "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  timeout = 600

  values = [
    yamlencode({
      image = {
        registry   = ""
        repository = local.grafana_image
        tag        = "11.2.1"
      }

      # chown init container is not needed when running as non-root with
      # a PVC that has the correct fsGroup set.
      initChownData = {
        enabled = false
      }

      sidecar = {
        image = {
          registry   = ""
          repository = local.sidecar_image
          tag        = "1.27.4"
        }
        dashboards = {
          enabled = true
        }
        datasources = {
          enabled = true
        }
      }

      adminPassword = random_password.grafana_admin.result

      persistence = {
        enabled          = true
        storageClassName = "ebs-sc"
        size             = "10Gi"
      }

      service = {
        type = "ClusterIP"
      }

      # Pre-configure Prometheus as the default datasource so Grafana is
      # immediately usable after deployment.
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [{
            name      = "Prometheus"
            type      = "prometheus"
            url       = "http://kube-prometheus-stack-prometheus.${kubernetes_namespace_v1.monitoring.metadata[0].name}:9090"
            isDefault = true
          }]
        }
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}
