#!/bin/bash
# =============================================================================
# Build admin console image and mirror all operator images to ECR
#
# Run this BEFORE terraform apply to ensure all container images are available.
#
# Usage:
#   # Global region (builds admin console, pushes to ECR)
#   bash build-and-mirror.sh --region us-west-2 --name openclaw-prod
#
#   # China region (builds admin console + mirrors ALL operator images to China ECR)
#   bash build-and-mirror.sh --region cn-northwest-1 --name openclaw-cn --profile china
#
#   # Repeat run (skip images already in ECR)
#   bash build-and-mirror.sh --region cn-northwest-1 --name openclaw-cn --profile china --skip-build
#
#   # Force re-mirror all images (even if they exist in ECR)
#   bash build-and-mirror.sh --region cn-northwest-1 --name openclaw-cn --profile china --mirror
#
#   # Global region with forced mirror (e.g. private ECR for air-gapped clusters)
#   bash build-and-mirror.sh --region us-west-2 --name openclaw-prod --mirror
#
#   # Build only, no mirror
#   bash build-and-mirror.sh --region us-west-2 --name openclaw-prod --no-mirror
#
# Flags:
#   --region      AWS region (default: us-west-2)
#   --name        Resource name prefix (default: openclaw-eks)
#   --profile     AWS CLI profile (required for China)
#   --skip-build  Skip Docker image build
#   --mirror      Force mirror all images (even in global regions or if already in ECR)
#   --no-mirror   Never mirror (even in China)
#   --platform    Target platform (e.g. linux/arm64) for cross-arch builds
#
# Prerequisites:
#   - Docker running locally
#   - AWS CLI configured (with --profile for China)
#   - Internet access to ghcr.io and Docker Hub (for mirror source)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[info]${NC}  $*"; }
success() { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

REGION="us-west-2"
NAME="openclaw-eks"
AWS_PROFILE_ARG=""
SKIP_BUILD=false
MIRROR_MODE="auto"  # auto | always | never
PLATFORM=""          # e.g. linux/arm64 for cross-arch builds

# Operator version — keep in sync with eks/terraform/modules/operator/variables.tf
OPERATOR_VERSION="0.26.2"

while [[ $# -gt 0 ]]; do
  case $1 in
    --region)      REGION="$2"; shift 2 ;;
    --name)        NAME="$2"; shift 2 ;;
    --profile)     AWS_PROFILE_ARG="--profile $2"; export AWS_PROFILE="$2"; shift 2 ;;
    --skip-build)  SKIP_BUILD=true; shift ;;
    --mirror)      MIRROR_MODE="always"; shift ;;
    --no-mirror)   MIRROR_MODE="never"; shift ;;
    --skip-mirror) MIRROR_MODE="never"; shift ;;  # backward compat
    --platform)    PLATFORM="$2"; shift 2 ;;
    *) error "Unknown flag: $1" ;;
  esac
done

IS_CHINA=false
[[ "$REGION" == cn-* ]] && IS_CHINA=true

ACCOUNT_ID=$(aws sts get-caller-identity $AWS_PROFILE_ARG --query Account --output text --region "$REGION")
if $IS_CHINA; then
  ECR_HOST="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com.cn"
else
  ECR_HOST="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
fi
ADMIN_ECR="${ECR_HOST}/${NAME}/admin-console"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Build & Mirror — ${NAME} (${REGION})"
echo "  Account: ${ACCOUNT_ID}"
echo "  ECR Host: ${ECR_HOST}"
echo "  China: ${IS_CHINA}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── ECR Login ──────────────────────────────────────────────────
info "Logging in to ECR (Docker + Helm)..."
ECR_PASSWORD=$(aws ecr get-login-password $AWS_PROFILE_ARG --region "$REGION")
echo "$ECR_PASSWORD" | docker login --username AWS --password-stdin "$ECR_HOST" 2>/dev/null
echo "$ECR_PASSWORD" | helm registry login "$ECR_HOST" --username AWS --password-stdin 2>/dev/null
unset ECR_PASSWORD
success "ECR login"

# ── Create admin console ECR repo ──────────────────────────────
info "Ensuring ECR repo: ${NAME}/admin-console"
aws ecr create-repository $AWS_PROFILE_ARG \
  --repository-name "${NAME}/admin-console" \
  --region "$REGION" 2>/dev/null || true

# ── Build admin console Docker image ──────────────────────────
if ! $SKIP_BUILD; then
  info "Building admin console Docker image..."
  cd "$REPO_ROOT/enterprise/admin-console"
  if [[ -n "$PLATFORM" ]]; then
    info "Cross-platform build: $PLATFORM (using buildx)"
    docker buildx build --platform "$PLATFORM" -t "$ADMIN_ECR:latest" --push .
  else
    docker build -t "$ADMIN_ECR:latest" .
    info "Pushing to $ADMIN_ECR:latest..."
    docker push "$ADMIN_ECR:latest"
  fi
  success "Admin console image pushed"
else
  warn "Skipping build (--skip-build)"
fi

# ── Mirror container images (required for China, optional for global) ──
# ALL images from registries blocked in China (ghcr.io, docker.io, quay.io,
# registry.k8s.io). The ECR path preserves the upstream org/repo structure
# so spec.registry CRD rewriting works correctly.

MIRROR_IMAGES=(
  # ── OpenClaw Operator workload images ──
  # Core — always needed for OpenClawInstance pods
  "ghcr.io/openclaw/openclaw:latest|openclaw/openclaw:latest"
  "ghcr.io/astral-sh/uv:0.6-bookworm-slim|astral-sh/uv:0.6-bookworm-slim"
  "busybox:1.37|library/busybox:1.37"
  "nginx:1.27-alpine|library/nginx:1.27-alpine"
  "otel/opentelemetry-collector:0.120.0|otel/opentelemetry-collector:0.120.0"
  # Sidecars — needed when enabled in CRD spec
  "chromedp/headless-shell:stable|chromedp/headless-shell:stable"
  "ghcr.io/tailscale/tailscale:latest|tailscale/tailscale:latest"
  "ollama/ollama:latest|ollama/ollama:latest"
  "tsl0922/ttyd:latest|tsl0922/ttyd:latest"
  # Backup/restore — needed when spec.backup is configured
  "rclone/rclone:1.68|rclone/rclone:1.68"

  # ── Operator controller ──
  "ghcr.io/openclaw-rocks/openclaw-operator:v${OPERATOR_VERSION}|openclaw-rocks/openclaw-operator:v${OPERATOR_VERSION}"

  # ── Kata Containers (optional: enable_kata) ──
  "quay.io/kata-containers/kata-deploy:3.27.0|kata-containers/kata-deploy:3.27.0"

  # ── LiteLLM (optional: enable_litellm) ──
  "docker.litellm.ai/berriai/litellm:main-latest|berriai/litellm:main-latest"

  # ── Monitoring stack (optional: enable_monitoring) ──
  # Grafana
  "grafana/grafana:11.2.1|grafana/grafana:11.2.1"
  "quay.io/kiwigrid/k8s-sidecar:1.27.4|kiwigrid/k8s-sidecar:1.27.4"
  # kube-prometheus-stack
  "quay.io/prometheus/prometheus:v2.54.1|prometheus/prometheus:v2.54.1"
  "quay.io/prometheus-operator/prometheus-operator:v0.77.1|prometheus-operator/prometheus-operator:v0.77.1"
  "quay.io/prometheus-operator/prometheus-config-reloader:v0.77.1|prometheus-operator/prometheus-config-reloader:v0.77.1"
  "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20221220-controller-v1.5.1-58-g787ea74b6|ingress-nginx/kube-webhook-certgen:v20221220-controller-v1.5.1-58-g787ea74b6"
  "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0|kube-state-metrics/kube-state-metrics:v2.13.0"
  "quay.io/prometheus/node-exporter:1.8.2|prometheus/node-exporter:1.8.2"
)

# Decide whether to mirror
DO_MIRROR=false
if [[ "$MIRROR_MODE" == "always" ]]; then
  DO_MIRROR=true
elif [[ "$MIRROR_MODE" == "never" ]]; then
  DO_MIRROR=false
else
  # auto: mirror for China, skip for global
  $IS_CHINA && DO_MIRROR=true
fi

if $DO_MIRROR; then
  info "Mirroring ${#MIRROR_IMAGES[@]} images to ECR ($ECR_HOST)..."
  echo ""

  MIRROR_FAIL=0
  MIRROR_SKIP=0
  MIRROR_PUSH=0
  for entry in "${MIRROR_IMAGES[@]}"; do
    SRC="${entry%%|*}"
    DST_PATH="${entry##*|}"
    DST="${ECR_HOST}/${DST_PATH}"
    DST_REPO="${DST_PATH%%:*}"
    DST_TAG="${DST_PATH##*:}"

    printf "  %-55s → " "$SRC"

    # Create repo (idempotent)
    aws ecr create-repository $AWS_PROFILE_ARG \
      --repository-name "$DST_REPO" \
      --region "$REGION" 2>/dev/null || true

    # Check if image already exists in ECR (skip if present, unless --mirror forces re-push)
    if [[ "$MIRROR_MODE" != "always" ]]; then
      EXISTING=$(aws ecr describe-images $AWS_PROFILE_ARG \
        --repository-name "$DST_REPO" \
        --image-ids imageTag="$DST_TAG" \
        --region "$REGION" --query 'imageDetails[0].imagePushedAt' --output text 2>/dev/null || echo "")
      if [[ -n "$EXISTING" && "$EXISTING" != "None" ]]; then
        echo -e "${CYAN}EXISTS${NC} (pushed ${EXISTING})"
        MIRROR_SKIP=$((MIRROR_SKIP + 1))
        continue
      fi
    fi

    # Pull (with optional platform override for cross-arch)
    PULL_ARGS=""
    [[ -n "$PLATFORM" ]] && PULL_ARGS="--platform $PLATFORM"
    if ! docker pull $PULL_ARGS "$SRC" > /dev/null 2>&1; then
      echo -e "${RED}PULL FAILED${NC}"
      MIRROR_FAIL=$((MIRROR_FAIL + 1))
      continue
    fi

    # Tag + push
    docker tag "$SRC" "$DST"
    if docker push "$DST" > /dev/null 2>&1; then
      echo -e "${GREEN}PUSHED${NC}"
      MIRROR_PUSH=$((MIRROR_PUSH + 1))
    else
      echo -e "${RED}PUSH FAILED${NC}"
      MIRROR_FAIL=$((MIRROR_FAIL + 1))
    fi
  done

  echo ""
  if [[ $MIRROR_FAIL -eq 0 ]]; then
    success "Mirror done: ${MIRROR_PUSH} pushed, ${MIRROR_SKIP} skipped (already exist), ${MIRROR_FAIL} failed"
  else
    warn "Mirror done: ${MIRROR_PUSH} pushed, ${MIRROR_SKIP} skipped, ${MIRROR_FAIL} FAILED"
  fi
else
  if [[ "$MIRROR_MODE" == "never" ]]; then
    info "Image mirror skipped (--no-mirror)"
  else
    info "Global region — image mirror not needed (use --mirror to force)"
  fi
fi

# ── Mirror Helm charts (OCI artifacts) ────────────────────────
# Terraform helm_release resources pull charts from registries that are
# inaccessible from China. Mirror them to ECR so terraform can use
# oci://${ECR_HOST}/charts as the repository override.

MIRROR_CHARTS=(
  # Required — OpenClaw Operator (always deployed)
  "oci://ghcr.io/openclaw-rocks/charts|openclaw-operator|${OPERATOR_VERSION}"
  # Optional — uncomment if using these Terraform modules in China:
  # "oci://ghcr.io/kata-containers/kata-deploy-charts|kata-deploy|3.27.0"
  # "oci://ghcr.io/berriai/litellm-helm|litellm-helm|"
)

# Monitoring/Grafana charts are from HTTPS repos (not OCI). Pull as OCI from
# the repos, convert, and push to ECR. Handled separately below.
MIRROR_HTTPS_CHARTS=(
  # "prometheus-community|https://prometheus-community.github.io/helm-charts|kube-prometheus-stack|65.1.0"
  # "grafana|https://grafana.github.io/helm-charts|grafana|"
)

if $DO_MIRROR; then
  info "Mirroring Helm charts to ECR ($ECR_HOST)..."
  echo ""
  CHART_DIR=$(mktemp -d)
  CHART_FAIL=0
  CHART_PUSH=0

  for entry in "${MIRROR_CHARTS[@]}"; do
    [[ "$entry" == \#* ]] && continue
    IFS='|' read -r REPO CHART VERSION <<< "$entry"
    printf "  %-55s → " "${REPO}/${CHART}:${VERSION}"

    # Pull chart from ghcr.io
    if ! helm pull "${REPO}/${CHART}" --version "$VERSION" --destination "$CHART_DIR" 2>/dev/null; then
      echo -e "${RED}PULL FAILED${NC}"
      CHART_FAIL=$((CHART_FAIL + 1))
      continue
    fi

    # Create ECR repo for the chart
    aws ecr create-repository $AWS_PROFILE_ARG \
      --repository-name "charts/${CHART}" \
      --region "$REGION" 2>/dev/null || true

    # Push to ECR as OCI artifact
    CHART_FILE=$(ls "$CHART_DIR/${CHART}"-*.tgz 2>/dev/null | sort -V | tail -1)
    if [[ -n "$CHART_FILE" ]] && helm push "$CHART_FILE" "oci://${ECR_HOST}/charts" 2>/dev/null; then
      echo -e "${GREEN}PUSHED${NC}"
      CHART_PUSH=$((CHART_PUSH + 1))
    else
      echo -e "${RED}PUSH FAILED${NC}"
      CHART_FAIL=$((CHART_FAIL + 1))
    fi
    rm -f "$CHART_FILE"
  done

  rm -rf "$CHART_DIR"
  echo ""
  if [[ $CHART_FAIL -eq 0 ]]; then
    success "Chart mirror done: ${CHART_PUSH} pushed, ${CHART_FAIL} failed"
  else
    warn "Chart mirror done: ${CHART_PUSH} pushed, ${CHART_FAIL} FAILED"
  fi

  # Mirror HTTPS-repo charts (monitoring, grafana)
  for entry in "${MIRROR_HTTPS_CHARTS[@]}"; do
    [[ "$entry" == \#* ]] && continue
    IFS='|' read -r REPO_NAME REPO_URL CHART VERSION <<< "$entry"
    printf "  %-55s → " "${REPO_URL} ${CHART}:${VERSION:-latest}"
    CHART_DIR2=$(mktemp -d)
    helm repo add "$REPO_NAME" "$REPO_URL" --force-update > /dev/null 2>&1
    PULL_ARGS="$REPO_NAME/$CHART"
    [[ -n "$VERSION" ]] && PULL_ARGS="$PULL_ARGS --version $VERSION"
    if ! helm pull $PULL_ARGS --destination "$CHART_DIR2" 2>/dev/null; then
      echo -e "${RED}PULL FAILED${NC}"
      continue
    fi
    aws ecr create-repository $AWS_PROFILE_ARG \
      --repository-name "charts/${CHART}" \
      --region "$REGION" 2>/dev/null || true
    CHART_FILE=$(ls "$CHART_DIR2/${CHART}"-*.tgz 2>/dev/null | sort -V | tail -1)
    if [[ -n "$CHART_FILE" ]] && helm push "$CHART_FILE" "oci://${ECR_HOST}/charts" 2>/dev/null; then
      echo -e "${GREEN}PUSHED${NC}"
    else
      echo -e "${RED}PUSH FAILED${NC}"
    fi
    rm -rf "$CHART_DIR2"
  done
fi

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}Done!${NC}"
echo ""
echo "  Admin Console: ${ADMIN_ECR}:latest"
if $IS_CHINA; then
  echo "  Registry:      ${ECR_HOST}"
  echo ""
  echo "  When deploying OpenClaw instances, set:"
  echo "    globalRegistry: ${ECR_HOST}"
  echo ""
  echo "  Helm chart repo for Terraform (operator/kata/litellm):"
  echo "    chart_repository = \"oci://${ECR_HOST}/charts\""
fi
echo ""
echo "  Next: run terraform apply"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
