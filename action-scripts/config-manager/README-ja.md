# Config Manager

[🇺🇸 English](README.md) | **日本語**

Config Manager は `workflow-config.yaml` を検証し、サービスからどのターゲットが作られるかを表示します。2 つの composite action はどちらも最初に `validate` を実行するので、設定が不正ならラベルの変更やターゲットの解決に進む前に step が失敗します。設定の形式は[このページ](#configuration-format)で説明しています。

## Commands

`action-scripts` ディレクトリで実行します。どちらのコマンドも GitHub にはアクセスしません。

| コマンド | 結果 |
|---|---|
| `bundle exec ruby config-manager/bin/config-manager validate` | 設定が正しいかどうかと、サービス・stack・定義された環境の数を表示します |
| `bundle exec ruby config-manager/bin/config-manager test SERVICE [ENVIRONMENT]` | サービスの全ターゲットと、それぞれが除外されているかを表示します |

`validate` は設定が不正なら終了コード 1 で終わります。読むのはファイルだけでディレクトリは列挙しないため、git の checkout の外でも動きます。その代わり、ディレクトリから探索される環境は表示される数に含まれません。エラーは `services[0].stacks[1].environments.develop.use[0]: profile 'aws' is not defined` のように問題の位置を示します。

`test` は、実在するディレクトリをもとに、サービスが何をデプロイするかを表示します。

```bash
bundle exec ruby config-manager/bin/config-manager test demo
bundle exec ruby config-manager/bin/config-manager test demo production
```

環境を省略すると、定義された環境と探索された環境のすべてに、環境をまたいで共有されるターゲットを加えて調べます。環境を指定すると、その環境と共有ターゲットを調べます。サービスの事前登録は不要で、どのディレクトリにも一致しない名前を渡すと結果は空になります。各ターゲットは stack の `id`、展開後の属性値、取得したプレースホルダーとともに表示されます。除外されたターゲットも `excluded: true` を付けて表示されるので、デプロイから外れるものを確認できます。未知の環境、不正な設定、ディレクトリを列挙できない場合、同じターゲットで取得値が食い違う場合はエラーになり、終了コード 1 で終わります。

元の設定を編集せずに変更を試すときは、`WORKFLOW_CONFIG_PATH` でコピーを指定します。

```bash
cp workflow-config.yaml test-config.yaml
WORKFLOW_CONFIG_PATH=test-config.yaml bundle exec ruby config-manager/bin/config-manager validate
WORKFLOW_CONFIG_PATH=test-config.yaml bundle exec ruby config-manager/bin/config-manager test myservice develop
```

### Environment Variables

3 つのツールはいずれも次の環境変数を読みます。

| 変数 | 値 |
|---|---|
| `WORKFLOW_CONFIG_PATH` | 設定ファイル。現在のディレクトリからの相対パスで、既定は `workflow-config.yaml` |
| `SOURCE_REPO_PATH` | リポジトリのルート。`.git` があるときに使います。なければ現在のディレクトリ自身から探し始め、`.git` を持つ最も近いディレクトリをルートにします |
| `GITHUB_TOKEN` | GitHub API のトークン。`dispatcher dispatch` と `resolver resolve` で必須 |
| `GITHUB_REPOSITORY` | `owner/repo` 形式のリポジトリ。`dispatcher dispatch` と `resolver resolve` で必須 |
| `GITHUB_ACTIONS` | 設定されていると、step の output を書き出し、エラーを `::error::` アノテーションで報告します |
| `GITHUB_OUTPUT` | step の output ファイル。`GITHUB_ACTIONS` が設定されているときは必須 |

## Configuration Format

`workflow-config.yaml` には空でない `services` 配列が必須で、任意のキーが 2 つあります。`profiles` は名前付きの属性セットを定義し、`labels` はラベルの prefix を設定します（[Labels](../label-dispatcher/README-ja.md#labels) を参照）。それ以外のトップレベルのキーは設定エラーです。

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

サービスは `roots` の下にあるファイルを持ち、その中で動く `stacks` を含みます。

| フィールド | 必須 | 動作 |
|---|---|---|
| `id` | 必須 | 設定全体で一意な識別子 |
| `roots` | 必須 | リポジトリルートからの相対パターンの空でない配列。どの root にも `{service}` が必要 |
| `attributes` | 任意 | サービス内の全 stack の全ターゲットに付く属性 |
| `ignore` | 任意 | root からの相対 glob の配列。変更検出にだけ影響します（[Ignoring Files](../label-dispatcher/README-ja.md#ignoring-files) を参照） |
| `stacks` | 必須 | stack の空でない配列 |

`{service}` で取得した値が、ラベルと matrix でのサービス名になります。サービスの `id` はどちらにも現れません。

root には `{project}` のような任意のプレースホルダーを使えます。`envs/{environment}/{service}` のように root に `{environment}` を書くと拒否されます。環境は stack の `path` で表すものだからです。環境ディレクトリがサービスの下にあるなら、`{environment}` は `path` に書き、root はサービスのディレクトリのままにします。こうすると、環境の隣にある共有ディレクトリも root の下に収まります。

### Stacks

stack は各 root に `path` を続けた場所で動きます。root が `aws/{service}`、path が `{environment}` なら、ディレクトリのパターンは `aws/{service}/{environment}` です。複数の stack が同じディレクトリを指しても構いません。

| フィールド | 必須 | 動作 |
|---|---|---|
| `id` | 必須 | 全サービスを通して一意な識別子。matrix の `stack` になります |
| `path` | 必須 | 各 root からの相対パス。`.` は root 自身 |
| `attributes` | 任意 | stack の全ターゲットに付く属性 |
| `environments` | 任意 | 環境名から環境エントリへの空でないマップ |
| `exclude` | 任意 | 除外条件の配列。既定は空配列 |

`path` には `{environment}` と任意のプレースホルダーを使えます。`{service}` は使えません。サービスは root が決めるからです。

stack に組み込みの種類はありません。`type` などの属性でツールの種類を表し、後続の処理でそれを見て分岐します（[Matrix Output](../label-resolver/README-ja.md#matrix-output) を参照）。`environments` と `{environment}` によって stack のターゲットがどう決まるかは [How Targets Are Built](../label-resolver/README-ja.md#how-targets-are-built) で説明しています。

### Profiles

profile はトップレベルの `profiles` に置く名前付きの属性マップです。stack は `environments.<name>` の中の `use` で profile を参照します。

`environments` のエントリは属性のマップで、`use` だけが予約キーです。`use` は profile 名の空でない配列で、省略できます。ターゲットの属性は、サービスの `attributes`、stack の `attributes`、`use` に並べた各 profile の属性、エントリの残りのキー（インライン属性）を合わせたものです。上の例の `gcp` stack は `aws-develop` の AWS ロールで動き、`gcp_project` でリソースを作る先のプロジェクトを加えています。

これらのうち 2 か所以上で同じ属性名を定義すると設定エラーになり、stack、環境、定義元が示されます。未定義の profile を `use` に書くと、`services[i].stacks[j].environments.<name>.use[k]` を指す設定エラーになります。使われない profile があるのは問題ありません。`use` を書けるのは `environments.<name>` の中だけで、サービスや stack の `attributes`、profile の中では拒否されます。

profile の属性には環境の属性と同じルールが適用されます。キーに matrix の固定キーは使えず、プレースホルダーはその profile を使うすべての stack で解決できなければなりません。

### Attribute Values

サービスと stack の `attributes`、profile、環境エントリの文字列値では、`{service}` と、root や `path` から取得した `{project}` のような任意のプレースホルダーを使えます。環境を持つターゲットでは、定義か探索かを問わず、`path` に含まれていなくても `{environment}` を使えます。`environments` も `path` の `{environment}` も持たない stack のターゲットには環境がないので、その属性では `{environment}` を参照できません。

同じルールはマップや配列の中の文字列にも適用されます。マップのキーはそのまま扱われ、文字列以外の値は型を保ちます。環境ごとに属性のキーが揃っている必要はありません。

属性が参照するプレースホルダーは、サービスのどの root と stack の `path` の組み合わせでも解決できなければなりません。サービスの属性なら、サービス内のどの stack でも同様です。解決できない参照は設定エラーになります。たとえば `roots: ["teams/{team}/{service}"]` と `attributes: {repository: "ghcr.io/{team}/{service}"}` の組み合わせでは、`teams/payments/api` に対して `ghcr.io/payments/api` が作られます。`{team}` を持たない root をこのサービスに足すと参照が拒否されるので、取得するプレースホルダーが異なる root はサービスを分けて書きます。

### Path Patterns

root と path は相対パターンです。絶対パスと `..` セグメントは拒否されます。先頭の `./`、余分な `/`、`.` セグメントは正規化されます。名前がドットで始まるサービスは対象から外れます。

任意のプレースホルダーの名前は `[a-z_][a-z0-9_]*` に一致する必要があり、値は 1 つのパスセグメントに収まります。同じプレースホルダーを複数回書くと、すべて同じ値に一致しなければなりません。glob の文字は文字どおりに扱われます。

プレースホルダーが matrix の固定キー（`stack`、`working_directory`）や、stack の属性キーと衝突する定義は拒否されます。属性キーの定義元がサービスや stack の `attributes`、profile、環境エントリのどれであっても同じです。属性キーには matrix の固定キー（`service`、`environment`、`stack`、`working_directory`）を使えません。

### Exclusion Conditions

`exclude` の各エントリは空でない条件のマップです。条件には `service`、`environment`、サービスのいずれかの root または stack の `path` にある任意のプレースホルダーを使えます。属性名は条件のキーに使えません。

条件は完全一致で判定します。マップ内のキーは AND、配列のエントリは OR で組み合わされ、書かなかったキーは制約になりません。一致した root が取得しない値を要求する条件は、その root では一致しません。たとえば `project: sandbox` が除外するのは、`gcp/{project}/{service}` のような root の下のターゲットだけです。

条件の値は 1 つのパスセグメントを表す空でない文字列で、`/`、`.`、`..` は使えません。サービス名をドットで始めることはできません。値は文字どおりに扱われ、プレースホルダーは展開されません。

`environment` 条件の扱いは、stack が環境をどう得るかで変わります。`environments` があれば、その stack で定義した環境だけを指定できます。環境を探索する stack では、まだ存在しないディレクトリの値も指定できます。`environments` も `path` の `{environment}` も持たない stack では、`environment` を省略するか `null` にします。それ以外の条件の値に `null` は使えません。

### YAML Anchors

アンカー、エイリアス、マージキー（`<<`）は使え、検証の前に解決されます。アンカーは `profiles` かいずれかの stack の中に定義します。アンカー専用のトップレベルキーを作ると未知のキーとして拒否されるためです。

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

検証で見るのはパース後のハッシュだけなので、上の `iam_role_plan` のように `<<:` の隣に書いたキーは、マージされた値を黙って上書きします。一方、stack の `attributes`、`use` の profile、インライン属性で同じキーを定義すると設定エラーになります。

## Code Layout

2 つのコマンドの入口は `ConfigManagerController` です。`ValidateConfig` は `ConfigClient` を通してファイルを読みます。`ConfigClient` は YAML をパースし、`WorkflowConfigParser` で検証します。`TestService` は共通の use case である `ListCandidates` でターゲットを列挙します。出力の整形は、端末では `ConsolePresenter`、workflow の中では `GitHubActionsPresenter` が担当します。

## Testing

```bash
cd action-scripts
bundle exec rspec spec/config-manager/
```
