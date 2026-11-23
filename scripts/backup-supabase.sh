#!/usr/bin/env bash
# 牛室 ERP · Supabase 数据备份：导出 erp_store(全部业务/薪资/会计数据) 和 erp_users(白名单)，
# 压成一个 JSON，再用口令加密成 .gpg。明文只在运行机器的临时目录里，加密后立刻删除。
# 需要环境变量（由 GitHub Actions 的 Secrets 提供，绝不能写进仓库）：
#   SUPABASE_URL  SUPABASE_KEY(service 密钥)  BACKUP_PASSPHRASE(加密口令)
set -euo pipefail

: "${SUPABASE_URL:?缺少 SUPABASE_URL}"
: "${SUPABASE_KEY:?缺少 SUPABASE_SERVICE_KEY：请先在 GitHub → Settings → Secrets and variables → Actions 添加}"
: "${BACKUP_PASSPHRASE:?缺少 BACKUP_PASSPHRASE：请先在 GitHub Secrets 添加}"

OUT_DIR="${OUT_DIR:-backup}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT_DIR"

hdr=(-H "apikey: $SUPABASE_KEY")
case "$SUPABASE_KEY" in eyJ*) hdr+=(-H "Authorization: Bearer $SUPABASE_KEY");; esac

# 表名:排序栏位（分页时要有稳定的顺序）
TABLES=("erp_store:key" "erp_users:email")
PAGE=25   # erp_store 每行可能很大，一页少拿一点

fetch_table() {
  local table="$1" order="$2" off=0 n
  : > "$TMP/$table.ndjson"
  while :; do
    curl -sS --fail-with-body --max-time 180 --retry 3 --retry-delay 5 \
      "${hdr[@]}" \
      "$SUPABASE_URL/rest/v1/$table?select=*&order=$order.asc&limit=$PAGE&offset=$off" \
      -o "$TMP/page.json"
    n="$(jq 'if type=="array" then length else error("回应不是数组") end' "$TMP/page.json")"
    jq -c '.[]' "$TMP/page.json" >> "$TMP/$table.ndjson"
    off=$((off + n))
    [ "$n" -lt "$PAGE" ] && break
  done
  jq -s '.' "$TMP/$table.ndjson" > "$TMP/$table.json"
  echo "  $table: $(jq 'length' "$TMP/$table.json") 行"
}

echo "开始导出…"
for t in "${TABLES[@]}"; do fetch_table "${t%%:*}" "${t##*:}"; done

# 安全检查：erp_store 一行都没有，多半是出了问题，宁可让这次运行变红，也不要存一份空备份
rows="$(jq 'length' "$TMP/erp_store.json")"
if [ "$rows" -lt 1 ]; then
  echo "::error::erp_store 是空的，这份备份不可信（可能是密钥不对或权限问题），已中止。"
  exit 1
fi

stamp="$(date -u +%Y%m%d-%H%M%S)"
jq -n --arg at "$(date -u +%FT%TZ)" \
  --slurpfile store "$TMP/erp_store.json" --slurpfile users "$TMP/erp_users.json" \
  '{exported_at:$at, project:"beefhouse", tables:{erp_store:$store[0], erp_users:$users[0]}}' \
  > "$TMP/backup.json"

OUT_FILE="$OUT_DIR/beefhouse-$stamp.json.gpg"
printf '%s' "$BACKUP_PASSPHRASE" | gpg --batch --yes --quiet --pinentry-mode loopback \
  --passphrase-fd 0 --symmetric --cipher-algo AES256 -o "$OUT_FILE" "$TMP/backup.json"

echo "完成：$OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))，erp_store $rows 行"
