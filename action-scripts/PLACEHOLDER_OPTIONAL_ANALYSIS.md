# プレースホルダーオプショナル化の影響分析

## 目次

1. [変更内容の概要](#変更内容の概要)
2. [変更1: `{environment}`をオプショナルにする](#変更1-environment-をオプショナルにする)
3. [変更2: `generated_matrix.rb:138`を`nil`に修正](#変更2-generated_matrixrb138-をnil-に修正)
4. [変更3: `{service}`をオプショナルにする](#変更3-service-をオプショナルにする)
5. [比較表](#比較表)
6. [最終的な挙動シミュレーション](#最終的な挙動シミュレーション)
7. [推奨事項](#推奨事項)

---

## 変更内容の概要

本ドキュメントでは、以下の3つの変更について、影響範囲・副作用・最終的な挙動を分析します。

| 変更 | 目的 | 優先度 |
|------|------|--------|
| `{environment}`をオプショナル化 | 環境非依存スタック（Dockerビルド等）のサポート | 高 |
| `generated_matrix.rb:138`の修正 | バグ修正（空配列→nil） | 中 |
| `{service}`をオプショナル化 | 固定サービス名（`docs`等）のサポート | 低 |

---

## 変更1: `{environment}` をオプショナルにする

### 目的

環境に依存しないスタック（Dockerイメージのビルドなど）を正式にサポートする。

### 必要な修正箇所

#### 1. バリデーションの緩和（必須）

**ファイル**: `config-manager/use_cases/validate_config.rb`

```ruby
# 現在のコード（169-171行目）
if stack['directory'] && !stack['directory'].include?('{environment}')
  errors << "Stack '#{stack['name']}' directory must include {environment} placeholder"
end

# 修正案: 削除またはコメントアウト
# {environment}はオプショナルになったため、このチェックは不要
```

**影響度**: 低
**実装難易度**: 低（3行の削除）

---

#### 2. label-dispatcherの調整（対応済み）

**ファイル**: `label-dispatcher/use_cases/detect_changed_services.rb`

```ruby
# 101行目 - 既に対応済み
regex_pattern = regex_pattern.gsub('{environment}', '[^/]+')
```

`{environment}`プレースホルダーがない場合、`gsub`は何も置換せずに元の文字列を返すため、**変更不要**。

**影響度**: なし
**実装難易度**: なし（既存のコードで動作）

---

#### 3. label-resolverの調整（条件分岐追加）

**ファイル**: `label-resolver/use_cases/generated_matrix.rb`

```ruby
# 現在のコード（125-127行目）
expanded_pattern = full_pattern
  .gsub('{service}', service_name)
  .gsub('{environment}', env)

# 修正案: 条件分岐を追加
expanded_pattern = full_pattern.gsub('{service}', service_name)
if full_pattern.include?('{environment}')
  expanded_pattern = expanded_pattern.gsub('{environment}', env)
else
  # {environment}がない場合、envは使用しない
  # 全環境で同じディレクトリを参照することになる
end
```

**同様の修正が必要な箇所**:
- 127行目（上記）
- 325行目（`expand_directory_pattern`メソッド内）
- 354行目（デバッグ出力）

**影響度**: 中
**実装難易度**: 中（条件分岐の追加、テストケースの追加）

---

#### 4. deployment_targetの調整

**ファイル**: `shared/entities/deployment_target.rb`

```ruby
# 現在のコード（141行目）
def self.expand_directory_pattern(pattern, service_name, target_environment)
  pattern
    .gsub('{service}', service_name)
    .gsub('{environment}', target_environment)
end

# 修正案
def self.expand_directory_pattern(pattern, service_name, target_environment)
  expanded = pattern.gsub('{service}', service_name)
  if pattern.include?('{environment}')
    expanded = expanded.gsub('{environment}', target_environment)
  end
  expanded
end
```

**影響度**: 中
**実装難易度**: 低（単純な条件分岐）

---

#### 5. テストファイルの更新

**影響を受けるテストファイル**:
- `spec/label-resolver/use_cases/generate_matrix_spec.rb`
- `spec/label-dispatcher/use_cases/detect_changed_services_spec.rb`
- `spec/shared/entities/deployment_target_spec.rb`
- `spec/shared/entities/workflow_config_spec.rb`
- `spec/config-manager/use_cases/validate_config_spec.rb`
- 他、約10-15ファイル

**必要なテストケース**:
- `{environment}`がないスタックの検出テスト
- `{environment}`がないスタックのマトリクス生成テスト
- 環境依存・非依存スタックの混在テスト

**影響度**: 中
**実装難易度**: 中（新規テストケースの追加）

---

### 影響範囲まとめ

| ファイル | 変更内容 | 影響度 | 実装難易度 |
|---------|---------|--------|----------|
| config-manager/use_cases/validate_config.rb | バリデーション削除 | 低 | 低 |
| label-dispatcher/use_cases/detect_changed_services.rb | 変更不要 | なし | なし |
| label-resolver/use_cases/generated_matrix.rb | 条件分岐追加（3箇所） | 中 | 中 |
| shared/entities/deployment_target.rb | 条件分岐追加（1箇所） | 中 | 低 |
| spec/** | テストケース追加 | 中 | 中 |

**合計**: 約4ファイルの実装変更 + 10-15ファイルのテスト追加

---

### 副作用

#### ✅ ポジティブな副作用

1. **環境非依存スタックの正式サポート**
   - Dockerイメージのビルドなど、環境に依存しない処理を明示的に定義可能
   - 設定の柔軟性が向上

2. **設定ファイルの簡潔化**
   ```yaml
   stacks:
     - name: docker
       directory: "src"  # {environment}不要
   ```

#### ⚠️ 注意すべき副作用

1. **重複ジョブの発生**
   - 環境非依存スタックでも、各環境ごとにデプロイメントターゲットが生成される
   - 例: `develop`, `staging`, `production`の3環境がある場合、同じDockerビルドが3回実行される
   - **非効率だが機能的には問題なし**

2. **working_directoryの重複**
   ```json
   [
     {"environment": "develop", "working_directory": "docs/src"},
     {"environment": "staging", "working_directory": "docs/src"},
     {"environment": "production", "working_directory": "docs/src"}
   ]
   ```
   - 全環境で同じディレクトリを参照

#### ❌ 潜在的なリスク

1. **誤設定の検出困難**
   - 既存の設定で誤って`{environment}`を削除した場合、検出が困難
   - バリデーションが緩和されるため、意図しない設定ミスが見逃される可能性

2. **テストカバレッジ不足のリスク**
   - 新しいパターンに対するテストが不十分だと、予期しない動作が発生する可能性

---

### 設定例

#### 修正前

```yaml
directory_conventions:
  - root: "docs/{service}"
    stacks:
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
```

#### 修正後

```yaml
directory_conventions:
  - root: "{service}"
    stacks:
      - name: docker
        directory: "src"  # {environment}なし
      - name: terragrunt
        directory: "terragrunt/envs/{environment}"  # {environment}あり
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"  # {environment}あり
```

---

## 変更2: `generated_matrix.rb:138` を`nil` に修正

### 目的

バグ修正。`find_matching_convention`メソッドがマッチする規約を見つけられない場合、空配列`[]`ではなく`nil`を返すようにする。

### 必要な修正箇所

#### 1. 戻り値の変更

**ファイル**: `label-resolver/use_cases/generated_matrix.rb`

```ruby
# 現在のコード（138行目）
def find_matching_convention(service_name, config)
  config.directory_conventions_config.each do |convention|
    # ...
    return convention if has_existing_directory
  end

  []  # ← 問題: 空配列を返している
end

# 修正案
def find_matching_convention(service_name, config)
  config.directory_conventions_config.each do |convention|
    # ...
    return convention if has_existing_directory
  end

  nil  # ← 修正: nilを返す
end
```

**影響度**: 低
**実装難易度**: 低（1行の変更）

---

#### 2. テストファイルの更新

**ファイル**: `spec/label-resolver/use_cases/generate_matrix_spec.rb`

**必要なテストケース**:
- マッチする規約が見つからない場合のテスト
- `nil`が返された場合のエラーハンドリングテスト

**影響度**: 低
**実装難易度**: 低

---

### 影響範囲まとめ

| ファイル | 変更内容 | 影響度 | 実装難易度 |
|---------|---------|--------|----------|
| label-resolver/use_cases/generated_matrix.rb | 1行変更（`[]` → `nil`） | 低 | 低 |
| spec/label-resolver/use_cases/generate_matrix_spec.rb | テストケース追加 | 低 | 低 |

**合計**: 1ファイルの実装変更（1行） + 1ファイルのテスト追加

---

### 副作用

#### ✅ ポジティブな副作用

1. **エラーメッセージの明確化**
   - 修正前: `no implicit conversion of String into Integer`（分かりにくい）
   - 修正後: nilチェック失敗により早期にエラーが検出される

2. **意図した動作の実現**
   - 74行目の`unless matching_convention`が正しく機能する
   ```ruby
   matching_convention = find_matching_convention(deploy_label.service, config)
   return targets unless matching_convention  # nilチェック
   ```

3. **デバッグの容易化**
   - エラーの原因が明確になる

#### ⚠️ 注意すべき副作用

- なし（完全にバグ修正）

#### ❌ 潜在的なリスク

- ほぼなし（既存のnilチェックが正しく動作するようになるだけ）

---

### エラーの再現

#### 修正前の挙動

```ruby
matching_convention = find_matching_convention("unknown-service", config)
# => []（空配列が返る）

# 74行目のチェック
return targets unless matching_convention
# => []は真値なので通過してしまう

# 76行目
stacks = matching_convention['stacks']
# => []['stacks']
# => エラー: no implicit conversion of String into Integer
```

#### 修正後の挙動

```ruby
matching_convention = find_matching_convention("unknown-service", config)
# => nil

# 74行目のチェック
return targets unless matching_convention
# => nilは偽値なのでここで早期リターン ✓

# 76行目には到達しない
```

---

## 変更3: `{service}` をオプショナルにする

### 目的

固定のサービス名（`docs`など）をサポートし、`{service}`プレースホルダーなしで設定できるようにする。

### 現在の制約

現在の実装では、label-dispatcherがサービス名を抽出するために`{service}`プレースホルダーが**必須**です。

```ruby
# label-dispatcher/use_cases/detect_changed_services.rb:107
service_name = match[1]  # 正規表現の最初のキャプチャグループ（{service}から生成）
```

`{service}`プレースホルダーがない場合、キャプチャグループが作られず、サービス名を抽出できません。

---

### 必要な修正箇所

#### 1. WorkflowConfigの拡張（サービス名の明示的指定）

**ファイル**: `shared/entities/workflow_config.rb`

**修正案A: 設定にサービス名を追加**

```yaml
directory_conventions:
  - service: "docs"  # 明示的にサービス名を指定
    root: "docs"
    stacks:
      - name: docker
        directory: "src"
      - name: terragrunt
        directory: "terragrunt/envs/{environment}"
```

**修正案B: rootからサービス名を推論**

```ruby
# all_directory_patternsメソッドの修正
def all_directory_patterns
  patterns = []

  directory_conventions_config.each do |convention|
    root_pattern = convention['root']
    service_name = convention['service']  # 明示的なサービス名

    # {service}プレースホルダーがある場合
    if root_pattern&.include?('{service}')
      # 既存のロジック
      patterns << root_pattern if root_pattern
      stacks.each do |stack_config|
        full_pattern = "#{root_pattern}/#{stack_config['directory']}"
        patterns << full_pattern if full_pattern.include?('{service}')
      end
    # {service}プレースホルダーがない場合
    elsif service_name
      # 固定サービス名を使用
      stacks.each do |stack_config|
        full_pattern = "#{root_pattern}/#{stack_config['directory']}"
        # パターンにサービス名を含めて返す
        patterns << { pattern: full_pattern, service: service_name }
      end
    end
  end

  patterns.uniq
end
```

**影響度**: 高
**実装難易度**: 高（データ構造の変更）

---

#### 2. label-dispatcherの大幅な変更

**ファイル**: `label-dispatcher/use_cases/detect_changed_services.rb`

```ruby
# 現在のコード（97-113行目）
def discover_services_from_pattern(changed_files, pattern)
  regex_pattern = pattern.gsub('{service}', '([^/]+)')
  regex_pattern = regex_pattern.gsub('{environment}', '[^/]+')

  services = Set.new
  changed_files.each do |file|
    if match = file.match(/^#{regex_pattern}/)
      service_name = match[1]  # {service}から抽出
      services << service_name
    end
  end
  services
end

# 修正案: パターンの型を判定
def discover_services_from_pattern(changed_files, pattern_or_hash)
  if pattern_or_hash.is_a?(Hash)
    # 固定サービス名の場合
    pattern = pattern_or_hash[:pattern]
    service_name = pattern_or_hash[:service]

    # パターンマッチング（サービス名は既知）
    regex_pattern = pattern.gsub('{environment}', '[^/]+')
    changed_files.each do |file|
      return Set[service_name] if file.match(/^#{regex_pattern}/)
    end
    Set.new
  else
    # 既存のロジック（{service}プレースホルダーあり）
    pattern = pattern_or_hash
    regex_pattern = pattern.gsub('{service}', '([^/]+)')
    regex_pattern = regex_pattern.gsub('{environment}', '[^/]+')

    services = Set.new
    changed_files.each do |file|
      if match = file.match(/^#{regex_pattern}/)
        service_name = match[1]
        services << service_name
      end
    end
    services
  end
end
```

**影響度**: 高
**実装難易度**: 高（ロジックの複雑化）

---

#### 3. label-resolverの調整

**ファイル**: `label-resolver/use_cases/generated_matrix.rb`

```ruby
# 現在のコード（125-127行目）
expanded_pattern = full_pattern
  .gsub('{service}', service_name)
  .gsub('{environment}', env)

# 修正案: {service}がない場合の処理を追加
expanded_pattern = full_pattern
if full_pattern.include?('{service}')
  expanded_pattern = expanded_pattern.gsub('{service}', service_name)
end
if full_pattern.include?('{environment}')
  expanded_pattern = expanded_pattern.gsub('{environment}', env)
end
```

**影響度**: 中
**実装難易度**: 中

---

#### 4. バリデーションの追加

**ファイル**: `config-manager/use_cases/validate_config.rb`

```ruby
# 新しいバリデーション
directory_conventions_config.each_with_index do |convention, conv_index|
  root_pattern = convention['root']
  service_name = convention['service']

  # {service}プレースホルダーがない場合、serviceフィールドが必須
  if !root_pattern&.include?('{service}') && service_name.nil?
    errors << "Convention #{conv_index}: 'service' field is required when root doesn't include {service} placeholder"
  end

  # {service}プレースホルダーとserviceフィールドの両方がある場合はエラー
  if root_pattern&.include?('{service}') && service_name
    errors << "Convention #{conv_index}: Cannot specify both {service} placeholder and 'service' field"
  end
end
```

**影響度**: 中
**実装難易度**: 中

---

#### 5. テストファイルの大幅な更新

**影響を受けるテストファイル**:
- `spec/label-dispatcher/use_cases/detect_changed_services_spec.rb`（大幅変更）
- `spec/label-resolver/use_cases/generate_matrix_spec.rb`（大幅変更）
- `spec/shared/entities/workflow_config_spec.rb`（新規テスト追加）
- `spec/config-manager/use_cases/validate_config_spec.rb`（新規テスト追加）
- 他、約15-20ファイル

**必要なテストケース**:
- 固定サービス名のパターンマッチングテスト
- `{service}`プレースホルダーあり・なしの混在テスト
- バリデーションテスト
- エッジケーステスト

**影響度**: 高
**実装難易度**: 高

---

### 影響範囲まとめ

| ファイル | 変更内容 | 影響度 | 実装難易度 |
|---------|---------|--------|----------|
| shared/entities/workflow_config.rb | データ構造変更、ロジック追加 | 高 | 高 |
| label-dispatcher/use_cases/detect_changed_services.rb | ロジックの大幅変更 | 高 | 高 |
| label-resolver/use_cases/generated_matrix.rb | 条件分岐追加 | 中 | 中 |
| shared/entities/deployment_target.rb | 条件分岐追加 | 中 | 低 |
| config-manager/use_cases/validate_config.rb | バリデーション追加 | 中 | 中 |
| spec/** | テストケース大幅追加 | 高 | 高 |

**合計**: 約5-6ファイルの実装変更 + 15-20ファイルのテスト追加

---

### 副作用

#### ✅ ポジティブな副作用

1. **固定サービスのサポート**
   - `docs`のような単一サービスを明示的に定義可能
   ```yaml
   - service: "docs"
     root: "docs"
     stacks: ...
   ```

2. **設定の明確化**
   - サービス名が設定ファイルに明記される
   - 複雑なディレクトリ構造でも理解しやすい

#### ⚠️ 注意すべき副作用

1. **設定ファイルの複雑化**
   - 新しいフィールド`service`の追加により、学習コストが増加
   - ドキュメントの更新が必要

2. **データ構造の変更**
   - `all_directory_patterns`の戻り値が文字列からハッシュ/混合型になる
   - 既存のコードへの影響範囲が広い

3. **バリデーションの追加**
   - `{service}`とserviceフィールドの排他制御が必要
   - エラーメッセージの追加が必要

#### ❌ 潜在的なリスク

1. **後方互換性の喪失**
   - データ構造の変更により、既存のワークフローが影響を受ける可能性
   - 移行パスの設計が必要

2. **複雑性の増加**
   - コードの複雑性が大幅に増加
   - メンテナンスコストの増加
   - バグの混入リスク

3. **テストカバレッジ**
   - 新しいパターンの組み合わせが多数発生
   - 網羅的なテストが困難

---

### 代替案: `{service}`を維持する

**推奨**: `{service}`プレースホルダーをオプショナルにせず、以下の設定で対応

```yaml
directory_conventions:
  # docsサービス（{service}を使用）
  - root: "{service}"
    stacks:
      - name: docker
        directory: "src"
      - name: terragrunt
        directory: "terragrunt/envs/{environment}"

  # その他のサービス
  - root: "services/{service}"
    stacks: ...

services:
  - name: clusters
    exclude_from_automation: true
  - name: services
    exclude_from_automation: true
```

この方法なら：
- コード変更不要
- 既存の仕組みで動作
- 設定の変更のみで対応可能

---

## 比較表

### 実装の複雑さ

| 変更 | 影響ファイル数 | 実装難易度 | テスト難易度 | 開発工数（概算） |
|------|--------------|----------|------------|---------------|
| `{environment}`オプショナル化 | 4ファイル | 中 | 中 | 2-3日 |
| `generated_matrix.rb:138`修正 | 1ファイル | 低 | 低 | 0.5日 |
| `{service}`オプショナル化 | 5-6ファイル | 高 | 高 | 5-7日 |

### 副作用のリスク

| 変更 | ポジティブ副作用 | ネガティブ副作用 | 潜在的リスク |
|------|----------------|----------------|------------|
| `{environment}`オプショナル化 | 高（柔軟性向上） | 中（重複ジョブ） | 低 |
| `generated_matrix.rb:138`修正 | 高（バグ修正） | なし | 極低 |
| `{service}`オプショナル化 | 中（固定サービス対応） | 高（複雑化） | 高 |

### 推奨度

| 変更 | 推奨度 | 理由 |
|------|--------|------|
| `{environment}`オプショナル化 | ⭐⭐⭐⭐ | 環境非依存スタックのサポートに必要 |
| `generated_matrix.rb:138`修正 | ⭐⭐⭐⭐⭐ | バグ修正であり、副作用がほぼない |
| `{service}`オプショナル化 | ⭐⭐ | 設定の工夫で代替可能、実装コストが高い |

---

## 最終的な挙動シミュレーション

### 前提条件

**修正後のmonorepo/workflow-config.yaml**:

```yaml
environments:
  - environment: develop
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::559744160976:role/github-oidc-auth-develop-github-actions-role
    iam_role_apply: arn:aws:iam::559744160976:role/github-oidc-auth-develop-github-actions-role

directory_conventions:
  # 変更1適用: {environment}オプショナル
  - root: "{service}"
    stacks:
      - name: docker
        directory: "src"  # {environment}なし
      - name: terragrunt
        directory: "terragrunt/envs/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

  - root: "services/{service}"
    stacks:
      - name: docker
        directory: "src"
      - name: terragrunt
        directory: "terragrunt/envs/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

# 除外設定
services:
  - name: clusters
    exclude_from_automation: true
    exclusion_config:
      reason: "Cluster configuration directory"
      type: "permanent"

  - name: services
    exclude_from_automation: true
    exclusion_config:
      reason: "Parent directory for services"
      type: "permanent"
```

---

### シナリオ1: docsサービスのDockerfileを変更

**変更ファイル**: `docs/src/Dockerfile`

#### Step 1: label-dispatcherの動作

```
📁 変更ファイル検出
  - docs/src/Dockerfile

🔍 パターンマッチング
  Pattern 1: {service}
    Regex: ^([^/]+)
    Match: "docs/src/Dockerfile" =~ /^([^/]+)/
    Result: ✓ service_name = "docs"

  Pattern 2: {service}/src
    Regex: ^([^/]+)/src
    Match: "docs/src/Dockerfile" =~ /^([^/]+)\/src/
    Result: ✓ service_name = "docs"

  Pattern 3: services/{service}/src
    Regex: ^services/([^/]+)/src
    Match: "docs/src/Dockerfile" =~ /^services\/([^/]+)\/src/
    Result: ✗ マッチせず

📊 検出されたサービス
  Set["docs"]

🚫 除外チェック
  "docs" ∉ excluded_services → OK

✅ 付与されるラベル
  deploy:docs
```

**結果**: PRに `deploy:docs` ラベルが付与される

---

#### Step 2: label-resolverの動作

**入力**:
- ラベル: `deploy:docs`
- 環境: `develop`

```
🔍 サービス検索: "docs"

📂 find_matching_convention("docs", config)
  Convention 1: root="{service}"
    Stacks検査:
      Stack 1: docker (directory="src")
        Pattern: "{service}/src"
        Expanded: "docs/src"
        File.directory?("/path/to/monorepo/docs/src") → true ✓

    → Convention 1を返す

📦 利用可能なスタック
  1. docker: directory="src"
  2. terragrunt: directory="terragrunt/envs/{environment}"
  3. kubernetes: directory="kubernetes/overlays/{environment}"

🌍 対象環境: develop

🔧 スタック処理

  Stack 1: docker
    Pattern: "docs/src"
    {environment}チェック: false
    Expanded: "docs/src" (変更なし)
    File.directory?("docs/src") → true ✓
    → ターゲット生成 ✓

  Stack 2: terragrunt
    Pattern: "docs/terragrunt/envs/{environment}"
    {environment}チェック: true
    Expanded: "docs/terragrunt/envs/develop"
    File.directory?("docs/terragrunt/envs/develop") → true ✓
    → ターゲット生成 ✓

  Stack 3: kubernetes
    Pattern: "docs/kubernetes/overlays/{environment}"
    {environment}チェック: true
    Expanded: "docs/kubernetes/overlays/develop"
    File.directory?("docs/kubernetes/overlays/develop") → true ✓
    → ターゲット生成 ✓

📋 生成されたマトリクス
[
  {
    "service": "docs",
    "environment": "develop",
    "stack": "docker",
    "working_directory": "docs/src",
    "directory_conventions_root": "docs"
  },
  {
    "service": "docs",
    "environment": "develop",
    "stack": "terragrunt",
    "working_directory": "docs/terragrunt/envs/develop",
    "aws_region": "ap-northeast-1",
    "iam_role_plan": "arn:aws:iam::559744160976:role/github-oidc-auth-develop-github-actions-role",
    "iam_role_apply": "arn:aws:iam::559744160976:role/github-oidc-auth-develop-github-actions-role",
    "directory_conventions_root": "docs"
  },
  {
    "service": "docs",
    "environment": "develop",
    "stack": "kubernetes",
    "working_directory": "docs/kubernetes/overlays/develop",
    "directory_conventions_root": "docs"
  }
]
```

**結果**: 3つのデプロイメントターゲットが生成される

---

#### Step 3: GitHub Actions matrixの実行

```yaml
strategy:
  matrix:
    include:
      - service: docs
        environment: develop
        stack: docker
        working_directory: docs/src

      - service: docs
        environment: develop
        stack: terragrunt
        working_directory: docs/terragrunt/envs/develop

      - service: docs
        environment: develop
        stack: kubernetes
        working_directory: docs/kubernetes/overlays/develop
```

**実行されるジョブ**:

1. **Dockerジョブ** (`docs/src`)
   - Dockerイメージのビルド
   - ECRへのプッシュ

2. **Terragruntジョブ** (`docs/terragrunt/envs/develop`)
   - Terragrunt plan/apply
   - インフラストラクチャの更新

3. **Kubernetesジョブ** (`docs/kubernetes/overlays/develop`)
   - kubectl apply
   - Kubernetesマニフェストの適用

---

### シナリオ2: services/nginx/src/index.htmlを変更

**変更ファイル**: `services/nginx/src/index.html`

#### Step 1: label-dispatcherの動作

```
📁 変更ファイル検出
  - services/nginx/src/index.html

🔍 パターンマッチング
  Pattern 1: {service}
    Regex: ^([^/]+)
    Match: "services/nginx/src/index.html" =~ /^([^/]+)/
    Result: ✓ service_name = "services"

  Pattern 2: {service}/src
    Regex: ^([^/]+)/src
    Match: "services/nginx/src/index.html" =~ /^([^/]+)\/src/
    Result: ✓ service_name = "services"

  Pattern 3: services/{service}/src
    Regex: ^services/([^/]+)/src
    Match: "services/nginx/src/index.html" =~ /^services\/([^/]+)\/src/
    Result: ✓ service_name = "nginx"

📊 検出されたサービス
  Set["services", "nginx"]

🚫 除外チェック
  "services" → excluded ✗ (削除)
  "nginx" → OK ✓

📝 最終的なサービス
  ["nginx"]

✅ 付与されるラベル
  deploy:nginx
```

**結果**: PRに `deploy:nginx` ラベルのみが付与される

**重要**: `deploy:services` は除外設定により付与されない

---

#### Step 2: label-resolverの動作

**入力**:
- ラベル: `deploy:nginx`
- 環境: `develop`

```
🔍 サービス検索: "nginx"

📂 find_matching_convention("nginx", config)
  Convention 1: root="{service}"
    Stacks検査:
      Stack 1: docker (directory="src")
        Pattern: "{service}/src"
        Expanded: "nginx/src"
        File.directory?("nginx/src") → false ✗
    → マッチせず

  Convention 2: root="services/{service}"
    Stacks検査:
      Stack 1: docker (directory="src")
        Pattern: "services/{service}/src"
        Expanded: "services/nginx/src"
        File.directory?("services/nginx/src") → true ✓
    → Convention 2を返す ✓

📦 利用可能なスタック
  1. docker: directory="src"
  2. terragrunt: directory="terragrunt/envs/{environment}"
  3. kubernetes: directory="kubernetes/overlays/{environment}"

🔧 スタック処理 (省略、docsと同様)

📋 生成されたマトリクス
[
  {
    "service": "nginx",
    "environment": "develop",
    "stack": "docker",
    "working_directory": "services/nginx/src",
    "directory_conventions_root": "services/nginx"
  },
  {
    "service": "nginx",
    "environment": "develop",
    "stack": "terragrunt",
    "working_directory": "services/nginx/terragrunt/envs/develop",
    "aws_region": "ap-northeast-1",
    "iam_role_plan": "arn:aws:iam::559744160976:role/...",
    "iam_role_apply": "arn:aws:iam::559744160976:role/...",
    "directory_conventions_root": "services/nginx"
  },
  ...
]
```

**結果**: nginxサービスのデプロイメントターゲットが正しく生成される

---

### シナリオ3: clusters/develop/config.yamlを変更

**変更ファイル**: `clusters/develop/config.yaml`

#### Step 1: label-dispatcherの動作

```
📁 変更ファイル検出
  - clusters/develop/config.yaml

🔍 パターンマッチング
  Pattern 1: {service}
    Regex: ^([^/]+)
    Match: "clusters/develop/config.yaml" =~ /^([^/]+)/
    Result: ✓ service_name = "clusters"

  Pattern 2: {service}/src
    Regex: ^([^/]+)/src
    Match: "clusters/develop/config.yaml" =~ /^([^/]+)\/src/
    Result: ✗ マッチせず

  Pattern 3-N: 他のパターン
    Result: ✗ すべてマッチせず

📊 検出されたサービス
  Set["clusters"]

🚫 除外チェック
  "clusters" → excluded ✗ (削除)

📝 最終的なサービス
  [] (空)

❌ 付与されるラベル
  なし
```

**結果**: ラベルは付与されない

**理由**: `clusters`は除外設定により、デプロイメント対象外として扱われる

---

### シナリオ4: 複数環境へのデプロイ

**変更ファイル**: `docs/src/Dockerfile`
**環境指定**: `develop,staging,production`

#### label-resolverの動作

```
🌍 対象環境: ["develop", "staging", "production"]

🔧 スタック処理

  Stack 1: docker (directory="src")
    {environment}チェック: false (含まれていない)

    Environment: develop
      Pattern: "docs/src"
      Expanded: "docs/src" (変更なし)
      File.directory?("docs/src") → true ✓
      → ターゲット生成 ✓

    Environment: staging
      Pattern: "docs/src"
      Expanded: "docs/src" (同じディレクトリ)
      File.directory?("docs/src") → true ✓
      → ターゲット生成 ✓

    Environment: production
      Pattern: "docs/src"
      Expanded: "docs/src" (同じディレクトリ)
      File.directory?("docs/src") → true ✓
      → ターゲット生成 ✓

📋 生成されたマトリクス (dockerスタックのみ抜粋)
[
  {
    "service": "docs",
    "environment": "develop",
    "stack": "docker",
    "working_directory": "docs/src"
  },
  {
    "service": "docs",
    "environment": "staging",
    "stack": "docker",
    "working_directory": "docs/src"  # 同じ
  },
  {
    "service": "docs",
    "environment": "production",
    "stack": "docker",
    "working_directory": "docs/src"  # 同じ
  }
]
```

**結果**:
- 環境非依存スタック（docker）は3回ビルドされる
- 非効率だが、機能的には問題なし

**最適化の余地**:
- 環境非依存スタックは1回だけビルドするロジックを追加可能
- または、ワークフロー側で重複を排除

---

### シナリオ5: エラーケース（generated_matrix.rb:138修正前）

**変更ファイル**: `unknown-service/src/Dockerfile`
**状況**: 存在しないサービスのファイルを変更

#### label-dispatcherの動作

```
✅ 付与されるラベル: deploy:unknown-service
```

#### label-resolverの動作（修正前）

```
🔍 サービス検索: "unknown-service"

📂 find_matching_convention("unknown-service", config)
  Convention 1: root="{service}"
    Stacks検査:
      すべてのスタックでディレクトリが存在しない
    → マッチせず

  Convention 2: root="services/{service}"
    Stacks検査:
      すべてのスタックでディレクトリが存在しない
    → マッチせず

  ❌ 戻り値: [] (空配列)

⚠️ エラー発生
  matching_convention = []
  return targets unless matching_convention
    → []は真値なので通過してしまう

  stacks = matching_convention['stacks']
    → []['stacks']
    → エラー: no implicit conversion of String into Integer
```

**結果**: エラーが発生し、ワークフローが失敗

---

#### label-resolverの動作（修正後）

```
🔍 サービス検索: "unknown-service"

📂 find_matching_convention("unknown-service", config)
  (同様の処理)

  ✅ 戻り値: nil

✓ 早期リターン
  matching_convention = nil
  return targets unless matching_convention
    → nilは偽値なので早期リターン
    → targets = [] を返す

📋 生成されたマトリクス
  [] (空)

ℹ️ 結果
  デプロイメントターゲットなし
  ワークフローは正常終了（デプロイは行われない）
```

**結果**: エラーにならず、正常に処理される（デプロイは行われない）

---

## 推奨事項

### 優先順位

1. **最優先**: `generated_matrix.rb:138`を`nil`に修正
   - バグ修正
   - 影響範囲が小さい
   - 副作用がほぼない
   - **開発工数**: 0.5日

2. **高優先**: `{environment}`をオプショナル化
   - 環境非依存スタックのサポートに必要
   - 影響範囲は中程度
   - 副作用は管理可能
   - **開発工数**: 2-3日

3. **低優先**: `{service}`をオプショナル化
   - 設定の工夫で代替可能
   - 実装コストが高い
   - 複雑性が大幅に増加
   - **開発工数**: 5-7日
   - **推奨**: 実装せず、設定での対応を推奨

### 推奨される実装順序

#### Phase 1: バグ修正（即座に実装可能）

1. `generated_matrix.rb:138`を`nil`に修正
2. テストケースを追加
3. PRを作成してマージ

**期間**: 0.5日

---

#### Phase 2: 環境非依存スタックのサポート（短期）

1. `config-manager/use_cases/validate_config.rb`のバリデーション削除
2. `label-resolver/use_cases/generated_matrix.rb`に条件分岐を追加
3. `shared/entities/deployment_target.rb`に条件分岐を追加
4. テストケースを追加
5. ドキュメント更新
6. PRを作成してマージ

**期間**: 2-3日

---

#### Phase 3: 設定での対応（推奨）

`{service}`をオプショナル化せず、設定の工夫で対応：

```yaml
directory_conventions:
  - root: "{service}"
    stacks:
      - name: docker
        directory: "src"
      - name: terragrunt
        directory: "terragrunt/envs/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

  - root: "services/{service}"
    stacks: ...

services:
  - name: clusters
    exclude_from_automation: true
  - name: services
    exclude_from_automation: true
```

**期間**: 0日（設定変更のみ）

---

### 現在のPR #246の修正方法

PR #246のエラーを修正するには、以下の手順を推奨します：

#### 即座の対応（緊急）

**monorepo/workflow-config.yamlを修正**:

```yaml
directory_conventions:
  - root: "{service}"  # docs用
    stacks:
      - name: docker
        directory: "src"
      - name: terragrunt
        directory: "terragrunt/envs/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

  - root: "services/{service}"  # 他のサービス用
    stacks:
      - name: docker
        directory: "src"
      - name: terragrunt
        directory: "terragrunt/envs/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

services:
  - name: clusters
    exclude_from_automation: true
    exclusion_config:
      reason: "Cluster configuration directory"
      type: "permanent"

  - name: services
    exclude_from_automation: true
    exclusion_config:
      reason: "Parent directory for services"
      type: "permanent"
```

**この設定変更のみで、PR #246は正常に動作します。**

---

#### 中期的な対応

1. Phase 1（バグ修正）を実装
2. Phase 2（環境非依存スタック対応）を実装
3. monorepo/workflow-config.yamlから`{environment}`を削除可能に

---

### まとめ

| 変更 | 実装推奨 | 理由 |
|------|---------|------|
| `generated_matrix.rb:138`修正 | ✅ **強く推奨** | バグ修正、影響小、副作用なし |
| `{environment}`オプショナル化 | ✅ **推奨** | 環境非依存スタック対応、影響中、副作用管理可能 |
| `{service}`オプショナル化 | ❌ **非推奨** | 設定で代替可能、実装コスト高、複雑化 |

**最終推奨事項**:
1. Phase 1とPhase 2を実装
2. Phase 3は設定での対応に留める
3. 合計開発工数: 2.5-3.5日

---

## 付録: 修正コード例

### A. generated_matrix.rb:138の修正

```ruby
# ファイル: label-resolver/use_cases/generated_matrix.rb

def find_matching_convention(service_name, config)
  repo_root = find_repository_root

  config.directory_conventions_config.each do |convention|
    stacks = convention['stacks'] || []

    has_existing_directory = stacks.any? do |stack_config|
      stack_name = stack_config['name']

      @target_environments.any? do |env|
        root_pattern = convention['root']
        stack_directory = stack_config['directory']

        full_pattern = if root_pattern.nil? || root_pattern.empty?
                        stack_directory
                      else
                        "#{root_pattern}/#{stack_directory}"
                      end

        expanded_pattern = full_pattern
          .gsub('{service}', service_name)
          .gsub('{environment}', env)

        full_path = File.join(repo_root, expanded_pattern)
        File.directory?(full_path)
      end
    end

    return convention if has_existing_directory
  end

  nil  # ← 修正: [] から nil に変更
end
```

---

### B. {environment}オプショナル化の修正

```ruby
# ファイル: label-resolver/use_cases/generated_matrix.rb

def expand_directory_pattern(pattern, service_name, target_environment)
  expanded = pattern.gsub('{service}', service_name)

  # {environment}が含まれる場合のみ展開
  if pattern.include?('{environment}')
    expanded = expanded.gsub('{environment}', target_environment)
  end

  expanded
end
```

```ruby
# ファイル: shared/entities/deployment_target.rb

def self.expand_directory_pattern(pattern, service_name, target_environment)
  expanded = pattern.gsub('{service}', service_name)

  if pattern.include?('{environment}')
    expanded = expanded.gsub('{environment}', target_environment)
  end

  expanded
end
```

```ruby
# ファイル: config-manager/use_cases/validate_config.rb

# この部分を削除またはコメントアウト
# if stack['directory'] && !stack['directory'].include?('{environment}')
#   errors << "Stack '#{stack['name']}' directory must include {environment} placeholder"
# end
```

---

## 終わりに

本ドキュメントでは、プレースホルダーをオプショナル化する3つの変更について、包括的な影響分析を行いました。

**キーポイント**:
- `generated_matrix.rb:138`の修正は即座に実装すべき
- `{environment}`のオプショナル化は有用で推奨
- `{service}`のオプショナル化は不要（設定で代替可能）

ご質問や追加の調査が必要な場合は、お気軽にお申し付けください。
