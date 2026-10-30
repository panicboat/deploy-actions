# Label Dispatcher

[🇺🇸 English](README.md) | **日本語**

Label Dispatcher は Pull Request が変更したサービスを見つけ、Pull Request の `deploy:<service>` ラベルを同期します。このラベルが [Label Resolver](../label-resolver/README-ja.md) の入力になります。

## Action

```yaml
- uses: panicboat/deploy-actions/label-dispatcher@v0.1.0
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.DEPLOY_LABEL_TOKEN }}
```

action は `repository` を全履歴つきで自分で checkout するので、job に checkout の step は要りません。ラベルを見る前に [Config Manager](../config-manager/README-ja.md) で設定を検証します。

入力:

| 入力 | 必須 | 値 |
|---|---|---|
| `pr-number` | はい | ラベルを付ける Pull Request |
| `repository` | はい | ソースリポジトリ（`owner/repo`） |
| `github-token` | はい | `pull-requests: write` を持つトークン。リポジトリの checkout とラベルの変更に使います |
| `config-path` | いいえ | リポジトリ内の設定ファイルのパス。既定は `workflow-config.yaml` |

`GITHUB_TOKEN` で付けたラベルでは他の workflow が起動しません。`labeled` で動く workflow から resolver を実行するなら、GitHub App のトークンか個人アクセストークンを渡します。

出力:

| 出力 | 値 |
|---|---|
| `labels-added` | 実行前の PR になかったラベルの JSON 配列 |
| `labels-removed` | 実行で PR から外し、付け直さなかったラベルの JSON 配列 |
| `services-detected` | 変更から検出したサービスの JSON 配列 |
| `has-changes` | サービスを 1 つ以上検出したら `true`、それ以外は `false` |

## Change Detection

変更ファイルがいずれかの root の下にあれば、そのサービスにラベルが付きます。dispatcher は Pull Request の base と head を three-dot diff で比較し、すべての変更ファイルをすべての root に対して次の順で評価します。

1. ファイルが root の下にない場合、または `{service}` の取得値がドットで始まる場合はスキップします。
2. root からの相対パスが `ignore` のパターンに一致する場合はスキップします。
3. ファイルが stack のディレクトリ（root に `path` を続けた場所）の下にある場合は、[Label Resolver と同じ方法](../label-resolver/README-ja.md#how-targets-are-built)で候補ターゲットを作ります。`exclude` が候補をすべて除外しない限り、サービスにラベルを付けます。
4. `modules/` や `Makefile` のようにどの stack のディレクトリの下にもない場合は、サービスにラベルを付けます。こうした共有ファイルに `exclude` は効かないので、スキップするには `ignore` を使います。

照合はパスだけで行うため、ディレクトリが実在する必要はなく、削除されたファイルも対象になります。stack の path はディレクトリとして解決されるので、そのディレクトリと同じパスを持つファイルは「下にある」とは扱われません。

候補は、stack が環境をどう得るかで変わります。`environments` を持つ stack は定義した名前だけを受け付け、`{environment}` を含まない path なら定義した環境ごとに評価します。環境を探索する stack は、変更パスから取得した名前を使います。どちらでもない stack は `environment: null` で評価します。

ルール 3 と 4 の結果が変わるケースが 3 つあります。

- `path: "."` の stack は root 自身をディレクトリとしますが、ルール 4 の判定では stack のディレクトリに数えません。候補はルール 3 のとおりにサービスへラベルを付けます。`exclude` が候補をすべて除外しても、ファイルが別の stack のディレクトリの下になければルール 4 が適用されます。
- 別の stack のディレクトリの下にあり、その候補がすべて除外されるファイルには、やはりラベルが付きません。
- `environments` を持つ stack では、`{environment}` の位置にある定義外のディレクトリは stack のディレクトリの外として扱います。

関係のないトップレベルのディレクトリがサービスとみなされないよう、root は十分に絞ります。たとえば `{service}` だけの root では、トップレベルのディレクトリすべてがサービスになります。

共有ファイルの変更で、解決できるターゲットのないサービスにラベルが付くこともあります。唯一の環境が除外されている場合などです。ラベルは付きますが、Label Resolver が返すターゲットは空です。

次の設定では、環境ディレクトリが共有の `modules/` ディレクトリと並んでいます。

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
| `aws/api/modules/main.tf` | `api` にラベル: 共有ファイル |
| `gcp/sandbox/api/modules/main.tf` | `api` にラベル: 共有ファイルなので `exclude` は効かない |
| `aws/api/develop/main.tf` | `api` にラベル |
| `aws/api/production/main.tf` | ラベルなし: 唯一の候補が除外される |
| `gcp/sandbox/api/develop/main.tf` | ラベルなし: 唯一の候補が除外される |
| `aws/api/docs/guide.md` | ラベルなし: ignore に一致 |

### Ignoring Files

`ignore` のパターンは root からの相対 glob です。root が `dystopia/{service}` なら、`dystopia/api/docs/guide.md` は `docs/guide.md` として照合されます。`*` は `/` をまたがず、`**/` は 0 個以上のディレクトリに一致します。末尾の `/**` はそのディレクトリの下のすべてのファイルに一致します。ドットで始まるファイルも一致し、`?`、`[...]`、`{a,b}` はシェルの glob と同じように使えます。

`ignore` が影響するのは変更検出だけです。ignore されたパスの下にも Label Resolver はターゲットを作ります。

## Labels

実行のたびに、Pull Request に付いている prefix で始まるラベルをすべて外し、リポジトリにない必要なラベルを作成してから、必要なラベルを付けます。先に外しておくので、push のたびに `labeled` が発生し、そのイベントが resolver を起動します。ラベルは 1 つずつ付くため、2 つのサービスにラベルが付く push では `labeled` が 2 回発生し、resolver はそれぞれの実行時点で Pull Request に付いているラベルを読みます。

`labels` キーで prefix を設定します。次の断片は `workflow-config.yaml` のトップレベル、`services` の隣に書きます。

```yaml
labels:
  prefix: "deploy:"
  extra_prefixes: ["manual/"]
```

| フィールド | 必須 | 動作 |
|---|---|---|
| `prefix` | 任意 | Label Dispatcher が管理するラベルの prefix。既定は `deploy:` |
| `extra_prefixes` | 任意 | Label Resolver が追加で読む prefix の配列。既定は空配列 |

prefix は区切り文字を含めてそのまま使われるので、`:` で終わる prefix は YAML で引用符を付けます。prefix は空でない文字列でなければなりません。ある prefix が別の prefix で始まることは許されません。Label Dispatcher が重なった prefix のラベルまで外してしまうためです。

`<prefix>all` は Label Resolver で全サービスを対象にします。dispatcher がこれを作るのは `{service}` の位置に `all` というディレクトリがある場合だけなので、普通は手で付けます。ただし `prefix` のラベルを手で付けても次の push で外れます。`extra_prefixes` で始まるラベルには一切触らないので、`manual/all` や `manual/api` は以後の push でも残ります。

`{service}` の位置のディレクトリには名前を問わずラベルが付きますが、Label Resolver は `[a-zA-Z0-9_-]+` に一致する名前[だけを読みます](../label-resolver/README-ja.md#from-labels-to-targets)。そのため `a.b` のようなディレクトリには、何にも解決されないラベルが付きます。

## Commands

`action-scripts` ディレクトリで実行します。

| コマンド | 結果 |
|---|---|
| `bundle exec ruby label-dispatcher/bin/dispatcher dispatch PR_NUMBER` | PR の base と head から変更を検出し、PR のラベルを同期します |
| `bundle exec ruby label-dispatcher/bin/dispatcher test [--base-ref=REF] [--head-ref=REF]` | GitHub を呼ばずに、変更に付くラベルを表示します |

`dispatch` には `GITHUB_TOKEN` と `GITHUB_REPOSITORY` が必要です。他の変数は [Environment Variables](../config-manager/README-ja.md#environment-variables) を参照してください。

`test` はオプションによって比較対象が変わります。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=feature/auth
```

ref を指定しないと、ステージ済みと未ステージの変更を使います。未追跡のファイルは含まれません。`--base-ref` だけなら base ref と作業ツリーを比較します。両方を指定すると `dispatch` と同じ three-dot diff です。`--head-ref` だけの指定はエラーです。存在しない ref を指定するとエラーで止まり、作業ツリーの変更には切り替えません。

どちらのコマンドも、ラベルと変更ファイルを表示します。変更ファイルが多いときは最初の 10 件だけを並べます。`dispatch` は追加と削除したラベルも表示します。どのターゲットが除外されるかを調べるには [`config-manager test`](../config-manager/README-ja.md#commands) を使います。

エラーは終了コード 1 で終わります。GitHub API のリクエストは Octokit の既定のリトライ機構を通り、冪等なリクエストは待ち時間なしで最大 2 回再試行されます。それでも失敗すると、API のエラーメッセージを出してコマンドが止まります。

## Code Layout

2 つのコマンドの入口は `LabelDispatcherController` です。`DispatchLabels` は PR の base と head の SHA を取得し、`DetectChangedServices` と `ManageLabels` を呼びます。`DetectChangedServices` は変更ファイルを列挙してサービスに対応づけ、`ManageLabels` はラベルを同期します。`GitHubClient` は Octokit を包み、`GitClient` は `git diff --name-only` を実行し、`ConfigClient` は設定を読みます。`RepositoryRoot` は `git diff` を実行するリポジトリを特定し、`Composition` は環境変数からクライアントと presenter を組み立てます。

## Testing

```bash
cd action-scripts
bundle exec rspec spec/label-dispatcher/
```
