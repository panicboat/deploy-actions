# Uniform Placeholder Handling via PatternMatcher

## Background

`workflow-config.yaml` の `stack_conventions[].root` と `stack_conventions[].stacks[].directory` は、テンプレ変数 `{service}` と `{environment}` を含む。現状の実装では:

- `label-dispatcher` の `discover_services_from_pattern` は `{service}` を `([^/]+)` に、`{environment}` を `[^/]+` に gsub するだけ。任意 placeholder（例 `{team}`）が pattern にあると、その文字列がリテラルとして regex に残り、service 検出が壊れる
- `label-resolver` の `expand_directory_pattern` も `{service}` と `{environment}` の 2 種類だけを `gsub` で展開する
- placeholder 関連のエラーは `puts "Warning: ..."` で握り潰されている（例: `generated_matrix.rb:292,300`）
- 抽出される値は `{service}` のみで、それ以外の placeholder の値は捨てられる

このため、ユーザーが pattern に `{team}` などの任意 placeholder を入れて downstream の Composite Action へ渡すことができない。

## Goal

- pattern 中の任意 placeholder を、変更ファイルパス（dispatcher 側）でも working_dir（resolver 側）でも統一的に扱えるようにする
- 抽出した任意 placeholder の値を、`DeploymentTarget` のトップレベルにフラット展開して matrix output として downstream に渡せるようにする
- placeholder 関連の警告 (`puts`) を例外に置き換え、不正な config / 不整合を validate / 実行時に早期に失敗させる

## Non-Goals

- placeholder の値を `workflow-config.yaml` の他のフィールド（例 `services[].xxx`）から取得する機能（今回はパス由来のみ）
- label 名の構造変更（`deploy:<service>` を維持）
- label-dispatcher が任意 placeholder の値を出力する機能（dispatcher は従来通り service 名のみ出力）

## Decisions

- **抽出場所**: label-resolver の `generate_deployment_target` で確定する `working_dir` と、その target を生成した dir_pattern を照らして抽出する
- **宣言方式**: 暗黙。pattern 中の `{name}` がそのまま capture 対象
- **出力フィールド**: `DeploymentTarget` のトップレベルにフラット展開（既存予約名と衝突しない場合のみ）
- **共通化**: pattern の regex 化・展開・抽出を行う `Entities::PatternMatcher` を新設し、dispatcher / resolver / validate で共有する

## Architecture

```
action-scripts/
├── shared/
│   ├── entities/
│   │   ├── deploy_label.rb
│   │   ├── deployment_target.rb           # add captures: param, merge into to_matrix_item
│   │   ├── pattern_matcher.rb             # New
│   │   ├── result.rb
│   │   └── workflow_config.rb
│   ├── infrastructure/
│   └── interfaces/
├── label-dispatcher/
│   └── use_cases/
│       └── detect_changed_services.rb     # use PatternMatcher
├── label-resolver/
│   └── use_cases/
│       └── generated_matrix.rb            # use PatternMatcher + extract captures
└── config-manager/
    └── use_cases/
        └── validate_config.rb             # reject reserved-name placeholders
```

`PatternMatcher` は clean architecture の Entity 層に置く Value Object。外部 I/O に依存せず、pattern 文法というドメインルールだけを表現する。`Entities::` 名前空間に入り、`shared/entities/` 配下に置く。

## PatternMatcher API

```ruby
module Entities
  class PatternMatcher
    # Matches placeholders like {service}, {team}, {env_a1}.
    # Uppercase and hyphenated names ({Team}, {my-var}) are treated as literals.
    PLACEHOLDER_REGEX = /\{([a-z_][a-z0-9_]*)\}/

    # Returns placeholder names in left-to-right order, including duplicates.
    def self.placeholders(pattern)
    end

    # Substitutes {name} with values[name]. Raises UnresolvedPlaceholderError
    # if any placeholder remains. Raises ArgumentError if a value contains "/".
    def self.expand(pattern, values)
    end

    # Returns a Hash mapping placeholder names to captured values, or nil if
    # the path does not match the pattern. Captures cannot span "/".
    def self.extract(pattern, path)
    end
  end

  class UnresolvedPlaceholderError < StandardError; end
end
```

### Naming Rules

- placeholder 名は `[a-z_][a-z0-9_]*`（小文字英字または `_` で始まり、小文字英数字または `_` が続く）
- 文法外の `{Team}` `{my-var}` `{a b}` は **placeholder と見なさずリテラル扱い**（regex 化時にエスケープ）
- 同一 pattern 中の同名 placeholder 複数出現は許可。`expand` では同じ値で置換、`extract` では値が一致しなければ `nil`

### Value Constraints

- `extract` のキャプチャは `[^/]+`（パス区切りを跨がない）
- `expand` の値に `/` が含まれる場合は `ArgumentError`（パスを意図せず深くしないため）

### Error Mapping

| Error | When | Raised by |
|---|---|---|
| `UnresolvedPlaceholderError` | `expand` で未指定 placeholder が残った | `PatternMatcher.expand` |
| `ArgumentError` | `expand` の値に `/` を含む | `PatternMatcher.expand` |
| `StandardError` | resolver が matched_pattern と working_dir の不整合を検知 | `generate_deployment_target` |

現状の `generated_matrix.rb:292,300` の `puts "Warning: ..."` はすべて例外に置き換える。

## Data Flow

### label-resolver

```
deploy_labels (deploy:<service>)
        │
        ▼
generate_targets_for_service(label, config)
        │
        ▼
generate_deployment_target(label, env, stack, config)
        │
        │  Existing: iterate dir_patterns and pick the first existing directory
        ▼
matched_pattern = the dir_pattern that matched
captures        = PatternMatcher.extract(matched_pattern, working_dir)
        │
        │  Drop service / environment from captures (they already become
        │  top-level fields via dedicated keyword args).
        │  Fixed reserved names (stack, working_directory,
        │  stack_convention_root) and dynamic reserved names (every key in
        │  the target's attributes Hash) are already rejected by
        │  validate_config; the DeploymentTarget constructor still
        │  defensively raises on collision.
        ▼
DeploymentTarget(
  service:, environment:, stack:, working_directory:,
  stack_convention_root:, attributes:,
  captures:   # new keyword arg; merged into to_matrix_item top-level
)
```

- 抽出に使う pattern は `root + "/" + stack.directory` の結合形（root が空なら stack.directory のみ）
- `extract` が `nil` を返した場合は不変条件違反として例外を投げる（黙って空 Hash にしない）

### label-dispatcher

```
changed_files × all_directory_patterns
        │
        ▼
PatternMatcher.extract(pattern, file_path)
        │
        │  Take the "service" key from the captures Hash.
        │  Any other captures are ignored at this layer.
        ▼
Set of service names
```

これにより任意 placeholder（例 `{team}`）を含む pattern でも service 検出が壊れない。

## Conflict Resolution

### Reserved Names

`DeploymentTarget#to_matrix_item` は固定フィールドに加えて `attributes` Hash をシンボル化してトップレベルに merge する（既存実装。`deployment_target.rb:24-32` 参照）。新たに captures もこの merge に加わるため、衝突は以下の 2 種類を考慮する。

**固定予約名** — `DeploymentTarget` のトップレベルフィールド名と衝突する placeholder は混乱を招くため拒否する。

- 既存使用の `{service}` `{environment}` は許可
- `{stack}` `{working_directory}` `{stack_convention_root}` を pattern 中に書いた場合は `validate_config` でエラー

**動的予約名（attributes キー）** — `environments[].stacks[stack_name]` 配下の attribute キー（例 `aws_region`, `iam_role_plan`, `iam_role_apply`）と一致する placeholder も拒否する。

- validate は全 `environments[].stacks[]` を走査して使用されている attribute キーの集合を作る
- そのキー集合と pattern 中の placeholder 名に重複があれば `validate_config` でエラー
- 防衛的に `DeploymentTarget` constructor でも captures × 固定フィールド名 × attributes キーの衝突を検出して例外

### Structurally Equivalent Conventions

複数の `stack_conventions` が、同じ stack 名を持ち、placeholder の **位置** で見たときに同じパス構造（同じ深さ・同じ位置に placeholder がある）を指す場合、対応する位置の placeholder 名も一致しなければならない。

不整合な例:

```yaml
stack_conventions:
  - root: "{team}/{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
  - root: "{team99}/{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
```

両 convention の root pattern (`{team}/{service}` と `{team99}/{service}`) は実ディレクトリ `payments/api/...` に対して両方ともマッチする。resolver 側では:

- `find_matching_conventions` が両方の convention を返す
- `stacks.uniq { |s| s['name'] }` により先頭の convention の stack 設定だけが採用される
- 抽出される captures のキー名は YAML 上で先に書かれた方（`team` か `team99`）

結果、captures のキー名が YAML の並び順で決まる順序依存挙動になる。これは downstream が参照すべきキー名を曖昧にする。

validate ルール: pattern 中の placeholder を出現順で `{X0}` `{X1}` ... と匿名化した形（=構造シグネチャ）を計算する。同じ stack 名を持つ複数 convention の root + stack.directory 結合パターンについて、構造シグネチャが一致する場合は対応位置の placeholder 名も一致することを確認し、不一致があればエラーにする。

例外:
- 異なる stack 名同士は比較対象外（terragrunt と kubernetes は別の世界）
- 構造が違う conventions（例: `{service}` のみ vs `{team}/{service}`）は比較対象外

### Per-Target Variance

同一 service の同一 stack で複数 environment を処理するとき、`{environment}` だけは target ごとに異なるのが正常（既存挙動）。それ以外の placeholder は service 1 つに対し root pattern 1 つに収束するため、target ごとに異なる値になることは構造上発生しない。特別な衝突解決ロジックは不要。

### Extract-Time Failure

`extract` が `nil` を返すケースは「`expand` で作った working_dir が元の pattern とマッチしない」状況であり、構造上起こり得ない。万一発生した場合は実装バグなので例外を投げる。

## Matrix Output Schema

label-resolver は `Entities::DeploymentTarget` の配列を `to_matrix_item` 経由で JSON 化し、GitHub Actions の `outputs.targets`（および presenters 経由で `DEPLOYMENT_TARGETS`）に渡す。1 つの matrix item は次のフラットな構造を持つ:

| Key | 型 | 由来 | 説明 |
|---|---|---|---|
| `service` | string | 固定 | `deploy:<service>` ラベルの service 名 |
| `environment` | string \| null | 固定 | 対象 environment 名。environment-agnostic stack では `null` |
| `stack` | string | 固定 | stack 名（例 `terragrunt`, `kubernetes`） |
| `working_directory` | string | 固定 | 実在する deploy 対象ディレクトリ（pattern 展開後） |
| `stack_convention_root` | string | 固定 | working_directory のうち root pattern 展開部分（例 `payments/api`） |
| _（attributes のキー）_ | any | 動的 | `environments[].stacks[stack].*` で定義された attribute（例 `aws_region`, `iam_role_plan`, `iam_role_apply`） |
| _（captures のキー）_ | string | 動的（本変更で追加） | pattern 中の任意 placeholder の抽出値（`service` / `environment` 以外、かつ予約名と衝突しないもの） |

例: 設定が

```yaml
environments:
  - environment: develop
    stacks:
      terragrunt:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::111:role/plan
        iam_role_apply: arn:aws:iam::111:role/apply
stack_conventions:
  - root: "{team}/{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
```

変更ファイル `payments/api/terragrunt/develop/main.tf` を `deploy:api` ラベルで解決した結果の matrix item:

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "terragrunt",
  "working_directory": "payments/api/terragrunt/develop",
  "stack_convention_root": "payments/api",
  "aws_region": "ap-northeast-1",
  "iam_role_plan": "arn:aws:iam::111:role/plan",
  "iam_role_apply": "arn:aws:iam::111:role/apply",
  "team": "payments"
}
```

downstream の Composite Action では `${{ matrix.team }}` のように直接参照できる。

GitHub Actions matrix の strategy に流す場合は `fromJson(needs.resolve.outputs.targets)` で配列化する。

### Output Channels

- `outputs.targets` — JSON 文字列。GitHub Actions の他ジョブが `fromJson` で参照
- 環境変数 `DEPLOYMENT_TARGETS` — 同じ JSON 文字列（後方互換）

両チャネルとも上記スキーマの配列を返す。

## Validation Rules (config-manager)

`validate_config.rb` に以下を追加する:

1. `stack_conventions[].root` と `stack_conventions[].stacks[].directory` を走査し、`PatternMatcher.placeholders` で名前を列挙
2. 固定予約名（`stack`, `working_directory`, `stack_convention_root`）と一致する placeholder があればエラー
3. 動的予約名（全 `environments[].stacks[]` から収集した attribute キー集合）と一致する placeholder があればエラー
4. pattern 中に文法外の `{...}` リテラル（例 `{Foo}` `{my-var}`）が含まれる場合は警告ではなくエラー（意図しない可能性が高いため早期検出）
5. 同じ stack 名を持つ複数 convention の `root + "/" + stack.directory` 結合パターンについて、placeholder 位置の構造シグネチャ（出現順で `{X0}` `{X1}` ... と匿名化したもの）が一致する組み合わせがあれば、対応位置の placeholder 名も一致しなければエラー

既存の `{service}` `{environment}` の必須／optional ルールは変更しない:

- `root` は `{service}` を必ず含む（空文字を除く）
- `stacks[].directory` の `{environment}` は optional（environment-agnostic stack をサポート）

## Test Strategy

### New Specs

**`spec/shared/entities/pattern_matcher_spec.rb`**

- `placeholders`
  - 単一: `{service}` → `["service"]`
  - 複数: `{team}/{service}/terragrunt/{environment}` → `["team", "service", "environment"]`
  - 重複: `{a}/{a}` → `["a", "a"]`
  - 文法外: `{Foo}` `{my-var}` `{a b}` → `[]`
- `expand`
  - 全 placeholder 指定で完全展開される
  - 未指定 placeholder が残る → `UnresolvedPlaceholderError`
  - 値に `/` が含まれる → `ArgumentError`
  - 同名 placeholder の複数出現を同じ値で置換する
  - placeholder のない pattern はそのまま返る
- `extract`
  - 完全マッチで名前付き Hash を返す
  - 部分マッチ（pattern より path が短い／長い）は `nil`
  - キャプチャ部分に `/` を含むパスは `nil`
  - 重複 `{a}/{a}` で値が一致するパスはマッチ、不一致は `nil`

### Modified Specs

**`spec/label-dispatcher/use_cases/detect_changed_services_spec.rb`**

- 既存ケースは green を維持
- 追加: 任意 placeholder `{team}` を含む pattern でも service 検出が成立する

**`spec/label-resolver/use_cases/generated_matrix_spec.rb`**

- 既存ケース: 任意 placeholder を含まない config では `DeploymentTarget` の構造に差分がないため green を維持
- 追加:
  - root に `{team}` を含む convention から生成された target に `team` キーがトップレベルに含まれる
  - `to_matrix_item` 出力に固定キー・attributes 由来キー・captures 由来キーがすべてフラットに並ぶ
  - matched_pattern と working_dir の不整合時に例外が投げられる（旧 `puts "Warning..."` 挙動の置換確認）

**`spec/shared/entities/deployment_target_spec.rb`**（存在しなければ新規）

- `captures:` 引数を渡せること
- `captures` のキーが固定フィールド名（`service` 等）と衝突 → constructor で例外
- `captures` のキーが `attributes` のキーと衝突 → constructor で例外
- 衝突がなければ `to_matrix_item` の戻り Hash にフラット展開される

**`spec/config-manager/use_cases/validate_config_spec.rb`**

- 追加:
  - 固定予約名 placeholder（`{stack}`, `{working_directory}`, `{stack_convention_root}`）を含む config → エラー
  - 文法外 placeholder（`{Foo}`）を含む config → エラー
  - 任意名 placeholder（`{team}`）を含む config → pass
  - 既存の `{service}` `{environment}` 必須／optional ルールは挙動が変わらない
  - 構造シグネチャが一致する複数 convention で placeholder 名が異なる（例 `{team}/{service}` と `{team99}/{service}` が両方 stack=terragrunt）→ エラー
  - 構造シグネチャが一致する複数 convention で placeholder 名も一致 → pass
  - 異なる stack 名同士は構造シグネチャが一致しても無視（pass）
  - environments の attribute キーと同名の placeholder（例 `{aws_region}`）→ エラー
  - environments で使われていない名前の placeholder → pass

### TDD Order

1. `PatternMatcher` の spec → 実装
2. `DeploymentTarget` の `captures:` 引数追加 spec → 実装（衝突検知含む）
3. `validate_config` の追加チェック spec（固定予約名・動的予約名・文法外 placeholder・構造同等性）→ 実装
4. `detect_changed_services` を PatternMatcher 経由に置換し、既存 spec が green を保つ
5. `generated_matrix` の captures フラット展開実装と新規 spec
6. `generated_matrix` の `puts "Warning..."` 箇所を例外化、関連 spec の更新
7. README.md / README-ja.md / config-manager/README.md を更新（matrix output schema・任意 placeholder の説明）

各ステップ後に `bundle exec rspec` 全体を流して green を維持する。README 更新ステップ後は markdown のリンク切れがないことを目視確認する。

## Documentation Updates

ユーザーが matrix 出力を参照する際に必要な情報が現状不足しているため、以下を更新する。

### `README.md` / `README-ja.md`（リポジトリ直下）

両ファイルに対し以下の章を追加・更新する（README.md は英語、README-ja.md は日本語、見出しは両方とも英語）。

1. **新規章 "Matrix Output"** — `## Workflow integration` の直後に追加。本 spec の "Matrix Output Schema" セクションの内容を要約して載せる:
   - matrix item のキー一覧（固定キー・attributes 由来・captures 由来の 3 種類があること）
   - JSON 例（上記の `team` を含むサンプル）
   - downstream Composite Action からの参照例（`${{ matrix.team }}`）

2. **設定例の更新** — `## Configuration` / `## 設定` 節の `stack_conventions` サンプルに、任意 placeholder の使用例（例: `root: "{team}/{service}"` のコメント付きバリアント）を追記。デフォルトサンプルは現状の `root: "{service}"` を維持し、「root には任意の placeholder を追加可能」と短い注記を入れる。

### `action-scripts/config-manager/README.md`

placeholder 関連の記述を更新する:

1. **新規節 "Placeholder rules"** — 既存の "Directory Validation" 節の近くに追加:
   - 文法 `{name}` の許容文字種（`[a-z_][a-z0-9_]*`）
   - 抽出と展開の仕組み（dispatcher / resolver の両方で動く）
   - 予約名（固定・動的）と衝突した場合の挙動
   - 構造同等性チェックの説明
2. 既存の `{service}` `{environment}` への言及箇所を「組み込み placeholder の例」として整理。任意 placeholder も同じ仕組みで動くことを明示

### `action-scripts/README.md`（存在する場合）

action-scripts 直下の README が存在する場合は、shared/entities に PatternMatcher が追加された旨と、その責務（pattern の regex 化・展開・抽出）の 1 段落説明を追加する。存在しなければスキップ。

これらの README 更新は実装 PR と同じ commit 群に含める（実装と乖離させないため）。

## Backward Compatibility

- `workflow-config.yaml` の既存定義（`{service}` `{environment}` のみ使用）はそのまま動作する
- `DeploymentTarget` の既存フィールドは変更しない。captures は target のトップレベルに追加されるだけ
- label 仕様（`deploy:<service>`）は変更しない
- label-dispatcher の output（detected services / deploy labels）は変更しない
- 例外化により従来 `puts "Warning..."` で続行されていた config の不整合は早期に失敗する。これは意図的な挙動変更で、実害がある config（unresolved placeholder, environment 不整合）は新挙動で気付ける

## Out of Scope

- 任意 placeholder を `services[].stack_conventions` のような service ローカル定義に拡張すること
- placeholder の値を環境変数や外部ソースから取得すること
- label-dispatcher が captures を出力に含めること
