# RHDH 構成改善 TODO

## レビュー指摘事項

- [x] 1. apiVersion を `rhdh.redhat.com/v1alpha3` → `rhdh.redhat.com/v1alpha4` に更新
  - ref: https://access.redhat.com/documentation/en-us/red_hat_developer_hub/1.8/html-single/configuring_red_hat_developer_hub/index
- [x] 2. replicas を 2 以上に変更 (本番向け HA 構成)
  - `components/ha/` として作成、hub overlay から参照
  - ref: https://access.redhat.com/documentation/en-us/red_hat_developer_hub/1.9/html-single/about_red_hat_developer_hub/index
- [x] 3. resource requests/limits を deployment.patch で明示設定
  - Small-scale 向け: requests cpu=500m/memory=1Gi, limits cpu=2/memory=4Gi
  - ref: https://access.redhat.com/solutions/7078954
- [ ] 4. 外部 PostgreSQL の検討 (本番時)
  - 現状は `enableLocalDb: true` で PoC 向け。本番移行時に component として切替
  - ref: https://access.redhat.com/documentation/en-us/red_hat_developer_hub/1.6/html-single/configuring_red_hat_developer_hub/index
- [ ] 5. 認証プロバイダの設定 (公開前に対応)
  - `components/disable-guest/` を作成済み。IdP 準備後に overlay から参照を追加
  - ref: https://access.redhat.com/documentation/en-us/red_hat_developer_hub/1.9/html-single/authentication_in_red_hat_developer_hub/index

## 判断済み

- Infra ノード対応: **対象外** (RHDH はエンドユーザー向けアプリのため worker で動かすべき)
  - ref: https://access.redhat.com/solutions/5034771
