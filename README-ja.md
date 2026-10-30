# Deploy Actions

[🇺🇸 English](README.md) | **日本語**

複数サービスを抱えるリポジトリで、PR ラベルベースのデプロイメント・オーケストレーションを駆動する GitHub Actions ツールキット。

## 概要

ファイル変更からデプロイ対象ラベルを生成し、ラベルからデプロイメント・ターゲットを解決する層を提供します。実際の `plan`/`apply` 実行は、利用側で任意の Composite Action（Terragrunt / Helm / kustomize など）に委ねる構成です。

## 構成要素

### 1. Config Manager (`action-scripts/config-manager/`)

`workflow-config.yaml` の stack 定義を検証し、実在ディレクトリにあるサービスの対象を、除外状態とあわせて表示します。

**特徴:**

- 詳細なエラーレポート付きの設定検証
- サービスの各対象と除外状態を表示するサービス診断
- stack のパスと除外条件の検証

### 2. Label Dispatcher (`label-dispatcher/`)

PR の変更ファイルを検出し、変更があったサービスに対して `<prefix><service>` ラベル（既定は `deploy:<service>`）を付与します。

**特徴:**

- `git diff` からの変更検出
- ディレクトリパターンからのサービス発見
- 自動ラベル生成
- 除外処理

### 3. Label Resolver (`label-resolver/`)

`<prefix><service>` ラベルと指定環境を、後続 Action が利用する matrix に変換します。

**特徴:**

- ラベルからターゲットへの解決
- 定義環境と探索した環境からの対象選択
- デプロイメント matrix 生成
- stack の `exclude` 条件に一致する対象の除外

## Composite Actions

### Label Dispatcher

```yaml
- uses: panicboat/deploy-actions/label-dispatcher@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

出力:

| 出力 | 値 |
|---|---|
| `labels-added` | 実行前の PR になかったラベルの JSON 配列 |
| `labels-removed` | 実行後の PR からなくなったラベルの JSON 配列 |
| `services-detected` | 変更から検出したサービスの JSON 配列 |
| `has-changes` | `true` または `false` |

### Label Resolver

`environments` は任意の入力で、複数環境はカンマ区切りで指定します。省略すると定義環境と探索した環境をすべて対象にします。

```yaml
- uses: panicboat/deploy-actions/label-resolver@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: develop
```

`service` を指定すると、pull request なしで service（または `all`）の対象を解決します。このとき `pr-number` は無視され、`ref` で checkout する source repository の ref を選べます。

```yaml
- uses: panicboat/deploy-actions/label-resolver@v1
  with:
    repository: ${{ github.repository }}
    service: api
    environments: production
    ref: ${{ github.event.release.tag_name }}
```

入力:

| 入力 | 必須 | 値 |
|---|---|---|
| `repository` | 必須 | source repository（`owner/repo`） |
| `pr-number` | `service` 未指定なら必須 | ラベルを解決する pull request。`service` を指定すると無視される |
| `service` | 任意 | service 名または `all`。pull request なしでその対象を解決する |
| `environments` | 任意 | カンマ区切りの環境。空なら定義環境と探索した環境をすべて対象にする |
| `ref` | 任意 | checkout する source repository の ref。既定は、ワークフローを起動したリポジトリならイベントの ref、別のリポジトリならそのデフォルトブランチ |
| `github-token` | 任意 | リポジトリの checkout と PR の読み取りに使う token。既定は `${{ github.token }}` |
| `config-path` | 任意 | 設定ファイルのパス。既定は `workflow-config.yaml` |

出力:

| 出力 | 値 |
|---|---|
| `targets` | デプロイ対象の JSON 配列（[matrix 出力](#matrix-出力) を参照） |
| `has-targets` | `true` または `false` |
| `candidates` | `service` を指定した場合に、除外された候補を含むすべての候補の JSON 配列。各要素は `{"target": <matrix item>, "excluded": <bool>, "root": "<root>"}` |

## 設定

`workflow-config.yaml` のトップレベルには、空でない `services` 配列を定義します。service は `roots` 配下のファイルを所有し、その中で実行する `stacks` を持ちます。トップレベルの `profiles` は名前付きの属性セットを定義する省略可能なマップ、`labels` はラベルの prefix を指定する省略可能なマップです。これら以外のトップレベルのキーは設定エラーです。

```yaml
labels:
  prefix: "deploy:"

profiles:
  aws-develop:
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::123456789012:role/aws-plan-develop-role
    iam_role_apply: arn:aws:iam::123456789012:role/aws-apply-develop-role
  aws-production:
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::210987654321:role/aws-plan-production-role
    iam_role_apply: arn:aws:iam::210987654321:role/aws-apply-production-role

services:
  - id: app
    roots:
      - "dystopia/{service}"
      - "system-components/{service}"
    ignore:
      - "**/README.md"
    stacks:
      - id: dockerfile
        path: "."
        attributes:
          type: container
          repository: registry.example.com/{service}
      - id: kustomize
        path: "kubernetes/overlays/{environment}"
        attributes:
          type: kustomize
      - id: aws
        path: "infrastructure/aws/{environment}"
        attributes:
          type: terragrunt
        environments:
          develop:
            use: [aws-develop]
          production:
            use: [aws-production]
        exclude:
          - service: demo
            environment: production
      - id: gcp
        path: "infrastructure/gcp/{environment}"
        attributes:
          type: terragrunt
        environments:
          develop:
            use: [aws-develop]
            gcp_project: foo-develop
```

### Services

| フィールド | 指定 | 動作 |
|---|---|---|
| `id` | 必須 | 設定全体で一意な識別子。エラーメッセージと表示に使う |
| `roots` | 必須 | リポジトリルートからの相対パターンの空でない配列。すべての root に `{service}` が必要 |
| `attributes` | 任意 | その service のすべての stack のすべての対象に付く属性 |
| `ignore` | 任意 | root からの相対 glob の配列。変更検知にだけ効く |
| `stacks` | 必須 | stack の空でない配列 |

root は、どのファイルがその service のものかを決めます。ラベルと matrix の service 名は `{service}` が取り出した値で、service の `id` ではありません。

root には `{project}` などの任意 placeholder を使えます。環境は stack の `path` に属するため、root の `{environment}` は拒否します。service より後ろに環境ディレクトリがある構成では、`{environment}` を `path` に書き、root は service のディレクトリにします。環境ディレクトリの隣にある共通ディレクトリが root の配下に残ります。

対応しない構成: `envs/{environment}/{service}` のように root に `{environment}` を書く構成と、`{service}` を含まない root。

### Stacks

| フィールド | 指定 | 動作 |
|---|---|---|
| `id` | 必須 | 全 service をまたいで一意な識別子。matrix の `stack` になる |
| `path` | 必須 | 各 root からの相対パス。`.` は root そのもの |
| `attributes` | 任意 | その stack のすべての対象に付く属性 |
| `environments` | 任意 | 環境名から環境エントリへの空でないマップ |
| `exclude` | 任意 | 除外条件の配列。省略時は空配列 |

stack に組み込みの種類はありません。ツールの種類は `type` などの属性で表し、下流でその属性を使って振り分けます（[matrix 出力](#matrix-出力) を参照）。

stack は各 root に `path` を連結したディレクトリで実行します。root `aws/{service}` と path `{environment}` は、ディレクトリパターン `aws/{service}/{environment}` になります。`path` には `{environment}` と任意 placeholder を書けますが、service は root が決めるため `{service}` は書けません。異なる stack が同じディレクトリを指してもかまいません。

対象は次の順で作ります。

1. `environments` があれば、`path` に `{environment}` がなくても、宣言した環境ごとに対象を作ります。`path` に `{environment}` がある場合は宣言した名前だけに一致するため、`modules/` のようなディレクトリは対象になりません。
2. `environments` がなく `path` に `{environment}` があれば、その位置にある実在ディレクトリから環境名を探索します。その位置にある環境ではないディレクトリ（`modules/` など）も環境として探索するため、環境ディレクトリの隣にそうしたディレクトリがある場合は `environments` を宣言します。
3. どちらもなければ、環境選択にかかわらず、ディレクトリごとに `environment: null` の対象を 1 つ作ります。

`attributes` は、どの作り方でも、その stack のすべての対象に付きます。3 の対象では `{environment}` を参照できません。service の `attributes` も同じように、その service のすべての stack の対象に付きます。

選択できる環境一覧は、全 stack の定義環境と実行時に探索した環境名の和集合です。除外された環境名も選択できます。環境指定を省略するとこの和集合を対象にします。各 stack は自身の定義環境または探索した環境だけを生成し、和集合にない環境指定はエラーになります。

### Profiles

profile は、トップレベルの `profiles` に置く名前付きの属性マップです。stack は `environments.<name>` の中の `use` で profile を参照します。

`environments` の各エントリは属性のマップで、予約キー `use` を 1 つ持てます。`use` は profile 名の空でない配列で、省略できます。対象の属性は、service の `attributes`、stack の `attributes`、`use` に並べた profile の属性、エントリのそれ以外のキー（インラインの属性）を合わせたものです。上の例の `gcp` stack は、`aws-develop` の AWS の role で実行し、`gcp_project` でリソースを作る project を足しています。

- 同じ属性名がこれらの 2 か所以上にあれば設定エラーになり、stack・環境・ぶつかった元を示します。
- `use` に存在しない profile 名があれば設定エラーになり、`services[i].stacks[j].environments.<name>.use[k]` の位置を示します。使われていない profile はエラーになりません。
- `use` は `environments.<name>` の中だけで使えます。service と stack の `attributes`、profile の中では拒否します。
- profile の属性には環境属性と同じ規則を適用します。キーは matrix の固定キーにできず、placeholder はその profile を使うすべての stack で解決できる必要があります。

### Attribute Values

service と stack の `attributes`、profile、環境エントリの文字列値では、`{service}` と、root や `path` から抽出した `{project}` などの任意 placeholder を使えます。環境のある対象（定義または探索した環境）では、`path` に含まれない場合も `{environment}` を使えます。マップや配列に入れ子になった文字列にも同じ規則を適用します。マップのキーはリテラルのままで、文字列以外の値は型を保持します。環境間で属性キーを揃える必要はありません。

属性が参照する placeholder は、その service のすべての root に stack の `path` を連結したパターンで取得できる必要があります。service の属性では、その service のすべての stack について取得できる必要があり、解決できない参照は設定エラーになります。例えば `roots: ["teams/{team}/{service}"]` と `attributes: {repository: "ghcr.io/{team}/{service}"}` の組み合わせは、`teams/payments/api` に対して `ghcr.io/payments/api` を出力します。`{team}` を含まない root が同じ service にあれば、この参照は拒否されるため、抽出する placeholder が異なる root は別の service に分けます。

### パスの照合

root と path は相対パターンです。絶対パスと `..` 要素は拒否し、先頭の `./`、余分な `/`、`.` 要素は正規化します。各 root に `path` を連結したパターンに一致する実在ディレクトリをすべて列挙し、存在しないパスは対象を生成しません。サービスの登録は不要です。ドットで始まるサービスは対象外です。

任意 placeholder の名前は `[a-z_][a-z0-9_]*`、値はパスの一要素です。同じ名前を繰り返した場合は、すべて同じ値に一致する必要があります。glob の記号はリテラルとして扱います。placeholder が matrix の固定キー（`stack`、`working_directory`）や、その stack のいずれかの属性キー（service と stack の `attributes`・profile・環境エントリのどれ由来でも）と衝突する定義は拒否します。属性キーを matrix の固定キー（`service`、`environment`、`stack`、`working_directory`）にすることもできません。

### 除外条件

`exclude` の各要素は空でない条件マップです。`service`、`environment`、その service のいずれかの root または stack の `path` にある任意 placeholder を条件にできます。属性名は条件キーとして使えません。

一つのマップ内は AND、配列内は OR で完全一致を判定します。省略したキーは制約になりません。照合した root が抽出しない値を要求する条件は、その root では一致しません。例えば `project: sandbox` が除外するのは、`gcp/{project}/{service}` のような root 配下の対象だけです。

条件値は空でない文字列で、パスの一要素を表し、`/`、`.`、`..` は使えません。service はドットで始められません。`environments` を指定した stack の環境条件は自身の定義環境だけを指定できます。環境を探索する stack では、まだ存在しないディレクトリの環境値も条件にできます。`environments` も `path` の `{environment}` もない stack では、environment の省略または `null` を受け付け、environment 以外の条件値に `null` は使えません。条件値はリテラルで、placeholder は展開しません。

### Detection

Label Dispatcher は、変更ファイルがいずれかの root の配下にあれば、次の例外を除いてその service にラベルを付けます。変更ファイルごとに、すべての root について次の順で判定します。

1. root の配下にない、または `{service}` の抽出値がドットで始まるファイルは対象外です。
2. root からの相対パスが `ignore` のいずれかに当たるファイルは対象外です。
3. ファイルが stack のディレクトリ（root に `path` を連結したもの）の配下にあれば、Label Resolver と同じ規則で候補の対象を作ります。`exclude` がすべての候補を除外しない限り、service にラベルを付けます。
4. ファイルがどの stack のディレクトリの配下にもなければ（`modules/` や `Makefile` などの共通部品）、service にラベルを付けます。これらの共通部品には `exclude` を適用しません。対象外にするには `ignore` を使います。

`path: "."` の stack は root そのものがディレクトリですが、規則 4 の判定では stack のディレクトリに数えません。その stack の候補は規則 3 と同じく service にラベルを付けますが、`exclude` がすべての候補を除外した場合は、ファイルがほかの stack のディレクトリの配下になければ規則 4 を適用します。ほかの stack のディレクトリの配下にあり、候補がすべて除外されたファイルには、引き続きラベルを付けません。`environments` を持つ stack では、`{environment}` の位置にあるディレクトリが宣言した環境でなければ、stack のディレクトリの外です。

関係のない最上位ディレクトリが service として扱われないよう、root は十分に絞り込みます。たとえば、最上位のディレクトリをすべて service にしてしまう `{service}` だけの root は避けます。

`ignore` は root からの相対 glob です。root `dystopia/{service}` では、`dystopia/api/docs/guide.md` を `docs/guide.md` として照合します。`*` は `/` をまたがず、`**/` は 0 個以上のディレクトリに当たります。末尾の `/**` はそのディレクトリ配下のすべてのファイルに当たります。ドットで始まるファイルにも当たり、`?`、`[...]`、`{a,b}` はシェルの glob と同じように使えます。`ignore` は変更検知にだけ効き、Label Resolver は無視したパスの配下でも対象を生成します。

共通部品の変更でラベルが付いた service に、解決できる対象が 1 つもないこともあります（たとえば唯一の環境が除外されている場合）。その場合はラベルが付き、Label Resolver は 0 件の対象を返します。

次の設定は、環境ディレクトリを共通の `modules/` ディレクトリの隣に置く構成です。

```yaml
profiles:
  aws-develop:
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::123456789012:role/aws-plan-develop-role
    iam_role_apply: arn:aws:iam::123456789012:role/aws-apply-develop-role
  aws-production:
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::210987654321:role/aws-plan-production-role
    iam_role_apply: arn:aws:iam::210987654321:role/aws-apply-production-role

services:
  - id: infrastructure
    roots:
      - "aws/{service}"
      - "gcp/{project}/{service}"
    ignore:
      - "**/*.md"
    stacks:
      - id: terragrunt
        path: "{environment}"
        attributes:
          type: terragrunt
        environments:
          develop:
            use: [aws-develop]
          production:
            use: [aws-production]
        exclude:
          - environment: production
          - project: sandbox
```

| 変更ファイル | 結果 |
|---|---|
| `aws/api/modules/main.tf` | `api` にラベルを付ける（共通部品） |
| `gcp/sandbox/api/modules/main.tf` | `api` にラベルを付ける（共通部品。`exclude` は適用しない） |
| `aws/api/develop/main.tf` | `api` にラベルを付ける |
| `aws/api/production/main.tf` | ラベルなし（唯一の候補が除外される） |
| `gcp/sandbox/api/develop/main.tf` | ラベルなし（唯一の候補が除外される） |
| `aws/api/docs/guide.md` | ラベルなし（`ignore`） |

### YAML Anchors

anchor・alias・merge key（`<<`）を使え、検証の前に展開されます。anchor は `profiles` かいずれかの stack の中で定義します。

```yaml
profiles:
  aws-develop: &aws-develop
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::123456789012:role/aws-plan-develop-role
    iam_role_apply: arn:aws:iam::123456789012:role/aws-apply-develop-role
  aws-production:
    <<: *aws-develop
    iam_role_plan: arn:aws:iam::210987654321:role/aws-plan-production-role
    iam_role_apply: arn:aws:iam::210987654321:role/aws-apply-production-role

services:
  - id: app
    roots:
      - "apps/{service}"
    stacks:
      - id: aws
        path: "aws/{environment}"
        environments: &environments
          develop:
            use: [aws-develop]
          production:
            use: [aws-production]
      - id: aws-audit
        path: "audit/{environment}"
        environments: *environments
```

validator はパース後のハッシュしか見ません。`<<:` と同じマップに書いたキーは、上の `iam_role_plan` のように、取り込んだ値をエラーにせず上書きします。stack の `attributes`、`use` で参照した profile、インラインの属性が同じキーを定義したときの設定エラーとは異なります。

### Labels

prefix は区切り文字を含めた文字列をそのまま使います。

```yaml
labels:
  prefix: "deploy:"
  extra_prefixes: ["manual/"]
```

| フィールド | 指定 | 動作 |
|---|---|---|
| `prefix` | 任意 | Label Dispatcher が管理するラベルの prefix。既定は `deploy:` |
| `extra_prefixes` | 任意 | Label Resolver が追加で読むラベルの prefix の配列。既定は空配列 |

Label Dispatcher は `<prefix><service>` ラベルを付与し、変更に一致しなくなった `prefix` で始まるラベルを外します。`extra_prefixes` で始まるラベルには触れないため、これらの prefix で手動付与したラベルは以降の push でも残ります。Label Resolver は設定したいずれかの prefix で始まるラベルを読み、残りの文字列をサービス名として扱います。異なる prefix で同じサービスが付与されていても一つのサービスとして扱い、どの prefix の `all` も全サービスを対象にします。残りの文字列がサービス名の形式（`[a-zA-Z0-9_-]+`）に一致しないラベルは無視します。

prefix は空でない文字列です。Label Dispatcher が重なった prefix のラベルまで外してしまうため、どの prefix も他の prefix で始まってはいけません。`:` で終わる prefix は YAML で引用符を付けて記述します。

実行可能な設定例は [workflow-config.yaml](action-scripts/workflow-config.yaml) を参照してください。

## ワークフローへの組み込み

### 1. 変更検出

```yaml
name: Detect Changes and Create Labels
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: panicboat/deploy-actions/label-dispatcher@v1
        with:
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 2. デプロイ対象の解決

```yaml
name: Deploy
on:
  pull_request:
    types: [labeled]

jobs:
  plan:
    runs-on: ubuntu-latest
    if: contains(github.event.label.name, 'deploy:')
    steps:
      - id: resolve
        uses: panicboat/deploy-actions/label-resolver@v1
        with:
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

`${{ steps.resolve.outputs.targets }}` を利用側のデプロイ処理に渡します。

`prefix` を変更する場合や `extra_prefixes` を追加する場合は、`if` 条件を設定したすべての prefix に一致するよう更新します（例: `startsWith(github.event.label.name, 'deploy:') || startsWith(github.event.label.name, 'manual/')`）。

実行レイヤ（`aws`, `kubernetes` など）は意図的に本リポジトリから除外しています。

## matrix 出力

`label-resolver` は `outputs.targets` に JSON 配列を出力します。固定キーは次の4個で、属性と任意 placeholder の抽出値を同じ階層に展開します。

| キー | 出力元 |
|---|---|
| `service` | ラベルまたは `<prefix>all` で探索したサービス名。`{service}` が取り出した値 |
| `environment` | 定義または探索した環境名。環境共通なら `null` |
| `stack` | stack の `id` |
| `working_directory` | 実在する対象ディレクトリの相対パス |
| 属性のキー | stack の `attributes`、選択した環境の `use` で参照した profile の属性、インラインの属性 |
| 任意 placeholder のキー | 一致したパスの抽出値 |

上記の最初の設定例で `dystopia/api/infrastructure/aws/develop` が存在する場合、次の行を生成します。

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "aws",
  "working_directory": "dystopia/api/infrastructure/aws/develop",
  "type": "terragrunt",
  "aws_region": "ap-northeast-1",
  "iam_role_plan": "arn:aws:iam::123456789012:role/aws-plan-develop-role",
  "iam_role_apply": "arn:aws:iam::123456789012:role/aws-apply-develop-role"
}
```

対象の同一性は service・stack・environment・working_directory で決まります。同じ対象の重複は一行にまとめます。同じ対象を異なる抽出値マップで解釈するパスは、除外条件や記載順にかかわらずエラーになります。

stack の種類は利用者が定義する属性なので、下流では `matrix.target.type` で振り分けます。`resolve` という名前の job で `steps.resolve.outputs.targets` を job の出力 `targets` として公開し、後続の job で使います。

```yaml
deploy:
  needs: resolve
  strategy:
    matrix:
      target: ${{ fromJSON(needs.resolve.outputs.targets) }}
  steps:
    - if: matrix.target.type == 'terragrunt'
      uses: ./.github/actions/terragrunt-plan
      with:
        working-directory: ${{ matrix.target.working_directory }}
        role-to-assume: ${{ matrix.target.iam_role_plan }}
    - if: matrix.target.type == 'kustomize'
      uses: ./.github/actions/kustomize-build
      with:
        working-directory: ${{ matrix.target.working_directory }}
```

## 開発

### 前提条件

- Ruby ([.ruby-version](action-scripts/.ruby-version))
- Bundler
- Git

### セットアップ

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

### 各コンポーネントの動作確認

`action-scripts` を作業ディレクトリとして実行します。`validate` と 2 つの `test` はローカルのファイルだけを読み、GitHub には触れません。

| コマンド | 結果 |
|---|---|
| `bundle exec ruby config-manager/bin/config-manager validate` | `workflow-config.yaml` を検証し、設定が不正なら終了コード 1 で終わる |
| `bundle exec ruby config-manager/bin/config-manager test SERVICE [ENVIRONMENT]` | サービスの各対象と除外状態を表示する |
| `bundle exec ruby label-dispatcher/bin/dispatcher test [--base-ref=REF] [--head-ref=REF]` | 変更に付くラベルを表示する |
| `bundle exec ruby label-dispatcher/bin/dispatcher dispatch PR_NUMBER` | PR の base と head から変更を検出し、PR のラベルを同期する |
| `bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER [ENVIRONMENTS]` | PR のラベルを対象に解決する。`ENVIRONMENTS` はカンマ区切りで、空なら全環境 |
| `bundle exec ruby label-resolver/bin/resolver targets SERVICE [ENVIRONMENTS]` | pull request なしで service（または `all`）の対象を解決する。`ENVIRONMENTS` は `resolve` と同じ |

変更が何をもたらすかをローカルで確かめるには、2 つの `test` を使います。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=HEAD
bundle exec ruby config-manager/bin/config-manager test api develop
```

- ref を指定しない `dispatcher test` は、ステージ済みと未ステージの変更を使います。
- `--base-ref` と `--head-ref` を指定すると 2 つの ref の差分を使います。`--base-ref` だけを指定すると base の ref と作業ツリーの差分を使います。`--head-ref` だけの指定はエラーです。
- ref を指定して存在しない場合は、作業ツリーの変更に切り替えずにエラーで止まります。
- `dispatch` は常に PR のラベルを同期します。`dispatch` と `resolve` には `GITHUB_TOKEN` と `GITHUB_REPOSITORY` が必要ですが、`targets` はどちらも不要です。
- リポジトリのルートは、`SOURCE_REPO_PATH` が `.git` を持つ場合はそのパスです。それ以外は現在のディレクトリ自身から探し始め、`.git` を持つ最も近いディレクトリです。
- `WORKFLOW_CONFIG_PATH` で設定ファイルを選びます。現在のディレクトリからの相対パスで、既定は `workflow-config.yaml` です。

## ライセンス

MIT — `LICENSE` を参照。
