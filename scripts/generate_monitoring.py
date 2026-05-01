import json
import os

dashboard = {
    "title": "ShopCloud Executive Dashboard",
    "uid": "shopcloud-exec",
    "tags": ["shopcloud", "business", "operations"],
    "timezone": "browser",
    "schemaVersion": 30,
    "refresh": "5s",
    "panels": [
        {
            "type": "stat",
            "title": "Total Revenue",
            "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
            "targets": [{"expr": "sum(shopcloud_revenue_total_total)", "format": "time_series", "refId": "A"}],
            "options": {"colorMode": "value", "graphMode": "area", "justifyMode": "auto", "reduceOptions": {"calcs": ["lastNotNull"]}},
            "fieldConfig": {"defaults": {"unit": "currencyUSD", "color": {"mode": "continuous-GrYlRd"}}}
        },
        {
            "type": "stat",
            "title": "Total Orders Placed",
            "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
            "targets": [{"expr": "sum(shopcloud_orders_total_total)", "format": "time_series", "refId": "A"}],
            "options": {"colorMode": "value", "graphMode": "area", "justifyMode": "auto", "reduceOptions": {"calcs": ["lastNotNull"]}},
            "fieldConfig": {"defaults": {"color": {"mode": "continuous-BlPu"}}}
        },
        {
            "type": "stat",
            "title": "Cart Items Added",
            "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
            "targets": [{"expr": "sum(shopcloud_cart_items_added_total_total)", "format": "time_series", "refId": "A"}],
            "options": {"colorMode": "value", "graphMode": "area", "justifyMode": "auto", "reduceOptions": {"calcs": ["lastNotNull"]}},
            "fieldConfig": {"defaults": {"color": {"mode": "continuous-BlYlRd"}}}
        },
        {
            "type": "stat",
            "title": "Successful Logins",
            "gridPos": {"h": 4, "w": 6, "x": 18, "y": 0},
            "targets": [{"expr": "sum(shopcloud_logins_total_total)", "format": "time_series", "refId": "A"}],
            "options": {"colorMode": "value", "graphMode": "area", "justifyMode": "auto", "reduceOptions": {"calcs": ["lastNotNull"]}},
            "fieldConfig": {"defaults": {"color": {"mode": "continuous-GrYlRd"}}}
        },
        {
            "type": "timeseries",
            "title": "Global Request Rate (req/sec)",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
            "targets": [{"expr": "sum(rate(http_requests_total[1m])) by (app)", "format": "time_series", "refId": "A", "legendFormat": "{{app}}"}],
            "fieldConfig": {"defaults": {"custom": {"lineWidth": 2, "fillOpacity": 15, "gradientMode": "opacity"}, "unit": "reqps"}}
        },
        {
            "type": "timeseries",
            "title": "HTTP 5xx Error Rate",
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
            "targets": [{"expr": "sum(rate(http_requests_total{status=~\"5..\"}[1m])) by (app)", "format": "time_series", "refId": "A", "legendFormat": "{{app}}"}],
            "fieldConfig": {"defaults": {"color": {"mode": "fixed", "fixedColor": "red"}, "custom": {"lineWidth": 2, "fillOpacity": 20}, "unit": "reqps"}}
        },
        {
            "type": "timeseries",
            "title": "P99 Latency by Service",
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 12},
            "targets": [{"expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, app))", "format": "time_series", "refId": "A", "legendFormat": "{{app}}"}],
            "fieldConfig": {"defaults": {"unit": "s", "custom": {"lineWidth": 2, "fillOpacity": 10}}}
        }
    ]
}

dashboard_json = json.dumps(dashboard, indent=2)

configmap = f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: shopcloud-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  shopcloud.json: |-
{chr(10).join('    ' + line for line in dashboard_json.split(chr(10)))}
"""

servicemonitor = """apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: shopcloud-services
  namespace: shopcloud
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      environment: production
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
"""

monitoring_dir = r"c:\Users\Hussein\Desktop\shopcloud\k8s\base\monitoring"
os.makedirs(monitoring_dir, exist_ok=True)

with open(os.path.join(monitoring_dir, "dashboard.yaml"), "w") as f:
    f.write(configmap)

with open(os.path.join(monitoring_dir, "servicemonitor.yaml"), "w") as f:
    f.write(servicemonitor)

print("Created monitoring manifests.")
