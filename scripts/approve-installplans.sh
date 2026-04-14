#!/usr/bin/env bash
#
# approve-installplans.sh
#
# installPlanApproval: Manual の Subscription に対して生成された
# 未承認の InstallPlan を一括承認するスクリプト。
#
# 使い方:
#   ./scripts/approve-installplans.sh          # 全 namespace の未承認 InstallPlan を承認
#   ./scripts/approve-installplans.sh --dry-run # 承認対象の確認のみ (変更なし)
#
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

echo "=== Searching for unapproved InstallPlans ==="

# 未承認の InstallPlan を取得 (namespace/name 形式)
pending=$(oc get installplan -A -o json \
  | jq -r '.items[]
    | select(.spec.approved == false)
    | "\(.metadata.namespace)/\(.metadata.name) \(.spec.clusterServiceVersionNames[0])"')

if [[ -z "$pending" ]]; then
  echo "No unapproved InstallPlans found."
  exit 0
fi

echo ""
echo "Found unapproved InstallPlans:"
echo "------------------------------"
echo "$pending" | while read -r entry csv; do
  ns="${entry%%/*}"
  name="${entry##*/}"
  printf "  %-50s  %s/%s\n" "$csv" "$ns" "$name"
done
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] No changes made."
  exit 0
fi

echo "Approving..."
echo "$pending" | while read -r entry _csv; do
  ns="${entry%%/*}"
  name="${entry##*/}"
  oc patch installplan "$name" -n "$ns" \
    --type merge -p '{"spec":{"approved":true}}'
  echo "  Approved: $ns/$name"
done

echo ""
echo "=== Done. Waiting for Operators to install... ==="
echo ""

# 承認後、CSV が Succeeded になるまで待機 (最大 5 分)
echo "Checking CSV status (timeout: 5m)..."
timeout=300
interval=10
elapsed=0

while (( elapsed < timeout )); do
  not_ready=$(oc get csv -A -o json \
    | jq -r '.items[]
      | select(.status.phase != "Succeeded")
      | "\(.metadata.namespace)/\(.metadata.name): \(.status.phase)"')

  if [[ -z "$not_ready" ]]; then
    echo "All CSVs are Succeeded."
    break
  fi

  echo "  Waiting... (${elapsed}s/${timeout}s)"
  echo "$not_ready" | head -5 | sed 's/^/    /'
  sleep "$interval"
  elapsed=$(( elapsed + interval ))
done

if (( elapsed >= timeout )); then
  echo "WARNING: Timed out waiting for CSVs. Check manually:"
  echo "  oc get csv -A"
fi
