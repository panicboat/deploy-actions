# Stack-grouped attributes for workflow-config.yaml

## Goal

`workflow-config.yaml` の environment 配下を stack 単位でグループ化し、stack 固有 attribute（`aws_region`, `iam_role_plan`, `iam_role_apply` 等）を任意化する。後段 action が必要とするキーは workflow-config.yaml の `stacks.<name>` 配下に書かれた値がそのまま `DeploymentTarget#attributes` に格納され、GitHub Actions matrix item にフラット展開される。

旧仕様では `aws_region` 等が environments 直下に必須でハードコードされており、AWS 非依存のスタック追加が困難だった。新仕様は「stack 仕様は workflow-config.yaml の宣言で決まる」方向に責務を分離する。

## Non-goals

- 後段 action（panicboat-actions / monorepo / platform の workflow ファイル）の参照キー名変更。matrix item のキー名は維持する。
- フラット形式（旧スキーマ）との後方互換レイヤ。同 PR で全 spec / fixtures を新スキーマに書き換える。
- AWS region / IAM ARN の format バリデーション。汎用化のため廃止。
- `DeployLabel`, `Result`, `find_repository_root`, label-dispatcher 周辺の挙動変更。

## New schema

### Environment with stack-grouped attributes

```yaml
environments:
  - environment: develop
    stacks:
      terragrunt:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::559744160976:role/github-oidc-auth-develop-github-actions-role
        iam_role_apply: arn:aws:iam::559744160976:role/github-oidc-auth-develop-github-actions-role
      kubernetes: {}
  - environment: staging
    stacks:
      terragrunt:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::123456789012:role/terragrunt-plan-staging-role
        iam_role_apply: arn:aws:iam::123456789012:role/terragrunt-apply-staging-role
  - environment: production
    stacks:
      terragrunt:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::123456789012:role/terragrunt-plan-production-role
        iam_role_apply: arn:aws:iam::123456789012:role/terragrunt-apply-production-role

stack_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        required_attributes: [aws_region, iam_role_plan, iam_role_apply]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

services:
  - name: demo
    exclude_from_automation: true
    exclusion_config:
      reason: "The demo service is for learning purposes, so the directory structure is completely different."
      type: permanent
```

### Schema rules

- `environments[].environment` は必須。
- `environments[].stacks` は省略可（全 stack で attribute 不要なケース）。書く場合は Hash で、キーは stack 名、値は任意キー / 任意値の Hash。値は YAML scalar（string / number / boolean）を想定。
- `stack_conventions[].stacks[].required_attributes` は省略可。配列で書く場合、要素は文字列（attribute 名）。空配列 `[]` は「必須なし」と同義。
- `aws_region` という名前のキーが書かれていても format チェックは行わない（汎用化）。

## Component design

### `Entities::DeploymentTarget`

```ruby
module Entities
  class DeploymentTarget
    attr_reader :service, :environment, :stack,
                :working_directory, :stack_convention_root, :attributes

    def initialize(service:, stack:, working_directory:,
                   environment: nil, stack_convention_root: nil,
                   attributes: {})
      raise ArgumentError, "service is required"           if service.nil?           || service.empty?
      raise ArgumentError, "stack is required"             if stack.nil?             || stack.empty?
      raise ArgumentError, "working_directory is required" if working_directory.nil? || working_directory.empty?

      @service                    = service
      @environment                = environment
      @stack                      = stack
      @working_directory          = working_directory
      @stack_convention_root = stack_convention_root
      @attributes                 = attributes.freeze
    end

    def to_matrix_item
      {
        service: service,
        environment: environment,
        stack: stack,
        working_directory: working_directory,
        stack_convention_root: stack_convention_root,
      }.merge(attributes.transform_keys(&:to_sym))
    end

    def ==(other)
      return false unless other.is_a?(DeploymentTarget)
      [service, environment, stack, working_directory] ==
        [other.service, other.environment, other.stack, other.working_directory]
    end

    def hash
      [service, environment, stack, working_directory].hash
    end

    alias eql? ==
  end
end
```

変更点：

- `aws_region`, `iam_role_plan`, `iam_role_apply` の attr_reader を削除。`target.attributes['aws_region']` で参照。
- `valid?` を削除。`new` 成功 = invariant 充足。
- stack 別 case/when を `to_matrix_item` から削除。`attributes` を symbol 化して merge するだけ。
- `stack:` のデフォルト値（旧 `'terragrunt'`）を削除し明示必須化。
- クラスメソッド `from_deploy_label_and_environment` は削除（`generate_matrix.rb` への一本化）。

### `Entities::WorkflowConfig`

新規メソッド：

- `stack_attributes_for(env_name, stack_name)` → Hash。`environments[env_name]&.dig('stacks', stack_name) || {}`。未定義 environment / 未定義 stack のいずれでも `{}` を返す。
- `required_attributes_for(stack_name)` → Array<String>。`stack_conventions_config` を順に走査し、最初に見つかった `stacks[].name == stack_name` の `required_attributes`（または `[]`）を返す。

既存の `environment_config(env)` は環境ハッシュ全体を返す（`stacks` キーを含む）。`stack_conventions_for`, `stack_convention_for`, `excluded_services`, `stack_convention_roots` 等は変更なし。

### `Infrastructure::ConfigClient#validate_config!`

- `aws_region` 必須チェックを削除。
- `environments[].stacks` がある場合、Hash であることを確認。各 stack の値も Hash であることを確認。
- `stack_conventions[].stacks[].required_attributes` がある場合、Array<String> であることを確認。

### `UseCases::ConfigManagement::ValidateConfig`

`validate_environment_config` を書き換え：

- 旧: `required_fields = %w[aws_region iam_role_plan iam_role_apply]` をハードコードチェック。
- 新: `stack_conventions` を走査し、各 stack の `required_attributes` について、当該 environment の `stacks.<stack>` 配下に当該キーが存在するか確認。`required_attributes` が未定義 / 空配列の場合はスキップ。

format チェック（AWS region / IAM ARN）は削除。

### `UseCases::LabelResolver::GenerateMatrix`

`create_terragrunt_target` / `create_kubernetes_target` / `create_generic_target` を 1 つの `create_deployment_target` に統合：

```ruby
def create_deployment_target(deploy_label, env, stack, working_dir, config)
  Entities::DeploymentTarget.new(
    service: deploy_label.service,
    environment: env,
    stack: stack,
    working_directory: working_dir,
    stack_convention_root: extract_root_from_working_dir(working_dir, deploy_label.service, env, config),
    attributes: env ? config.stack_attributes_for(env, stack) : {},
  )
end
```

`generate_deployment_target` の最後の case/when は削除。`target&.valid?` ガード（`generate_matrix.rb:98`）も削除（コンストラクタが raise）。

`env_config['iam_role_plan']` 等の直接参照は不要になる。

### Presenters

- `Interfaces::Presenters::GitHubActionsPresenter#present_service_test_result` および `Interfaces::Presenters::ConsolePresenter` の同名メソッドが `env_config['iam_role_plan']` 等を直接参照している。これらは表示用ヘルパであり、新スキーマでは `aws_region` / `iam_role_*` という名前自体が任意キーになる。実装フェーズで以下の方針で書き換える：
  - controller / use case から呼ばれている：`config.stack_attributes_for(env, 'terragrunt')` を渡す形に書き換え、表示は attributes hash の全キーを汎用的にループ表示する。
  - controller / use case から呼ばれていない（dead code）：削除する。
  - 呼び出し関係は実装着手時に grep で確定し、結果を実装計画に明記する。

### Matrix item output (label-resolver)

terragrunt target（後段 action 影響なし）：

```json
{
  "service": "foo",
  "environment": "develop",
  "stack": "terragrunt",
  "working_directory": "foo/terragrunt/develop",
  "stack_convention_root": "foo",
  "aws_region": "ap-northeast-1",
  "iam_role_plan": "arn:aws:iam::...",
  "iam_role_apply": "arn:aws:iam::..."
}
```

kubernetes target（旧仕様で副作用的に出力されていた `aws_region` が消える）：

```json
{
  "service": "foo",
  "environment": "develop",
  "stack": "kubernetes",
  "working_directory": "foo/kubernetes/overlays/develop",
  "stack_convention_root": "foo"
}
```

## Validation strategy

config-manager の検証は以下の順で実行：

1. `Infrastructure::ConfigClient#validate_config!`：YAML 構造の最低限の整合性（`environments` Array, `stack_conventions` Array, `stacks` Hash, `required_attributes` Array<String>）。
2. `Entities::WorkflowConfig#validate!`：必須セクション（environments / stack_conventions）の存在。
3. `UseCases::ConfigManagement::ValidateConfig`：stack_conventions に宣言された `required_attributes` を、各 environment の `stacks.<name>` 配下と突合。

`required_attributes: []` または未定義 → 検証スキップ（任意属性のみのスタックを許容）。

`DeploymentTarget#new` は invariant（service / stack / working_directory）を強制。validation が通ったあとの正常系では raise しない。

## Test strategy

### 書き換えが必要な spec

| ファイル | 主な変更 |
|---|---|
| `spec/factories.rb` | `:deployment_target` factory：`aws_region`/`iam_role_plan`/`iam_role_apply` を `attributes` hash に移動。`:workflow_config` factory：environments を新 stacks 構造に書き換え、stack_conventions に required_attributes を追加。 |
| `spec/shared/entities/workflow_config_spec.rb` | `stack_attributes_for`, `required_attributes_for` のテスト追加。旧 environment 直下属性のテスト削除。 |
| `spec/shared/entities/deployment_target_spec.rb` | （新規）コンストラクタ invariant raise、`to_matrix_item` のフラット展開、`==`/`hash` の同値性。 |
| `spec/config-manager/use_cases/validate_config_spec.rb` | required_attributes ベースの検証テストに置換。AWS region / IAM ARN format テスト削除。required_attributes 未定義 / 空配列の許容テスト追加。 |
| `spec/config-manager/controllers/config_manager_controller_spec.rb` | factory 経由で連動更新。 |
| `spec/label-resolver/use_cases/generate_matrix_spec.rb` | `target.aws_region` → `target.attributes['aws_region']` に書き換え。stack 別生成の case/when 廃止に伴うテスト整理。 |
| `spec/label-resolver/controllers/...` | factory 経由で連動更新。 |
| `spec/spec_helper.rb` | テスト用 workflow-config をベタ書きしている箇所を新スキーマに更新。 |

### 追加すべきテストケース

- `DeploymentTarget.new` が core 必須欠如（service / stack / working_directory のいずれか）で `ArgumentError` を raise。
- `to_matrix_item` で `attributes` のキーが symbol としてフラットに混入。
- `attributes` が空 hash の target でも matrix item が破綻しない（kubernetes 想定）。
- `WorkflowConfig#stack_attributes_for` が未定義 environment / 未定義 stack で `{}` を返す（KeyError でない）。
- `ValidateConfig` が `required_attributes: []` / 未定義のとき検証スキップ。
- `ValidateConfig` が environment.stacks に required_attributes のキーが無いとエラーを返す。

## Migration

1. 本リポジトリ（`deploy-actions`）の `workflow-config.yaml` を新スキーマに書き換え（同 PR 内）。
2. action-scripts のコード変更と spec 全更新を同 PR 内で完了。
3. 別 PR で `monorepo` の `workflow-config.yaml` を新スキーマに書き換え。
4. 別 PR で `platform` の `workflow-config.yaml` を新スキーマに書き換え。
5. `panicboat-actions`（terragrunt / kubernetes action）の修正は不要。
6. `monorepo` / `platform` の `.github/workflows/auto-label--deploy-trigger.yaml` 等の matrix キー参照（`matrix.target.aws_region` 等）の修正は不要。

破壊的変更だが、後段 action の参照キー名は維持されるため、利用側 workflow ファイルへの影響はない。`workflow-config.yaml` を 3 リポジトリで同期更新するのみ。

## Verification

1. `bundle exec rspec` で全 spec 通過確認。
2. `bin/config-manager validate -c workflow-config.yaml` 相当を実行し新 YAML が valid と判定されること。
3. `bin/label-resolver` で deploy:demo（除外サービス）含むケースの matrix 出力 JSON を目視確認し、新仕様での出力（kubernetes target から `aws_region` が消える等）が想定通りであること。
4. `monorepo` / `platform` の追従 PR 作成前に、本リポジトリの変更を main にマージし利用側で参照可能にする。
