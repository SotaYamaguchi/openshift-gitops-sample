# Platform GitOps Repository

OpenShift / ROSA クラスタ群のプラットフォーム構成を GitOps で管理するリポジトリです。

## 設計思想

このリポジトリの構成は、Red Hat の **Gerald Nunn** 氏（Principal Technical Marketing Manager - Kubernetes and GitOps）が公開している [cluster-config-v2](https://github.com/gnunn-gitops/cluster-config-v2) のパターンを基盤としています。

Gerald Nunn 氏は Red Hat で OpenShift GitOps の技術マーケティングを主導し、[Red Hat Developer Blog](https://developers.redhat.com/author/gerald-nunn) にて OpenShift GitOps の公式ガイドやベストプラクティスを多数公開しています。このパターンは Red Hat 社内外で広く採用されており、OpenShift GitOps の実運用における確立されたリファレンスアーキテクチャです。

### 核となる設計判断

#### 1. 分散 ArgoCD（各クラスタが自身のみを管理）

```
┌─────────────────────┐  ┌─────────────────────┐
│ IDP (Hub)           │  │ dev-workload         │
│  ArgoCD -> self     │  │  ArgoCD -> self      │
│  core/ + hub/       │  │  core/ + workload/   │
└─────────────────────┘  └─────────────────────┘
┌─────────────────────┐  ┌─────────────────────┐
│ stg-workload        │  │ prod-workload        │
│  ArgoCD -> self     │  │  ArgoCD -> self      │
│  core/ + workload/  │  │  core/ + workload/   │
└─────────────────────┘  └─────────────────────┘
```

各クラスタの ArgoCD は `https://kubernetes.default.svc` のみをターゲットにします。リモートクラスタの Secret 管理が不要になり、クラスタ間の依存関係を排除できます。中央集権型の ArgoCD Hub と比較して、障害の影響範囲が限定されます。

#### 2. Overlay 名によるスコープ制御

ApplicationSet の Git directory generator が overlay のディレクトリ名を基にアプリケーションを自動検出します。これにより、**新しいコンポーネントを追加する際に ApplicationSet を編集する必要がありません**。

| Overlay 名 | 粒度 | 適用先 |
|---|---|---|
| `all` | 全クラスタ | IDP, dev, stg, prod |
| `hub` / `workload` | クラスタ種別 | hub -> IDP のみ, workload -> dev + stg + prod |
| `workload-dev` / `workload-prod` | 種別 + 環境 | 特定環境 |
| `internal-developer-portal` / `dev-workload` | クラスタ固有 | 特定クラスタのみ |

Gerald Nunn 氏がこの設計について述べているように、**どのアプリケーションがどのクラスタにデプロイされるかは、シンプルな `ls` コマンドで確認できます**。DRY 原則よりも可読性を重視した設計です。

#### 3. Tier 分類（core / hub / workload）

コンポーネントの配置先は「もう 1 つクラスタを追加したとき、そのコンポーネントも必要か？」で判断します。

- **core/** -- 全クラスタに必要なインフラ（ArgoCD, cert-manager, external-secrets, RBAC, etc.）
- **hub/** -- IDP クラスタのみで必要な管理サービス（Developer Hub, Quay, Pipelines, ACS, etc.）
- **workload/** -- ワークロードクラスタのみで必要なもの（AMQ Streams, Grafana, ALB Operator, etc.）

#### 4. base / components / overlays パターン

全コンポーネントが同一の Kustomize ディレクトリ構造に従います。

```
apps/<tier>/<component>/
├── base/               # コンポーネントの動作に必要な最小リソース
├── components/         # オプション機能 (Kustomize Component)
└── overlays/           # ターゲット別のパッチ・設定
```

- **base/** -- Operator Subscription, CRD インスタンス, Namespace 等
- **components/** -- 有効/無効を選択できる機能モジュール（例: ArgoCD の notifications, image-updater）
- **overlays/** -- クラスタ固有のドメイン名、認証情報、リソース制限等をオーバーライド

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
├── infrastructure/     # Terraform / Terragrunt（AWS, ROSA, VPC 等）
├── templates/          # Backstage ソフトウェアテンプレート
└── docs/               # ドキュメント
```

## クラスタ構成

| クラスタ | 役割 | Tier |
|---|---|---|
| internal-developer-portal | Hub クラスタ。Developer Hub, Quay, Pipelines 等の管理サービスをホスト | core + hub |
| dev-workload | 開発環境ワークロード | core + workload |
| stg-workload | ステージング環境ワークロード | core + workload |
| prod-workload | 本番環境ワークロード | core + workload |

## プラットフォームコンポーネント

### core/（全クラスタ共通）

| コンポーネント | 用途 |
|---|---|
| argocd | OpenShift GitOps - デプロイメント自動化 |
| cert-manager | Let's Encrypt TLS 証明書管理 |
| cert-utils-operator | 証明書の Route 自動注入 |
| external-secrets | AWS Secrets Manager 連携 |
| cluster-monitoring | クラスタ監視設定 |
| rbac | プラットフォーム RBAC |

### hub/（IDP クラスタ専用）

| コンポーネント | 用途 |
|---|---|
| backstage | Red Hat Developer Hub - 開発者ポータル |
| quay | Red Hat Quay - コンテナレジストリ |
| pipelines | OpenShift Pipelines (Tekton) - CI/CD |
| acs | Advanced Cluster Security - コンテナセキュリティ |
| tas | Trusted Artifact Signer - イメージ署名・検証 |
| tpa | Trusted Profile Analyzer - 脆弱性分析 |

### workload/（ワークロードクラスタ専用）

| コンポーネント | 用途 |
|---|---|
| amq-streams | AMQ Streams (Kafka) |
| aws-load-balancer-operator | ALB/NLB 自動作成 |
| external-dns-operator | Route53 DNS レコード自動作成 |
| grafana-operator | 監視ダッシュボード |
| opentelemetry | 分散トレーシング・メトリクス |
| argo-rollouts | Blue/Green・Canary デプロイメント |

## ブートストラップ手順

各クラスタで以下を実行します。

```bash
# 1. ArgoCD のインストールと ApplicationSet の適用
oc apply -k bootstrap/overlays/<cluster-name>/

# 例: IDP クラスタ
oc apply -k bootstrap/overlays/internal-developer-portal/
```

ブートストラップ後の流れ:

1. ArgoCD がインストールされる
2. ArgoCD が `clusters/<cluster-name>/` の ApplicationSet を読み取る
3. ApplicationSet が `apps/` 配下のマッチする overlay を自動検出し、Application を生成する

## 新しいコンポーネントの追加方法

```bash
# 1. Tier を選択して base を作成
mkdir -p apps/<tier>/<component>/base
# -> Subscription, Namespace 等のリソースを配置

# 2. Overlay を作成（スコープに応じた名前で）
mkdir -p apps/<tier>/<component>/overlays/<target>
# -> kustomization.yaml で base を参照

# 3. 完了。ApplicationSet が自動検出する
```

**重要: 1 つのコンポーネントに対して、同じクラスタにマッチする overlay を複数作成しないでください。** 例えば `overlays/all/` と `overlays/dev-workload/` が両方存在すると、dev-workload クラスタに 2 つの Application が生成され競合します。

## マニフェストの検証

```bash
# 個別の overlay を検証
oc kustomize apps/core/argocd/overlays/all/

# 全 overlay を一括検証
for dir in $(find apps -type f -name kustomization.yaml -path '*/overlays/*' -exec dirname {} \; | sort); do
  oc kustomize "$dir" > /dev/null && echo "OK  $dir" || echo "FAIL $dir"
done
```

## 参考資料

- [gnunn-gitops/cluster-config-v2](https://github.com/gnunn-gitops/cluster-config-v2) -- Gerald Nunn 氏による OpenShift GitOps リファレンス実装
- [Gerald Nunn | Red Hat Developer](https://developers.redhat.com/author/gerald-nunn) -- OpenShift GitOps の公式記事・ガイド
- [Getting Started with OpenShift GitOps](https://developers.redhat.com/articles/2025/05/28/getting-started-openshift-gitops) -- OpenShift GitOps 入門ガイド
