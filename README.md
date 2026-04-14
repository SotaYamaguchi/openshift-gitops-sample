# Platform GitOps Repository

OpenShift / ROSA クラスタ群のプラットフォーム構成を GitOps で管理するリポジトリです。

## 設計思想

このリポジトリの構成は、Red Hat の **Gerald Nunn** 氏（Principal Technical Marketing Manager - Kubernetes and GitOps）が公開している [cluster-config-v2](https://github.com/gnunn-gitops/cluster-config-v2) のパターンを基盤としています。

Gerald Nunn 氏は Red Hat で OpenShift GitOps の技術マーケティングを主導し、[Red Hat Developer Blog](https://developers.redhat.com/author/gerald-nunn) にて OpenShift GitOps の公式ガイドやベストプラクティスを多数公開しています。このパターンは Red Hat 社内外で広く採用されており、OpenShift GitOps の実運用における確立されたリファレンスアーキテクチャです。

### 核となる設計判断

#### 1. 分散 ArgoCD（各クラスタが自身のみを管理）

```
┌─────────────────────┐  ┌─────────────────────┐
│ idp-cluster (Hub)   │  │ dev-cluster          │
│  ArgoCD -> self     │  │  ArgoCD -> self      │
│  core/ + hub/       │  │  core/ + workload/   │
└─────────────────────┘  └─────────────────────┘
┌─────────────────────┐  ┌─────────────────────┐
│ stg-cluster         │  │ prod-cluster         │
│  ArgoCD -> self     │  │  ArgoCD -> self      │
│  core/ + workload/  │  │  core/ + workload/   │
└─────────────────────┘  └─────────────────────┘
```

各クラスタの ArgoCD は `https://kubernetes.default.svc` のみをターゲットにします。リモートクラスタの Secret 管理が不要になり、クラスタ間の依存関係を排除できます。中央集権型の ArgoCD Hub と比較して、障害の影響範囲が限定されます。

#### 2. Overlay 名によるスコープ制御

ApplicationSet の Git directory generator が overlay のディレクトリ名を基にアプリケーションを自動検出します。これにより、**新しいコンポーネントを追加する際に ApplicationSet を編集する必要がありません**。

| Overlay 名 | 粒度 | 適用先 |
|---|---|---|
| `all` | 全クラスタ | idp, dev, stg, prod |
| `hub` | クラスタ種別 | idp-cluster のみ |
| `dev-cluster` / `stg-cluster` / `prod-cluster` | クラスタ固有 | 特定クラスタのみ |

Gerald Nunn 氏がこの設計について述べているように、**どのアプリケーションがどのクラスタにデプロイされるかは、シンプルな `ls` コマンドで確認できます**。DRY 原則よりも可読性を重視した設計です。

#### 3. Tier 分類（core / hub / workload）

コンポーネントの配置先は「もう 1 つクラスタを追加したとき、そのコンポーネントも必要か？」で判断します。

- **core/** -- 全クラスタに必要なインフラ（OpenShift GitOps, Pipelines, 監視, RBAC）
- **hub/** -- IDP クラスタのみで必要な管理サービス（Developer Hub, Quay, ACS, TAS, TPA）
- **workload/** -- ワークロードクラスタのみで必要なもの（Service Mesh, アプリケーション）

#### 4. base / components / overlays パターン

全コンポーネントが同一の Kustomize ディレクトリ構造に従います。

```
apps/<tier>/<component>/
├── base/               # コンポーネントの動作に必要な最小リソース
├── components/         # オプション機能 (Kustomize Component)
└── overlays/           # ターゲット別のパッチ・設定
```

- **base/** -- Operator Subscription, CRD インスタンス, Namespace 等
- **components/** -- 有効/無効を選択できる機能モジュール（例: ArgoCD の notifications, ha, monitoring）
- **overlays/** -- クラスタ固有の設定やオプション機能の組み合わせ

#### 5. Kustomize Components による機能の組み合わせ

`openshift-gitops` コンポーネントは、base を最小構成にし、3つの Component で環境ごとに異なる機能セットを構成するサンプルです。

```
apps/core/openshift-gitops/
├── base/argocd.yaml                   # 全機能 disabled の最小構成
├── components/
│   ├── notifications/                 # Sync 通知の有効化
│   ├── ha/                            # HA 構成 (controller sharding)
│   └── monitoring/                    # Prometheus メトリクス収集
└── overlays/
    ├── dev-cluster/                   # notifications
    ├── stg-cluster/                   # notifications + monitoring
    ├── prod-cluster/                  # notifications + ha + monitoring
    └── idp-cluster/                   # notifications + monitoring
```

#### 6. Sync Wave による Operator と CR の適用順序制御

Operator の Subscription と Custom Resource (CR) を同一の Application で管理する場合、以下の仕組みで適用順序を制御します。

- **sync-wave "0"** (デフォルト): Namespace, OperatorGroup, Subscription
- **sync-wave "1"**: Operator の CR (Central, QuayRegistry, Backstage 等)
- **SkipDryRunOnMissingResource**: CRD 未登録時の dry-run エラーを回避
- **Subscription health check**: Operator の CSV がインストールされるまで Progressing として待機
- **retry with backoff**: 一時的な失敗を自動リトライ

## リポジトリ構成

```
.
├── bootstrap/          # ArgoCD のインストールと ApplicationSet の適用
├── apps/               # プラットフォームコンポーネント定義
│   ├── core/           #   全クラスタ共通インフラ
│   ├── hub/            #   IDP クラスタ専用
│   └── workload/       #   ワークロードクラスタ専用
├── clusters/           # クラスタ別 ApplicationSet
├── components/         # リポジトリ共有 Kustomize Components
└── docs/               # ドキュメント
```

## クラスタ構成

| クラスタ | 役割 | Tier |
|---|---|---|
| idp-cluster | Hub クラスタ。Developer Hub, Quay, ACS 等の管理サービスをホスト | core + hub |
| dev-cluster | 開発環境ワークロード | core + workload |
| stg-cluster | ステージング環境ワークロード | core + workload |
| prod-cluster | 本番環境ワークロード | core + workload |

## プラットフォームコンポーネント

### core/（全クラスタ共通）

| コンポーネント | Operator | 用途 |
|---|---|---|
| openshift-gitops | OpenShift GitOps Operator | ArgoCD - GitOps デプロイメント自動化 |
| openshift-pipelines | OpenShift Pipelines Operator | Tekton - CI/CD パイプライン基盤 |
| cluster-monitoring | - | クラスタ監視設定 |
| rbac | - | プラットフォーム RBAC |

### hub/（IDP クラスタ専用）

| コンポーネント | Operator | 用途 |
|---|---|---|
| rhacs | RHACS Operator | Advanced Cluster Security - コンテナセキュリティ |
| quay | Quay Operator | Red Hat Quay - コンテナレジストリ |
| rhdh | RHDH Operator | Red Hat Developer Hub - 開発者ポータル |
| rhtas | RHTAS Operator | Trusted Artifact Signer - イメージ署名・検証 |
| rhtpa | RHTPA Operator | Trusted Profile Analyzer - 脆弱性分析 |

### workload/（ワークロードクラスタ専用）

| コンポーネント | Operator | 用途 |
|---|---|---|
| servicemesh | Service Mesh Operator | OpenShift Service Mesh |
| sample-app | - | サンプルアプリ (overlay patch パターンのデモ) |

## ブートストラップ手順

各クラスタで以下を実行します。

```bash
# 1. ArgoCD Operator のインストールと ArgoCD CR + ApplicationSet の適用
oc apply -k bootstrap/overlays/<cluster-name>/

# CRD が登録されるまで待機（初回のみ）
# Operator がインストールされた後、再適用
oc apply -k bootstrap/overlays/<cluster-name>/

# 例: IDP クラスタ
oc apply -k bootstrap/overlays/idp-cluster/
```

ブートストラップ後の流れ:

1. OpenShift GitOps Operator がインストールされる
2. ArgoCD CR が作成され、ArgoCD が起動する
3. ArgoCD が `clusters/<cluster-name>/` の ApplicationSet を読み取る
4. ApplicationSet が `apps/` 配下のマッチする overlay を自動検出し、Application を生成する
5. Operator Subscription が先に sync され、CRD 登録後に CR が sync される (sync-wave)

## 新しいコンポーネントの追加方法

```bash
# 1. Tier を選択して base を作成
mkdir -p apps/<tier>/<component>/base
# -> Namespace, OperatorGroup, Subscription, CR 等のリソースを配置
# -> CR には sync-wave "1" と SkipDryRunOnMissingResource annotation を付与

# 2. Overlay を作成（スコープに応じた名前で）
mkdir -p apps/<tier>/<component>/overlays/<target>
# -> kustomization.yaml で base を参照

# 3. 完了。ApplicationSet が自動検出する
```

**重要: 1 つのコンポーネントに対して、同じクラスタにマッチする overlay を複数作成しないでください。** 例えば `overlays/all/` と `overlays/dev-cluster/` が両方存在すると、dev-cluster に 2 つの Application が生成され競合します。

## マニフェストの検証

```bash
# 個別の overlay を検証
oc kustomize apps/core/openshift-gitops/overlays/idp-cluster/

# 全 overlay を一括検証
for dir in $(find apps -type f -name kustomization.yaml -path '*/overlays/*' -exec dirname {} \; | sort); do
  oc kustomize "$dir" > /dev/null && echo "OK  $dir" || echo "FAIL $dir"
done
```

## Operator チャネルの更新手順

Subscription の `channel` を更新する際は、CatalogSource に実際に存在するチャネルを確認すること。
Red Hat ドキュメント上の最新バージョンがクラスタの CatalogSource に未提供の場合がある。

### 1. 利用可能なチャネルを確認する

```bash
# 特定の Operator
oc get packagemanifest <operator-name> -n openshift-marketplace \
  -o jsonpath='{.status.channels[*].name}'

# このリポジトリで管理している全 Operator を一括確認
for pkg in openshift-gitops-operator openshift-pipelines-operator-rh \
           rhacs-operator quay-operator rhdh rhtas-operator \
           rhtpa-operator servicemeshoperator; do
  printf "%-40s %s\n" "$pkg:" \
    "$(oc get packagemanifest "$pkg" -n openshift-marketplace \
       -o jsonpath='{.status.channels[*].name}' 2>/dev/null || echo 'NOT FOUND')"
done
```

### 2. Red Hat 公式ライフサイクルポリシーを参照する

- [OpenShift Operator Life Cycles](https://access.redhat.com/support/policy/updates/openshift_operators)

### 3. Subscription ファイルのチャネルを更新する

対象ファイル一覧:

| Operator | ファイル |
|---|---|
| OpenShift GitOps | `bootstrap/base/subscription.yaml` |
| OpenShift Pipelines | `apps/core/openshift-pipelines/base/subscription.yaml` |
| RHACS | `apps/hub/rhacs-central/base/subscription.yaml` |
| Quay | `apps/hub/quay/base/subscription.yaml` |
| Developer Hub | `apps/hub/rhdh/base/subscription.yaml` |
| Trusted Artifact Signer | `apps/hub/rhtas/base/subscription.yaml` |
| Trusted Profile Analyzer | `apps/hub/rhtpa/base/subscription.yaml` |
| Service Mesh | `apps/workload/servicemesh/base/subscription.yaml` |

### 4. InstallPlan を承認する

`installPlanApproval: Manual` のため、チャネル変更後に生成される InstallPlan を承認する必要がある。

```bash
# 未承認の InstallPlan を確認（dry-run）
./scripts/approve-installplans.sh --dry-run

# 一括承認
./scripts/approve-installplans.sh
```

## 参考資料

- [gnunn-gitops/cluster-config-v2](https://github.com/gnunn-gitops/cluster-config-v2) -- Gerald Nunn 氏による OpenShift GitOps リファレンス実装
- [Gerald Nunn | Red Hat Developer](https://developers.redhat.com/author/gerald-nunn) -- OpenShift GitOps の公式記事・ガイド
- [Getting Started with OpenShift GitOps](https://developers.redhat.com/articles/2025/05/28/getting-started-openshift-gitops) -- OpenShift GitOps 入門ガイド
