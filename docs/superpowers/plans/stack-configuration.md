# Stack Configuration Implementation Plan

> **For agentic workers:** ユーザーが計画と実行方式を承認した後、本人が実装する場合は `superpowers:executing-plans`、subagent 方式を選んだ場合は `superpowers:subagent-driven-development` を使う。各手順のチェックボックスを完了時に更新する。委譲する場合は AGENTS.md の全ルールを委譲先に渡す。

**Goal:** stack のパス・属性・除外条件を一つの定義で扱い、すべての利用側を新しい設定モデルに揃える。

**Architecture:** `WorkflowConfig` が新形式を検証し、確定した stack 定義と除外判定を提供する。既存の `PatternMatcher` と `FileSystemClient` を使い、変更検出は変更パスから、matrix とサービス診断は実在ディレクトリから対象を解決する。旧形式への変換器を挟まず、利用側を直接変更する。

**Tech Stack:** Ruby、YAML、RSpec、FactoryBot、Thor。バージョンは `action-scripts/.ruby-version` と `action-scripts/Gemfile.lock` を参照する。

**Spec:** [Stack Configuration Design](../specs/stack-configuration-design.md)

## Global Constraints

- 設計書の新しいスキーマだけを受け付け、旧形式の変換器・互換アクセサー・二重の読み込み経路を作らない。
- 「トップレベルには必須の `stacks` だけを置く。」
- 「`attributes` と `environments` は併用しない。」
- 「属性値の型を変換しない。」
- 「属性の必須チェックと、環境間で属性キーを揃える検証は行わない。」
- 「変更検出と matrix 生成は同じ除外判定を利用する。」
- 新しい依存ライブラリを追加せず、Gemfile・lockfile・Ruby のバージョン指定を変更しない。
- ドキュメントの見出しは英語、本文は日本語にする。コードの名前・コメント・テスト名・コミットメッセージは英語にする。
- コメントを追加する場合は、非自明な制約を一行で書く。複数行のコメントと docstring を追加しない。
- コミットには `git commit -s` を使い、`Co-Authored-By` を付けない。初回 push は `git push -u origin HEAD`、PR は Draft にする。
- 各タスクは対象テストが通った時点でコミットする。全体の RSpec と設定 CLI の検証が通るまで、実装全体の完了を報告しない。
- 各コミット前に `superpowers:verification-before-completion` を適用し、そのコミットに含まれる変更の検証コマンドと出力を確認する。

## Review Focus

1. 不正な YAML 構造や任意キーの誤記は、設定内の位置を含むエラーとして各利用側へ届く。Task 1 の検証表と読み込みテストで確認する。
2. リテラルに glob 記号を含むパスと、同名 placeholder の繰り返しは、ディレクトリ列挙とパス照合で同じ意味になる。Task 2 の実在ディレクトリテストで確認する。
3. 環境共通だけの構成と環境名がパスにない構成は、環境数に応じた実行回数と属性が得られる。Task 3 の対象数・属性のテストで確認する。
4. 同じ対象へ複数パスが一致して抽出値が異なる場合は、除外条件やパス順序で矛盾が隠れず失敗する。Task 3 の衝突テストで確認する。
5. `{team}` がないパス、除外されない別 stack の照合、除外されない別環境の照合は、対象単位で判定する。Task 1・3・4・5 の除外と診断のテストで確認する。

## File Map

| Files | Responsibility | Task |
|---|---|---|
| `action-scripts/shared/entities/workflow_config.rb` | スキーマ検証、正規化した stack、環境一覧、除外判定 | 1 |
| `action-scripts/shared/infrastructure/config_client.rb` | ファイル読み込み、YAML 解析、モデルのキャッシュ | 1 |
| `action-scripts/config-manager/use_cases/validate_config.rb` | モデルの検証結果と設定件数の表示用サマリー | 1 |
| `action-scripts/spec/factories.rb`, `action-scripts/spec/spec_helper.rb` | 新形式の共通 fixture と実在ディレクトリを使うテスト基盤 | 1, 2, 3 |
| `action-scripts/shared/infrastructure/file_system_client.rb` | ソースリポジトリのルートと実在するパスの照合結果 | 2 |
| `action-scripts/shared/entities/deployment_target.rb` | matrix の固定キー、属性、抽出値、対象の同一性 | 3 |
| `action-scripts/label-resolver/use_cases/determine_target_environment.rb`, `action-scripts/label-resolver/use_cases/generated_matrix.rb` | 環境選択と対象列挙 | 3 |
| `action-scripts/label-resolver/application.rb`, `action-scripts/label-resolver/bin/resolver` | ファイルクライアントの注入と CLI 入力の解析 | 3 |
| `action-scripts/label-dispatcher/use_cases/detect_changed_services.rb`, `action-scripts/label-dispatcher/controllers/label_dispatcher_controller.rb` | 照合単位の除外とサービスラベル生成 | 4 |
| `action-scripts/shared/interfaces/presenters/console_presenter.rb`, `action-scripts/shared/interfaces/presenters/github_actions_presenter.rb` | dispatch・設定・サービス診断の表示 | 4, 5 |
| `action-scripts/config-manager/controllers/config_manager_controller.rb`, `action-scripts/config-manager/application.rb`, `action-scripts/config-manager/bin/config-manager` | 設定表示、環境一覧、サービス診断、テンプレート | 5 |
| `action-scripts/workflow-config.yaml`, `README.md`, `README-ja.md` | 実行可能な設定例と設定・matrix の説明 | 5 |
| `action-scripts/config-manager/README.md`, `action-scripts/config-manager/README-ja.md` | CLI コマンドと設定表示の説明 | 5 |
| `action-scripts/label-resolver/README.md`, `action-scripts/label-resolver/README-ja.md` | ラベルからの対象列挙と環境選択の説明 | 5 |
| `action-scripts/label-dispatcher/README.md`, `action-scripts/label-dispatcher/README-ja.md` | 変更照合と除外によるラベル生成の説明 | 5 |

`PatternMatcher.placeholders(pattern)`、`expand(pattern, values)`、`extract(pattern, path)`、`extract_prefix(pattern, path)` の既存 signature を使う。placeholder の文法を別のクラスへ複製しない。GitHub API クライアント、ラベル管理、設定コピーの JavaScript、composite action の入出力はこの計画の変更対象に含めない。

## Execution Preparation

- [ ] **Step 1: Read the approved documents and repository rules**

設計書、本計画、AGENTS.md、存在する CLAUDE.md を読む。実行方式の承認と、設計書の15項目が計画のどのタスクに対応するかを確認した時点で完了とする。

- [ ] **Step 2: Prepare the implementation workspace**

`superpowers:using-git-worktrees` の手順で隔離環境を準備する。ブランチ名・作業パス・既存 Draft PR を継続するか新しい Draft PR にするかを記録する。ユーザーの未コミット変更を含めず、実装用ブランチであることを `git status --short --branch` で確認した時点で完了とする。

- [ ] **Step 3: Confirm the runtime and dependency setup**

`action-scripts` を作業ディレクトリとして `ruby --version`、`bundle --version`、`bundle check` を実行し、リポジトリの指定と整合することを確認する。不足がある場合は既存 lockfile に従って環境を用意し、指定ファイルを書き換えない。

以降のテストコマンドは `action-scripts` で実行する。テストはフォアグラウンドで実行し、実行者が完了を待ち、終了コードと標準出力・標準エラーを記録する。中断が必要な場合は実行者が停止する。追加の常駐プロセスを起動しない。

## Shared Test Inputs

Task 1 で `:workflow_config` の `config_hash` を次のデータへ置き換える。`default_test_config` は `attributes_for(:workflow_config).fetch(:config_hash).to_yaml` から取得し、別のスキーマ例を重複して管理しない。

```yaml
stacks:
  - name: terragrunt
    id: aws
    paths:
      - "dystopia/{service}/aws/{environment}"
      - "system-components/{service}/infrastructure/aws/{environment}"
    environments:
      develop:
        aws_region: ap-northeast-1
      production:
        aws_region: us-west-2
    exclude: []
  - name: container
    paths:
      - "dystopia/{service}"
      - "system-components/{service}"
    attributes:
      repository: registry.example.com/app
```

各タスクで必要な構成は、その spec の `let(:config_hash)` に明記して `Entities::WorkflowConfig.new(config_hash)` で読む。旧メソッドを mock して新モデルを模倣しない。実在ディレクトリを使う spec は `Dir.mktmpdir` のブロック内で作成・削除を完結させ、変更した環境変数を元の値へ戻す。

## Task 1: Configuration Model

**Files:**

- Modify: `action-scripts/shared/entities/workflow_config.rb`
- Modify: `action-scripts/shared/infrastructure/config_client.rb`
- Modify: `action-scripts/config-manager/use_cases/validate_config.rb`
- Modify: `action-scripts/spec/factories.rb`
- Modify: `action-scripts/spec/spec_helper.rb`
- Test: `action-scripts/spec/shared/entities/workflow_config_spec.rb`
- Test: `action-scripts/spec/shared/infrastructure/config_client_spec.rb`
- Test: `action-scripts/spec/config-manager/use_cases/validate_config_spec.rb`

**Interfaces:**

- Consumes: `Entities::PatternMatcher.placeholders(pattern)` → `Array<String>`、既存の `Entities::Result.success(**data)` と `failure(error_message:, **data)`。
- Produces: `Entities::WorkflowConfig.new(config_hash)` → 検証済みモデル。不正な設定は位置と理由を含む `ArgumentError`。
- Produces: `WorkflowConfig#stacks` → 文字列キーの正規化した stack マップの配列。`id` は確定値、`exclude` は省略時 `[]`、環境共通の `attributes` は省略時 `{}`。`environments` の有無は保持する。
- Produces: `WorkflowConfig#environment_names` → 各 stack の環境名の和集合を、最初に現れた順序で返す `Array<String>`。
- Produces: `WorkflowConfig#excluded?(stack, values)` → `Boolean`。`stack` は `#stacks` の要素、`values` は文字列キーのマップで、`service`・`environment` と存在する任意の抽出値を含む。
- Preserves: `Infrastructure::ConfigClient#load_workflow_config`、`#clear_cache`。
- Produces: `UseCases::ConfigManagement::ValidateConfig#execute` → 成功時 `Result` の `valid: true`・`config`・`validation_summary`、失敗時 `error_message`・`validation_errors`。

- [ ] **Step 1: Write model, exclusion, and loading tests**

共通 fixture を新形式へ変更するテストと、次の除外テストを追加する。

```ruby
it 'matches fixed and declared placeholder conditions' do
  config = described_class.new('stacks' => [{
    'name' => 'terragrunt',
    'paths' => ['{team}/{service}/aws/{environment}'],
    'environments' => { 'develop' => {}, 'production' => {} },
    'exclude' => [
      { 'team' => 'platform', 'service' => 'demo', 'environment' => 'production' },
      { 'team' => 'sandbox' }
    ]
  }])
  stack = config.stacks.first

  expect(config.excluded?(stack, 'team' => 'platform', 'service' => 'demo', 'environment' => 'production')).to be(true)
  expect(config.excluded?(stack, 'team' => 'platform', 'service' => 'demo', 'environment' => 'develop')).to be(false)
  expect(config.excluded?(stack, 'team' => 'sandbox', 'service' => 'api', 'environment' => 'develop')).to be(true)
  expect(config.excluded?(stack, 'service' => 'demo', 'environment' => 'production')).to be(false)
end
```

以下の入力とアサーションを個別の example またはパラメーター化した example にする。

| Test name | Input and assertion |
|---|---|
| `resolves identities and environment names` | 共通 fixture の `stacks.map { \|s\| s['id'] } == ['aws', 'container']`、`environment_names == ['develop', 'production']`、共通 stack の `environment_names` への追加はない |
| `normalizes relative paths` | `./dystopia/{service}/` → `dystopia/{service}`。入力マップを変更せず正規化したモデルを返す |
| `accepts environment attributes without required keys` | `develop: { aws_region: 'ap-northeast-1' }` と `production: { token: nil }` を受け付け、値と型を保持する |
| `matches single fixed conditions` | `exclude: [{ service: 'demo' }]` は demo の両環境に一致し、`[{ environment: 'production' }]` は production の全サービスに一致する |
| `matches common targets with null environment` | `environments` のない stack の `{ service: 'demo' }` と `{ environment: nil }` は該当する共通対象に一致する |
| `limits exclusion keys to the owning stack` | 自身の `paths` にない `team` と属性名 `aws_region` は、位置 `stacks[0].exclude[0]` を含むエラーになる。他 stack の `{team}` は許可根拠にしない |
| `rejects empty conditions and invalid values` | `{}`、数値・配列・空文字・`a/b`・`.`・`..`、service の `.hidden`、environment 以外の nil を拒否する |
| `validates environment conditions when present` | 環境名の省略を受け付け、未定義の環境名と環境共通 stack の非 nil 環境名を拒否する |
| `rejects invalid schema shapes` | nil・配列のトップレベル、空・非配列の stacks、非マップの stack、空・非文字列の name/id、重複 identity、空・非配列の paths と空・非文字列のパターン、空・非マップの environments、非マップの属性・exclude 要素を拒否する |
| `rejects unknown fields and mixed attributes` | トップレベルの services/stack_conventions/environments、stack の root/directory/required_attributes、未知キー、attributes と environments の併用を拒否する |
| `validates environment names and attribute keys` | 環境名の空文字・非文字列・`a/b`・`.`・`..`、属性キーの空文字・非文字列・固定5キーとの衝突を拒否する |
| `validates paths and placeholder collisions` | 絶対パス、`..` 要素、service の欠落、不正・閉じていない placeholder、環境共通の `{environment}`、固定5キーや当該 stack の全環境の属性キーと任意 placeholder の衝突を拒否する |
| `limits attribute collisions to the owning stack` | 同じ stack の衝突は拒否し、別 stack の属性キーと placeholder 名が同じ場合は受け付ける |

`ConfigClient` は成功時のキャッシュ、ファイル欠落・権限・YAML 行番号のエラー、モデルの検証位置が伝わることをテストする。`ValidateConfig` は成功サマリーが `stacks: 2`・`environments: 2` を含み、読み込み失敗では `validation_errors` に元のエラーを保持することをテストする。

- [ ] **Step 2: Confirm the tests fail for the old model**

Run: `bundle exec rspec spec/shared/entities/workflow_config_spec.rb spec/shared/infrastructure/config_client_spec.rb spec/config-manager/use_cases/validate_config_spec.rb`

Expected: 新形式または新アクセサー・除外判定の assertion が FAIL。環境や require の不備は先に解消し、仕様に対する失敗を記録する。

- [ ] **Step 3: Implement the model and remove duplicate validation**

`WorkflowConfig` の constructor で構造・型・整合性を検証し、その後に id と相対パスを正規化する。除外キーの許可範囲は `PatternMatcher.placeholders` から収集する。除外判定は `values.key?(key) && values[key] == expected` を条件内の全キーに要求し、規則の配列のいずれかが一致した場合だけ true にする。

`ConfigClient` の `validate_config!`・`validate_config_file`・サマリー生成を削除し、ファイルと YAML の処理後に `WorkflowConfig.new` を呼ぶ。`ValidateConfig` は読み込み済みモデルからサマリーを作り、個別のスキーマ検証を持たない。サマリーは stack 数と環境数を表示し、登録サービス数・除外理由・種別の統計を表示しない。

旧 convention・service・属性探索のメソッドと、製品コードに呼び出しのない `raw_config` アクセサー・`safety_check_enabled?` を削除する。旧 `with_excluded_service` trait を `with_target_exclusions` に置き換え、aws stack に service と environment の条件を設定する。旧形式の振る舞いテストは新仕様のテストへ置き換え、旧形式の拒否を検証する入力だけに旧フィールド名を残す。

- [ ] **Step 4: Confirm the model tests pass**

Step 2 と同じコマンドを実行する。Expected: exit 0、`0 failures`。完了条件は、旧アクセサーを使わずに3ファイルのテストが通ることである。

- [ ] **Step 5: Commit the configuration model**

Files に列挙した変更を指定して stage し、`git diff --cached --check` が exit 0 であることを確認する。

Run: `git commit -s -m 'feat: define stack configuration and exclusion conditions'`

## Task 2: Directory Resolution

**Files:**

- Modify: `action-scripts/shared/infrastructure/file_system_client.rb`
- Modify: `action-scripts/spec/spec_helper.rb`
- Create/Test: `action-scripts/spec/shared/infrastructure/file_system_client_spec.rb`

**Interfaces:**

- Consumes: `PatternMatcher::PLACEHOLDER_REGEX`、`PatternMatcher.extract(pattern, relative_path)` → 抽出値のマップまたは nil。
- Produces: `FileSystemClient#repository_root(start_path: __dir__)` → 絶対パスの `String`。既存 matrix の SOURCE_REPO_PATH と親ディレクトリの `.git` 探索を移し、`.git` はファイルとディレクトリの双方を受け付ける。
- Produces: `FileSystemClient#resolve_directories(pattern:, values: {})` → `Array<Hash>`。各要素は `{ working_directory: String, captures: Hash<String, String> }`。相対パスを昇順で返す。`values` はパターンに現れるキーだけを照合し、その placeholder の値を完全一致させる。
- Preserves: `FileSystemClient#get_changed_files(base_ref: nil, head_ref: nil)` の既存 signature と Git diff 処理。

- [ ] **Step 1: Write directory and root tests using temporary repositories**

`tmpdir` と `fileutils` を spec で読み、ブロック内で `.git` とディレクトリを作る。以下を assertion にする。

```ruby
expect(client.resolve_directories(
  pattern: 'teams/{team}/{service}/aws/{environment}',
  values: { 'service' => 'demo', 'environment' => 'production' }
)).to eq([
  { working_directory: 'teams/platform/demo/aws/production',
    captures: { 'team' => 'platform', 'service' => 'demo', 'environment' => 'production' } },
  { working_directory: 'teams/sandbox/demo/aws/production',
    captures: { 'team' => 'sandbox', 'service' => 'demo', 'environment' => 'production' } }
])
```

この example の client は `described_class.new`、SOURCE_REPO_PATH は作成した一時リポジトリとする。同じリポジトリに別サービス、develop、通常ファイルを作り、いずれも返らないことを確認する。

追加 example は `matches repeated placeholders`、`treats glob characters as literals`、`ignores context keys absent from the pattern`、`returns no matches for absent directories`、`uses the source repository root`、`accepts git marker files`、`fails when no repository root exists` とする。繰り返しは `teams/{team}/{service}/{team}` で同じ team だけが一致し、リテラルは `literal[1]/{service}` で `literal1` を返さないことを確認する。`dystopia/{service}/aws` に environment=production の既知値を渡しても実在するパスを返すことを確認する。`Dir.glob` が `Errno::EACCES` を返した場合は、そのエラーが呼び出し側へ届くことを確認する。

- [ ] **Step 2: Confirm the directory tests fail**

Run: `bundle exec rspec spec/shared/infrastructure/file_system_client_spec.rb`

Expected: `resolve_directories` と `repository_root` の未実装による FAIL。

- [ ] **Step 3: Implement exact directory resolution**

既存の未使用 `find_directories(pattern)` を置き換え、上記2メソッドを公開する。glob はリテラルを escape し、placeholder だけを候補列挙用の `*` にする。`Dir.glob(..., base: repository_root)` の結果を、実在ディレクトリ・`PatternMatcher.extract`・既知値の一致で絞る。繰り返した placeholder の一致は `PatternMatcher` に任せる。

`spec_helper` の全 example に対する test-service/demo の `File.directory?` mock を削除する。各 spec に必要なディレクトリを作り、通常ファイルがディレクトリとして誤認されないことをテストする。Git diff の既存処理は変更しない。

- [ ] **Step 4: Confirm the directory tests pass**

Step 2 と同じコマンドを実行する。Expected: exit 0、`0 failures`。実在しないディレクトリの戻り値が `[]`、列挙エラーが例外であることを確認して完了とする。

- [ ] **Step 5: Commit directory resolution**

Files の変更を stage して `git diff --cached --check` を実行する。

Run: `git commit -s -m 'feat: resolve stack paths from repository directories'`

## Task 3: Environment Selection and Matrix

**Files:**

- Modify: `action-scripts/shared/entities/deployment_target.rb`
- Modify: `action-scripts/label-resolver/use_cases/determine_target_environment.rb`
- Modify: `action-scripts/label-resolver/use_cases/generated_matrix.rb`
- Modify: `action-scripts/label-resolver/application.rb`
- Modify: `action-scripts/label-resolver/bin/resolver`
- Modify: `action-scripts/spec/factories.rb`
- Test: `action-scripts/spec/shared/entities/deployment_target_spec.rb`
- Test: `action-scripts/spec/label-resolver/use_cases/determine_target_environment_spec.rb`
- Test: `action-scripts/spec/label-resolver/use_cases/generate_matrix_spec.rb`
- Test: `action-scripts/spec/label-resolver/controllers/label_resolver_controller_spec.rb`
- Create/Test: `action-scripts/spec/label-resolver/cli_spec.rb`

**Interfaces:**

- Consumes: Task 1 の `WorkflowConfig#stacks`・`#environment_names`・`#excluded?`、Task 2 の `FileSystemClient#resolve_directories`。
- Produces: `DetermineTargetEnvironment#execute(target_environments:)` → 成功時 `Result(target_environments: Array<String>)`。nil または `[]` は全環境、指定値は重複を除去し、未知名は failure。旧 `environment_configs` は返さない。
- Produces: `GenerateMatrix.new(config_client:, file_client:)` と `#execute(deploy_labels:, target_environments:)` → 成功時 `deployment_targets`・`has_deployments`・`total_targets`、失敗時 `error_message` を持つ `Result`。
- Produces: `DeploymentTarget.new(service:, stack:, stack_id:, working_directory:, environment: nil, attributes: {}, captures: {})`。stack_id は確定値を要求する。
- Produces: `DeploymentTarget#to_matrix_item` → Symbol キーの固定5フィールドと、属性・任意の抽出値を展開したマップ。`#==`・`#eql?`・`#hash` の識別要素は service・stack_id・environment・working_directory。
- Produces: `LabelResolverCLI#parse_environments(env_string)` → 入力省略・空白だけなら `[]`、それ以外は comma 分割して strip した文字列配列。環境名の検証は use case に任せる。

- [ ] **Step 1: Write environment, target, and matrix behavior tests**

環境選択は入力 nil・空配列・重複・未知名・環境共通だけの設定をテストする。`['production', 'production']` の結果が `['production']`、未知名 `preview` が failure、共通だけの構成の既定値が `[]` になることを確認する。

matrix の spec は一時リポジトリと実モデルを使う。生成対象を `to_matrix_item` に変換し、以下の入力・結果を個別 example にする。

| Test name | Input and assertion |
|---|---|
| `generates every shared product path` | 共通 fixture の2プロダクトに demo の両環境を作る。aws は4行、container は2行。各 aws 行のリージョンは自身の環境の値 |
| `keeps independent identities distinct` | 同じ terragrunt、id が dystopia-aws/system-components-aws の定義から各属性を持つ2行を生成する |
| `limits each stack to its declared environments` | aws は develop のみ、別 stack は production のみ。両方選択しても各 stack は1環境分で、aws の production ディレクトリは対象にならない |
| `reuses a directory across declared environments` | path が `dystopia/{service}/aws`、develop/production の属性が異なる。同じ working_directory で環境と属性が異なる2行を返す |
| `generates common targets once with attributes` | 環境共通だけの container 設定と両環境選択の設定で、各ディレクトリ1行・environment nil・repository 属性が得られる |
| `discovers services for all labels` | `deploy:all` は実在する demo/api を列挙し、未登録サービスも対象にする。`deploy:all` と `deploy:demo` の併用でも同じ対象は増えない |
| `resolves every arbitrary placeholder value` | teams/platform と teams/sandbox に demo を作る。各 team の値を持つ2行を返す |
| `applies fixed and arbitrary exclusion conditions` | service のみ・environment のみ・team のみ・組み合わせの除外で該当する行だけを除く。環境名がないパスにも環境条件を適用する |
| `does not match missing captures` | 同じ stack に `teams/{team}/{service}/aws/{environment}` と `dystopia/{service}/aws/{environment}` を置く。team 条件は前者の該当 team だけを除く |
| `deduplicates targets and rejects conflicting captures` | 同じパスの重複は1行。`teams/{team}/{service}/aws` と `teams/{product}/{service}/aws` が同じ対象に一致した場合は failure。除外条件と記載順を変えても failure |
| `returns failures without partial targets` | 途中のディレクトリ列挙エラー・未知の環境で failure、`deployment_targets` は返さない。存在しないディレクトリは正常な空配列 |

`DeploymentTarget` の spec は固定5キー、属性値の型、capture の衝突、stack_id が異なる対象の不一致、同一対象の `hash` 一致を assertion にする。CLI の spec は bin を require してもコマンドが起動しないこと、nil・空白・`' develop,production '` の解析をテストする。controller の spec は検証済み環境配列を生成と表示へ渡すことを確認する。

- [ ] **Step 2: Confirm the resolver tests fail**

Run: `bundle exec rspec spec/shared/entities/deployment_target_spec.rb spec/label-resolver`

Expected: 新しい constructor、環境選択、複数パス、除外、固定5キーの assertion が FAIL。

- [ ] **Step 3: Implement target generation from stack definitions**

`application.rb` から `FileSystemClient` を注入する。`DetermineTargetEnvironment` は `environment_names` を使い、`GenerateMatrix` も直接呼び出された場合に環境名を検証する。matrix の入力 nil・空配列も全環境として扱い、既定値・重複除去・未知名の判定は両 use case で同じ値になるようテストする。

matrix は stack ごとに選択環境と定義環境の共通部分、または環境共通の `[nil]` を使う。各 paths を `resolve_directories` で列挙し、通常ラベルでは service、全体ラベルでは全サービスを照合する。任意の placeholder はすべての一致を対象にする。サービス名が `.` で始まる一致を対象にしない。

候補の識別4要素で重複を確認し、同じ対象で異なる capture マップが得られた場合は failure にする。矛盾を確認した後で `excluded?` を適用する。属性は当該 stack の環境マップまたは attributes から取得する。capture から service と environment を除き、固定フィールドへ渡す。

旧 convention の探索、属性の名前への fallback、最初のパスへの収束、サービス登録、root の推測、旧ディレクトリ解決の補助メソッドを削除する。`DeploymentTarget` と factory の `stack_convention_root` を削除し、同一性を stack_id に揃える。bin の実行末尾を `$PROGRAM_NAME == __FILE__` で guard し、環境一覧の既定値を補う `all_environments` を削除する。

- [ ] **Step 4: Confirm the resolver tests pass**

Step 2 と同じコマンドを実行する。Expected: exit 0、`0 failures`。行数・属性・capture を実在ディレクトリで確認し、旧メソッドの mock が残っていない時点で完了とする。

- [ ] **Step 5: Commit environment selection and matrix generation**

Files の変更を stage して `git diff --cached --check` を実行する。

Run: `git commit -s -m 'feat: generate deployment targets from stack definitions'`

## Task 4: Changed Service Detection

**Files:**

- Modify: `action-scripts/label-dispatcher/use_cases/detect_changed_services.rb`
- Modify: `action-scripts/label-dispatcher/controllers/label_dispatcher_controller.rb`
- Modify: `action-scripts/shared/interfaces/presenters/console_presenter.rb`
- Modify: `action-scripts/shared/interfaces/presenters/github_actions_presenter.rb`
- Test: `action-scripts/spec/label-dispatcher/use_cases/detect_changed_services_spec.rb`
- Test: `action-scripts/spec/label-dispatcher/controllers/label_dispatcher_controller_spec.rb`
- Create/Test: `action-scripts/spec/shared/interfaces/presenters/console_presenter_spec.rb`
- Create/Test: `action-scripts/spec/shared/interfaces/presenters/github_actions_presenter_spec.rb`

**Interfaces:**

- Consumes: Task 1 の設定と除外判定、`PatternMatcher.extract_prefix(pattern, changed_file)`、`PatternMatcher.expand(pattern, values)` → `String`、既存 `FileSystemClient#get_changed_files`。
- Produces: `DetectChangedServices#execute(base_ref: nil, head_ref: nil)` → 成功時 `deploy_labels`・`changed_files`・`services_detected`、失敗時 `error_message` を持つ `Result`。
- Produces: 両 presenter の `#present_label_dispatch_result(deploy_labels:, labels_added:, labels_removed:, changed_files:)`。controller はこの signature で呼び出す。

- [ ] **Step 1: Write per-match exclusion and output tests**

変更ファイル `teams/platform/demo/aws/production/main.tf` に対し、team=platform・service=demo・environment=production の条件でラベルを生成しないことをテストする。同じ設定で develop の変更を加えると `deploy:demo` を生成することをテストする。

追加 example は `detects only declared stack paths`、`ignores undeclared environments`、`evaluates every environment for paths without environment`、`keeps services with a non-excluded stack match`、`does not exclude paths missing custom captures`、`detects common stacks with null environment`、`rejects conflicting captures before exclusions` とする。サービスディレクトリのパスを定義しない設定で、その兄弟ファイルだけが変わった場合にラベルを生成しないことを assertion にする。Task 3 と同じ team/product の衝突を持つパスで、除外条件やパス順序にかかわらず failure を返すことを確認する。

controller の spec は presenter 呼び出しから `excluded_services` が消えることを確認する。GitHub presenter の spec は一時ファイルを `GITHUB_ENV`・`GITHUB_OUTPUT` とし、現行公開 outputs のラベル・サービス・変更有無が出力され、`EXCLUDED_SERVICES`・`HAS_EXCLUDED_SERVICES`・`excluded-services`・`has-excluded-services` が出力されないことを確認する。Console presenter の spec は、ラベルとサービス結果を表示することを確認する。

- [ ] **Step 2: Confirm the dispatcher tests fail**

Run: `bundle exec rspec spec/label-dispatcher spec/shared/interfaces/presenters`

Expected: stack 別・照合別の判定と旧除外出力の assertion が FAIL。

- [ ] **Step 3: Implement service detection from valid matches**

stack と paths を走査し、変更ファイルから service・環境・任意の placeholder を抽出する。サービス名が `.` で始まる照合は対象にしない。環境名がパスにある場合は当該 stack の定義内であることを確認し、ない場合は定義された各環境、環境共通なら nil を使う。`PatternMatcher.expand(pattern, captures)` で照合したディレクトリを確定し、service・stack_id・environment・working_directory が同じ照合の抽出値が矛盾する場合は failure にする。その後に各照合を `excluded?` で判定し、除外されない照合が一つでもあるサービスを一度だけラベル対象にする。

全体のサービス除外、理由・種別のログ、旧結果フィールド、controller と presenter の旧引数・内部環境変数・内部出力を削除する。対象を列挙する際に filesystem の存在は要求せず、削除されたファイルの変更パスにも同じ照合を適用する。

- [ ] **Step 4: Confirm the dispatcher tests pass**

Step 2 と同じコマンドを実行する。Expected: exit 0、`0 failures`。除外された照合だけのサービスと、除外されない照合を持つサービスの双方を確認して完了とする。

- [ ] **Step 5: Commit changed service detection**

Files の変更を stage して `git diff --cached --check` を実行する。

Run: `git commit -s -m 'feat: apply stack exclusions to changed service matches'`

## Task 5: Configuration Commands and Examples

**Files:**

- Modify: `action-scripts/config-manager/controllers/config_manager_controller.rb`
- Modify: `action-scripts/config-manager/application.rb`
- Modify: `action-scripts/config-manager/bin/config-manager`
- Modify: `action-scripts/shared/interfaces/presenters/console_presenter.rb`
- Modify: `action-scripts/shared/interfaces/presenters/github_actions_presenter.rb`
- Modify: `action-scripts/workflow-config.yaml`
- Modify: `README.md`, `README-ja.md`
- Modify: `action-scripts/config-manager/README.md`, `action-scripts/config-manager/README-ja.md`
- Modify: `action-scripts/label-resolver/README.md`, `action-scripts/label-resolver/README-ja.md`
- Modify: `action-scripts/label-dispatcher/README.md`, `action-scripts/label-dispatcher/README-ja.md`
- Test: `action-scripts/spec/config-manager/controllers/config_manager_controller_spec.rb`
- Test: `action-scripts/spec/shared/interfaces/presenters/console_presenter_spec.rb`
- Test: `action-scripts/spec/shared/interfaces/presenters/github_actions_presenter_spec.rb`
- Create/Test: `action-scripts/spec/config-manager/cli_spec.rb`

**Interfaces:**

- Consumes: Task 1 のモデル、Task 2 のディレクトリ解決、Task 3 の `DeploymentTarget`。
- Produces: `ConfigManagerController.new(validate_config_use_case:, config_client:, file_client:, presenter:)`。
- Produces: `ConfigManagerController#test_service_configuration(service_name:, environment: nil)` → `present_service_test_result(service_name:, matches:)` を呼ぶ。環境省略時は全定義環境と環境共通を診断する。
- Produces: `matches` → `Array<Hash>`。各要素は `{ target: Entities::DeploymentTarget, excluded: Boolean }`。除外対象も状態を表示し、登録サービスを要求しない。
- Preserves: `#validate_configuration`・`#show_configuration`・`#run_diagnostics`・`#generate_config_template`、presenter の `#present_config_details(config:)` と `#present_config_template(template:)`。
- Produces: `ConfigManagerCLI#test(service_name, environment = nil)` と `#environments`。`services` と `excluded_services` のコマンドは削除する。

- [ ] **Step 1: Write configuration display and diagnostic tests**

`show_configuration` がそのまま検証済みモデルを presenter へ渡すこと、両 presenter が stack_id ごとに全パス・各環境属性または共通属性・除外条件を表示することをテストする。非 AWS 属性 `repository` と `token` が表示されることを assertion にする。

サービス診断は一時リポジトリの demo を使い、登録なしで2プロダクトの各ディレクトリを表示すること、環境省略時に共通 stack を一度だけ表示すること、指定した環境の属性を保持すること、除外対象に `excluded: true` が付くこと、空の一致が空配列になることをテストする。識別4要素の重複は一行、異なる captures は error にする。

```ruby
it 'generates a template accepted by the configuration model' do
  template = controller.send(:build_config_template)
  config = Entities::WorkflowConfig.new(YAML.safe_load(template))

  expect(config.stacks.map { |stack| stack['id'] }).to include('aws', 'container')
  expect(config.environment_names).to include('develop', 'production')
end
```

CLI の spec は require 時の自動起動がないこと、environments が和集合を表示すること、削除した2コマンドが Thor の登録コマンドにないことを確認する。テンプレートとリポジトリの sample YAML が同じモデルで検証できるテストを追加する。

- [ ] **Step 2: Confirm the configuration command tests fail**

Run: `bundle exec rspec spec/config-manager spec/shared/interfaces/presenters`

Expected: 新しい診断引数、汎用属性の表示、旧コマンドの削除、新形式のテンプレートで FAIL。

- [ ] **Step 3: Implement configuration commands and update their documentation**

Config manager にファイルクライアントを注入する。診断は stack ごとに環境を選択し、各パスを Task 2 のメソッドで解決する。属性・capture を持つ `DeploymentTarget` と Task 1 の除外判定を組にして presenter へ渡す。未知の環境・設定・列挙・capture の矛盾は `present_error` へ伝える。

設定表示は属性名を列挙し、特定のプロバイダーのキーを前提にしない。CLI の environments は `environment_names` を表示する。bin の末尾を `$PROGRAM_NAME == __FILE__` で guard し、旧サービス一覧と旧除外一覧を削除する。テンプレートは stacks だけの新スキーマを生成し、YAML に説明コメントを付けない。

sample と README の設定例・matrix 出力・除外説明・コマンド例を変更する。設定スキーマと matrix の説明は root README を参照先とし、各 component README には担当するコマンドとその結果を記載する。本文を同じ媒体間で複製せず、新しい見出しを英語・新しい本文を日本語にする。現在の仕様として示す旧形式の例、旧コマンド、旧 root 出力を残さない。履歴文書は変更しない。

- [ ] **Step 4: Confirm configuration command tests pass**

Run: `bundle exec rspec spec/config-manager spec/shared/interfaces/presenters`

Expected: exit 0、`0 failures`。

- [ ] **Step 5: Confirm the complete suite passes**

Run: `bundle exec rspec`

Expected: exit 0、`0 failures`。

- [ ] **Step 6: Validate the sample configuration through the CLI**

Run: `bundle exec ruby config-manager/bin/config-manager validate`

Expected: exit 0、`Configuration is valid` と新モデルの stack・環境数のサマリー。

- [ ] **Step 7: Confirm stack configuration display through the CLI**

Run: `bundle exec ruby config-manager/bin/config-manager show`

Expected: exit 0、各 stack のパス・属性・除外条件を表示する。

- [ ] **Step 8: Review removal scope and added comments**

リポジトリルートで次を実行し、旧モデルに依存する製品コード・fixture・現在の設定例が検索結果に残っていないことを確認する。旧形式を拒否するテスト入力は残してよい。`rg` の exit 1 は該当なしを表す。

Run: `rg -n 'stack_conventions|stack_convention_root|directory_stacks|required_attributes|exclude_from_automation|exclusion_config|excluded_services|EXCLUDED_SERVICES|HAS_EXCLUDED_SERVICES|environment_configs|all_directory_patterns|stack_attributes_for' action-scripts label-dispatcher label-resolver README.md README-ja.md`

`git diff` に現れた追加・変更コメントをすべて AGENTS.md の Content Rules と照合し、複数行・自明な説明・タスクへの言及を削除する。Files 外の変更がないことを確認し、`git diff --check` が exit 0 であることを完了条件にする。

- [ ] **Step 9: Review the implementation**

`superpowers:requesting-code-review` を適用し、計画と設計書の要件、除外判定、全利用側の旧モデル削除をレビューする。指摘を解消し、変更した箇所に必要な検証を再実行した時点で完了とする。

- [ ] **Step 10: Commit the configuration commands and examples**

Files の変更を指定して stage し、`git diff --cached --check` を実行する。

Run: `git commit -s -m 'feat: expose stack configuration through config commands'`

- [ ] **Step 11: Publish the branch as a Draft PR**

`superpowers:verification-before-completion` を適用して、コミット内容と検証結果を確認する。新規ブランチなら `git push -u origin HEAD`、追跡済みなら `git push` を実行する。既存 Draft PR を継続する場合は設計と実装をレビューできる説明へ更新し、新規 PR なら `gh pr create --draft` を使う。PR が Draft、タイトルが英語、変更ファイルと検証結果が確認できる時点で完了とする。

## Coverage Map

| Spec verification criteria | Tasks |
|---|---|
| 1–2: プロダクト間の共有と独立 | 1, 3, 5 |
| 3–5: 定義環境、共通対象、環境名がないパス | 1, 3, 4, 5 |
| 6: 複数一致と重複 | 2, 3, 5 |
| 7–9: 固定・任意キーと環境共通の除外 | 1, 3, 4, 5 |
| 10: 除外後の変更検出 | 4 |
| 11: deploy:all のディレクトリ探索 | 2, 3 |
| 12–13: 検証と旧形式の拒否 | 1, 3, 5 |
| 14: matrix 固定キー、属性、capture | 1, 3 |
| 15: Config manager とテンプレート | 1, 5 |
