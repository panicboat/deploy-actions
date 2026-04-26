# Stack-grouped attributes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** workflow-config.yaml を environment × stack のグループ化構造に変更し、stack 固有 attribute（`aws_region` 等）を任意化して `DeploymentTarget#attributes` に集約する。

**Architecture:** `DeploymentTarget` を core 5 属性 + `attributes` Hash の構造へ変更し、コンストラクタで invariant を強制（`valid?` 廃止）。`WorkflowConfig` に `stack_attributes_for` / `required_attributes_for` を追加し、必須キーは `directory_conventions[].stacks[].required_attributes` の宣言で表現。format バリデーションは廃止。

**Tech Stack:** Ruby, RSpec, FactoryBot

**作業ディレクトリ：** すべての相対パスは `/Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes/action-scripts/` を起点とする（特記がなければ `action-scripts` 直下からの相対）。

**コミット規約：** 全コミットに `-s`（DCO sign-off）を付与。`Co-Authored-By` は付与しない。

---

## Task 1: DeploymentTarget を attributes hash 構造に rewrite

**Files:**
- Create: `spec/shared/entities/deployment_target_spec.rb`
- Modify: `shared/entities/deployment_target.rb`
- Modify: `spec/factories.rb`（`:deployment_target` factory）

- [ ] **Step 1.1: failing test を新規作成**

`spec/shared/entities/deployment_target_spec.rb` を以下の内容で新規作成：

```ruby
# spec/shared/entities/deployment_target_spec.rb

require 'spec_helper'

RSpec.describe Entities::DeploymentTarget do
  describe '#initialize' do
    context 'with all required core fields' do
      it 'creates a target' do
        target = described_class.new(
          service: 'foo',
          stack: 'terragrunt',
          working_directory: 'foo/terragrunt/develop',
          environment: 'develop',
          directory_conventions_root: 'foo',
          attributes: { 'aws_region' => 'ap-northeast-1' }
        )
        expect(target.service).to eq('foo')
        expect(target.stack).to eq('terragrunt')
        expect(target.working_directory).to eq('foo/terragrunt/develop')
        expect(target.environment).to eq('develop')
        expect(target.directory_conventions_root).to eq('foo')
        expect(target.attributes).to eq('aws_region' => 'ap-northeast-1')
      end
    end

    context 'with environment-agnostic stack' do
      it 'allows nil environment' do
        target = described_class.new(
          service: 'foo',
          stack: 'docker',
          working_directory: 'foo/workspace',
          attributes: {}
        )
        expect(target.environment).to be_nil
        expect(target.attributes).to eq({})
      end
    end

    context 'with empty attributes' do
      it 'defaults attributes to empty hash' do
        target = described_class.new(
          service: 'foo',
          stack: 'kubernetes',
          working_directory: 'foo/kubernetes/overlays/develop',
          environment: 'develop'
        )
        expect(target.attributes).to eq({})
      end
    end

    context 'when service is missing' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(service: nil, stack: 'terragrunt', working_directory: 'foo')
        }.to raise_error(ArgumentError, /service/)
      end
    end

    context 'when stack is missing' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(service: 'foo', stack: nil, working_directory: 'foo/dir')
        }.to raise_error(ArgumentError, /stack/)
      end
    end

    context 'when working_directory is missing' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(service: 'foo', stack: 'terragrunt', working_directory: nil)
        }.to raise_error(ArgumentError, /working_directory/)
      end
    end

    context 'when service is empty string' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(service: '', stack: 'terragrunt', working_directory: 'foo/dir')
        }.to raise_error(ArgumentError, /service/)
      end
    end
  end

  describe '#to_matrix_item' do
    it 'returns flat hash merging core attrs and attributes with symbol keys' do
      target = described_class.new(
        service: 'foo',
        stack: 'terragrunt',
        working_directory: 'foo/terragrunt/develop',
        environment: 'develop',
        directory_conventions_root: 'foo',
        attributes: {
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123:role/plan',
          'iam_role_apply' => 'arn:aws:iam::123:role/apply'
        }
      )

      expect(target.to_matrix_item).to eq(
        service: 'foo',
        environment: 'develop',
        stack: 'terragrunt',
        working_directory: 'foo/terragrunt/develop',
        directory_conventions_root: 'foo',
        aws_region: 'ap-northeast-1',
        iam_role_plan: 'arn:aws:iam::123:role/plan',
        iam_role_apply: 'arn:aws:iam::123:role/apply'
      )
    end

    it 'omits attribute keys when attributes is empty' do
      target = described_class.new(
        service: 'foo',
        stack: 'kubernetes',
        working_directory: 'foo/kubernetes/overlays/develop',
        environment: 'develop',
        directory_conventions_root: 'foo'
      )

      expect(target.to_matrix_item).to eq(
        service: 'foo',
        environment: 'develop',
        stack: 'kubernetes',
        working_directory: 'foo/kubernetes/overlays/develop',
        directory_conventions_root: 'foo'
      )
    end
  end

  describe '#==' do
    let(:base_args) do
      {
        service: 'foo',
        stack: 'terragrunt',
        working_directory: 'foo/terragrunt/develop',
        environment: 'develop'
      }
    end

    it 'is equal when service / environment / stack / working_directory match' do
      a = described_class.new(**base_args, attributes: { 'k' => 'v1' })
      b = described_class.new(**base_args, attributes: { 'k' => 'v2' })
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it 'is not equal when working_directory differs' do
      a = described_class.new(**base_args)
      b = described_class.new(**base_args.merge(working_directory: 'foo/other'))
      expect(a).not_to eq(b)
    end
  end
end
```

- [ ] **Step 1.2: テスト実行で fail を確認**

Run: `cd action-scripts && bundle exec rspec spec/shared/entities/deployment_target_spec.rb`

Expected: FAIL（複数例。例えば `unknown keyword: :attributes` あるいは `iam_role_plan` 必須エラー等。新仕様未実装のため）

- [ ] **Step 1.3: `shared/entities/deployment_target.rb` を全面書き換え**

`shared/entities/deployment_target.rb` の全内容を以下に置換：

```ruby
# Deployment target entity representing a specific deployment configuration
# Contains all necessary information for a deployment matrix item

module Entities
  class DeploymentTarget
    attr_reader :service, :environment, :stack,
                :working_directory, :directory_conventions_root, :attributes

    def initialize(service:, stack:, working_directory:,
                   environment: nil, directory_conventions_root: nil,
                   attributes: {})
      raise ArgumentError, "service is required"           if service.nil?           || service.empty?
      raise ArgumentError, "stack is required"             if stack.nil?             || stack.empty?
      raise ArgumentError, "working_directory is required" if working_directory.nil? || working_directory.empty?

      @service                    = service
      @environment                = environment
      @stack                      = stack
      @working_directory          = working_directory
      @directory_conventions_root = directory_conventions_root
      @attributes                 = attributes.freeze
    end

    def to_matrix_item
      {
        service: service,
        environment: environment,
        stack: stack,
        working_directory: working_directory,
        directory_conventions_root: directory_conventions_root,
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

旧コードに含まれていた `from_deploy_label_and_environment` クラスメソッド、`valid?`、`expand_directory_pattern` クラスメソッドはすべて削除。

- [ ] **Step 1.4: `spec/factories.rb` の `:deployment_target` factory を更新**

`spec/factories.rb` の line 20-50（`factory :deployment_target ... :staging end`）の旧定義を以下に置換：

```ruby
  factory :deployment_target, class: 'Entities::DeploymentTarget' do
    service { "test-service" }
    environment { "develop" }
    stack { "terragrunt" }
    working_directory { "test-service/terragrunt/develop" }
    directory_conventions_root { "test-service" }
    attributes do
      {
        "aws_region" => "ap-northeast-1",
        "iam_role_plan" => "arn:aws:iam::123456789012:role/plan-role",
        "iam_role_apply" => "arn:aws:iam::123456789012:role/apply-role"
      }
    end

    initialize_with do
      new(
        service: service,
        environment: environment,
        stack: stack,
        working_directory: working_directory,
        directory_conventions_root: directory_conventions_root,
        attributes: attributes
      )
    end

    trait :kubernetes do
      stack { "kubernetes" }
      working_directory { "test-service/kubernetes/overlays/develop" }
      attributes { {} }
    end

    trait :staging do
      environment { "staging" }
      working_directory { "test-service/terragrunt/staging" }
    end
  end
```

- [ ] **Step 1.5: 新規 spec の pass を確認**

Run: `cd action-scripts && bundle exec rspec spec/shared/entities/deployment_target_spec.rb`

Expected: PASS（全 example 通過）

- [ ] **Step 1.6: コミット**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/shared/entities/deployment_target.rb \
        action-scripts/spec/shared/entities/deployment_target_spec.rb \
        action-scripts/spec/factories.rb
git commit -s -m "refactor(deployment_target): switch to attributes hash with constructor invariant"
```

---

## Task 2: WorkflowConfig に stack_attributes_for / required_attributes_for を追加

**Files:**
- Modify: `shared/entities/workflow_config.rb`
- Modify: `spec/shared/entities/workflow_config_spec.rb`

- [ ] **Step 2.1: failing test を追加**

`spec/shared/entities/workflow_config_spec.rb` の `describe '#environment_config'` ブロック（line 93-110）の直後（line 110 の `end` の後）に以下を挿入：

```ruby
  describe '#stack_attributes_for' do
    let(:config_hash) do
      {
        'environments' => [
          {
            'environment' => 'develop',
            'stacks' => {
              'terragrunt' => {
                'aws_region' => 'ap-northeast-1',
                'iam_role_plan' => 'arn:aws:iam::123:role/plan'
              },
              'kubernetes' => {}
            }
          }
        ],
        'directory_conventions' => [
          { 'root' => '{service}', 'stacks' => [
            { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' }
          ] }
        ]
      }
    end

    it 'returns attributes hash for an existing environment and stack' do
      expect(workflow_config.stack_attributes_for('develop', 'terragrunt')).to eq(
        'aws_region' => 'ap-northeast-1',
        'iam_role_plan' => 'arn:aws:iam::123:role/plan'
      )
    end

    it 'returns empty hash for stack defined as empty hash' do
      expect(workflow_config.stack_attributes_for('develop', 'kubernetes')).to eq({})
    end

    it 'returns empty hash for stack not defined under environment' do
      expect(workflow_config.stack_attributes_for('develop', 'docker')).to eq({})
    end

    it 'returns empty hash for non-existent environment' do
      expect(workflow_config.stack_attributes_for('non-existent', 'terragrunt')).to eq({})
    end

    it 'returns empty hash when environment has no stacks key' do
      hash = config_hash.dup
      hash['environments'] = [{ 'environment' => 'develop' }]
      config = described_class.new(hash)
      expect(config.stack_attributes_for('develop', 'terragrunt')).to eq({})
    end
  end

  describe '#required_attributes_for' do
    let(:config_hash) do
      {
        'environments' => [{ 'environment' => 'develop' }],
        'directory_conventions' => [
          {
            'root' => '{service}',
            'stacks' => [
              {
                'name' => 'terragrunt',
                'directory' => 'terragrunt/{environment}',
                'required_attributes' => ['aws_region', 'iam_role_plan']
              },
              {
                'name' => 'kubernetes',
                'directory' => 'kubernetes/overlays/{environment}'
              }
            ]
          }
        ]
      }
    end

    it 'returns required attributes list for the stack' do
      expect(workflow_config.required_attributes_for('terragrunt')).to eq(['aws_region', 'iam_role_plan'])
    end

    it 'returns empty array when required_attributes is not defined' do
      expect(workflow_config.required_attributes_for('kubernetes')).to eq([])
    end

    it 'returns empty array when stack is not in any convention' do
      expect(workflow_config.required_attributes_for('docker')).to eq([])
    end
  end
```

- [ ] **Step 2.2: テスト実行で fail を確認**

Run: `cd action-scripts && bundle exec rspec spec/shared/entities/workflow_config_spec.rb -e "stack_attributes_for" -e "required_attributes_for"`

Expected: FAIL（`NoMethodError: undefined method 'stack_attributes_for'` 等）

- [ ] **Step 2.3: `shared/entities/workflow_config.rb` にメソッドを追加**

`shared/entities/workflow_config.rb` の `def environment_config(env_name)` の直後（`environments[env_name]` の `end` のあと、現状 line 16-17 付近）に以下を挿入：

```ruby
    # Get stack-specific attribute hash for an environment+stack pair
    def stack_attributes_for(env_name, stack_name)
      env = environments[env_name]
      return {} unless env
      env.dig('stacks', stack_name) || {}
    end

    # Get required attribute keys declared for a stack in directory_conventions
    def required_attributes_for(stack_name)
      directory_conventions_config.each do |convention|
        stack = (convention['stacks'] || []).find { |s| s['name'] == stack_name }
        next unless stack
        return stack['required_attributes'] || []
      end
      []
    end
```

- [ ] **Step 2.4: テスト pass を確認**

Run: `cd action-scripts && bundle exec rspec spec/shared/entities/workflow_config_spec.rb -e "stack_attributes_for" -e "required_attributes_for"`

Expected: PASS

- [ ] **Step 2.5: コミット**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/shared/entities/workflow_config.rb \
        action-scripts/spec/shared/entities/workflow_config_spec.rb
git commit -s -m "feat(workflow_config): add stack_attributes_for and required_attributes_for"
```

---

## Task 3: spec_helper の default_test_config と factories の :workflow_config を新スキーマへ移行

**Files:**
- Modify: `spec/spec_helper.rb`
- Modify: `spec/factories.rb`
- Modify: `spec/shared/entities/workflow_config_spec.rb`

このタスクは多くの spec の前提（fixture）を更新する。Task 4 以降の spec が新 fixture で正しく動くようにここで完了させる。

- [ ] **Step 3.1: `spec/spec_helper.rb` の `default_test_config` を新スキーマへ書き換え**

`spec/spec_helper.rb` line 117-151 の `def default_test_config` を以下に置換：

```ruby
  # Default test configuration
  def default_test_config
    <<~YAML
      environments:
        - environment: develop
          stacks:
            terragrunt:
              aws_region: ap-northeast-1
              iam_role_plan: arn:aws:iam::123456789012:role/plan-role
              iam_role_apply: arn:aws:iam::123456789012:role/apply-role
            kubernetes: {}
        - environment: staging
          stacks:
            terragrunt:
              aws_region: ap-northeast-1
              iam_role_plan: arn:aws:iam::123456789012:role/staging-plan-role
              iam_role_apply: arn:aws:iam::123456789012:role/staging-apply-role
            kubernetes: {}
        - environment: production
          stacks:
            terragrunt:
              aws_region: ap-northeast-1
              iam_role_plan: arn:aws:iam::123456789012:role/production-plan-role
              iam_role_apply: arn:aws:iam::123456789012:role/production-apply-role
            kubernetes: {}

      directory_conventions:
        - root: "{service}"
          stacks:
            - name: terragrunt
              directory: "terragrunt/{environment}"
              required_attributes: [aws_region, iam_role_plan, iam_role_apply]
            - name: kubernetes
              directory: "kubernetes/overlays/{environment}"

      services:
        - name: demo
          directory_conventions:
            terragrunt: "services/{service}/terragrunt/envs/{environment}"
        - name: excluded-service
          exclude_from_automation: true
          exclusion_config:
            reason: "Manual deployment required"
            type: "permanent"
    YAML
  end
```

- [ ] **Step 3.2: `spec/factories.rb` の `:workflow_config` factory を新スキーマへ書き換え**

line 52-114（`factory :workflow_config` 全体）を以下に置換：

```ruby
  factory :workflow_config, class: 'Entities::WorkflowConfig' do
    config_hash do
      {
        'environments' => [
          {
            'environment' => 'develop',
            'stacks' => {
              'terragrunt' => {
                'aws_region' => 'ap-northeast-1',
                'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
                'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
              },
              'kubernetes' => {}
            }
          },
          {
            'environment' => 'staging',
            'stacks' => {
              'terragrunt' => {
                'aws_region' => 'ap-northeast-1',
                'iam_role_plan' => 'arn:aws:iam::123456789012:role/staging-plan-role',
                'iam_role_apply' => 'arn:aws:iam::123456789012:role/staging-apply-role'
              },
              'kubernetes' => {}
            }
          },
          {
            'environment' => 'production',
            'stacks' => {
              'terragrunt' => {
                'aws_region' => 'ap-northeast-1',
                'iam_role_plan' => 'arn:aws:iam::123456789012:role/production-plan-role',
                'iam_role_apply' => 'arn:aws:iam::123456789012:role/production-apply-role'
              },
              'kubernetes' => {}
            }
          }
        ],
        'directory_conventions' => [
          {
            'root' => '{service}',
            'stacks' => [
              {
                'name' => 'terragrunt',
                'directory' => 'terragrunt/{environment}',
                'required_attributes' => ['aws_region', 'iam_role_plan', 'iam_role_apply']
              },
              {
                'name' => 'kubernetes',
                'directory' => 'kubernetes/overlays/{environment}'
              }
            ]
          }
        ],
        'services' => [
          {
            'name' => 'test-service'
          }
        ]
      }
    end

    initialize_with { new(config_hash) }

    trait :with_excluded_service do
      config_hash do
        base_config = attributes_for(:workflow_config)[:config_hash]
        base_config['services'] << {
          'name' => 'excluded-service',
          'exclude_from_automation' => true,
          'exclusion_config' => {
            'reason' => 'Manual deployment required',
            'type' => 'permanent'
          }
        }
        base_config
      end
    end
  end
```

- [ ] **Step 3.3: `spec/shared/entities/workflow_config_spec.rb` のトップレベル `let(:config_hash)` を新スキーマに書き換え**

line 6-60 の `let(:config_hash) do ... end` を以下に置換：

```ruby
  let(:config_hash) do
    {
      'environments' => [
        {
          'environment' => 'develop',
          'stacks' => {
            'terragrunt' => {
              'aws_region' => 'ap-northeast-1',
              'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
              'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
            },
            'kubernetes' => {}
          }
        },
        {
          'environment' => 'staging',
          'stacks' => {
            'terragrunt' => {
              'aws_region' => 'us-west-2',
              'iam_role_plan' => 'arn:aws:iam::123456789012:role/staging-plan',
              'iam_role_apply' => 'arn:aws:iam::123456789012:role/staging-apply'
            }
          }
        },
        {
          'environment' => 'production',
          'stacks' => {
            'terragrunt' => {
              'aws_region' => 'us-west-2',
              'iam_role_plan' => 'arn:aws:iam::123456789012:role/production-plan',
              'iam_role_apply' => 'arn:aws:iam::123456789012:role/production-apply'
            }
          }
        }
      ],
      'directory_conventions' => [
        {
          'root' => '{service}',
          'stacks' => [
            {
              'name' => 'terragrunt',
              'directory' => 'terragrunt/{environment}',
              'required_attributes' => ['aws_region', 'iam_role_plan', 'iam_role_apply']
            },
            {
              'name' => 'kubernetes',
              'directory' => 'kubernetes/overlays/{environment}'
            }
          ]
        }
      ],
      'services' => [
        {
          'name' => 'test-service',
          'directory_conventions' => {
            'terragrunt' => 'services/{service}/terragrunt/envs/{environment}'
          }
        },
        {
          'name' => 'excluded-service',
          'exclude_from_automation' => true,
          'exclusion_config' => {
            'reason' => 'Manual deployment required',
            'type' => 'permanent'
          }
        }
      ]
    }
  end
```

`describe '#environments'` ブロック（line 70-80）の expectations は `aws_region` 直アクセスを止めて、stacks 配下の構造を検査する形に書き換える：

```ruby
  describe '#environments' do
    it 'returns environments hash keyed by environment name' do
      environments = workflow_config.environments

      expect(environments).to be_a(Hash)
      expect(environments.keys).to contain_exactly('develop', 'staging', 'production')
      expect(environments['develop']['stacks']['terragrunt']['aws_region']).to eq('ap-northeast-1')
      expect(environments['staging']['stacks']['terragrunt']['aws_region']).to eq('us-west-2')
      expect(environments['production']['stacks']['terragrunt']['aws_region']).to eq('us-west-2')
    end
  end
```

`describe '#environment_config'` の `with existing environment` block（line 94-102）は以下に置換：

```ruby
    context 'with existing environment' do
      it 'returns environment configuration including stacks' do
        config = workflow_config.environment_config('develop')

        expect(config['environment']).to eq('develop')
        expect(config['stacks']['terragrunt']['aws_region']).to eq('ap-northeast-1')
        expect(config['stacks']['terragrunt']['iam_role_plan']).to eq('arn:aws:iam::123456789012:role/plan-role')
      end
    end
```

- [ ] **Step 3.4: テスト実行で workflow_config_spec が通ることを確認**

Run: `cd action-scripts && bundle exec rspec spec/shared/entities/workflow_config_spec.rb`

Expected: PASS（全 example）

- [ ] **Step 3.5: 全 spec を一旦実行し、影響範囲を把握する**

Run: `cd action-scripts && bundle exec rspec 2>&1 | tail -50`

Expected: 多数の FAIL（generate_matrix_spec / validate_config_spec / config_manager_controller_spec 等。後続 task で順次修正）。**この時点でコミットせず Task 4 以降に進む**。

- [ ] **Step 3.6: コミット**

ここまでで `spec_helper.rb`, `factories.rb`, `workflow_config_spec.rb` の修正のみコミット。後続テスト修正は各 task で行う。

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/spec/spec_helper.rb \
        action-scripts/spec/factories.rb \
        action-scripts/spec/shared/entities/workflow_config_spec.rb
git commit -s -m "test: migrate fixtures to stack-grouped environment schema"
```

---

## Task 4: ConfigClient#validate_config! を新スキーマ対応に書き換え

**Files:**
- Modify: `shared/infrastructure/config_client.rb`

`ConfigClient` 単体 spec は既存しないため、後段の `validate_config_spec.rb` 経由で間接的にカバーする。

- [ ] **Step 4.1: `shared/infrastructure/config_client.rb` の `validate_config!` を書き換え**

line 87-133 の `validate_config!` メソッド全体を以下に置換：

```ruby
    # Validate the configuration structure
    def validate_config!(config_data)
      raise "Configuration must be a Hash" unless config_data.is_a?(Hash)

      # Validate required sections
      required_sections = %w[environments directory_conventions]
      missing_sections = required_sections - config_data.keys
      if missing_sections.any?
        raise "Missing required configuration sections: #{missing_sections.join(', ')}"
      end

      # Validate environments section
      environments = config_data['environments']
      raise "environments must be an Array" unless environments.is_a?(Array)

      environments.each_with_index do |env, index|
        raise "Environment #{index} must have 'environment' key" unless env['environment']

        if env.key?('stacks')
          stacks = env['stacks']
          raise "Environment #{index} 'stacks' must be a Hash" unless stacks.is_a?(Hash)
          stacks.each do |stack_name, stack_attrs|
            unless stack_attrs.nil? || stack_attrs.is_a?(Hash)
              raise "Environment #{index} stack '#{stack_name}' must be a Hash or null"
            end
          end
        end
      end

      # Validate directory_conventions structure
      conventions = config_data['directory_conventions']
      raise "directory_conventions must be an Array" unless conventions.is_a?(Array)

      conventions.each_with_index do |convention, conv_index|
        raise "directory_conventions[#{conv_index}] must have 'root' key" unless convention.key?('root')
        raise "directory_conventions[#{conv_index}] must have 'stacks' key" unless convention['stacks']

        stacks = convention['stacks']
        raise "directory_conventions[#{conv_index}].stacks must be an Array" unless stacks.is_a?(Array)

        stacks.each_with_index do |stack, stack_index|
          raise "directory_conventions[#{conv_index}].stacks[#{stack_index}] must have 'name' key" unless stack['name']
          raise "directory_conventions[#{conv_index}].stacks[#{stack_index}] must have 'directory' key" unless stack['directory']

          if stack.key?('required_attributes')
            req = stack['required_attributes']
            unless req.is_a?(Array) && req.all? { |k| k.is_a?(String) }
              raise "directory_conventions[#{conv_index}].stacks[#{stack_index}].required_attributes must be an Array of String"
            end
          end
        end
      end

      # Validate services section if present
      if config_data['services']
        services = config_data['services']
        raise "services must be an Array" unless services.is_a?(Array)

        services.each_with_index do |service, index|
          raise "Service #{index} must have 'name' key" unless service['name']
        end
      end
    end
```

旧 `aws_region` 必須チェック（line 103: `raise "Environment #{index} must have 'aws_region' key"`）は削除済み。

- [ ] **Step 4.2: 既存 spec へのインパクトを確認**

Run: `cd action-scripts && bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb 2>&1 | tail -30`

Expected: integration テスト（line 122-148）は default_test_config が新スキーマなので通過する見込み。一部失敗があっても次 task で修正する。

- [ ] **Step 4.3: コミット**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/shared/infrastructure/config_client.rb
git commit -s -m "refactor(config_client): validate stack-grouped environment schema"
```

---

## Task 5: ValidateConfig use case を required_attributes ベースに書き換え

**Files:**
- Modify: `config-manager/use_cases/validate_config.rb`
- Modify: `spec/config-manager/use_cases/validate_config_spec.rb`

- [ ] **Step 5.1: failing test を追加**

`spec/config-manager/use_cases/validate_config_spec.rb` の `describe '#execute'` ブロック内、`context 'with empty configuration' do ... end`（line 98-112）の直後（line 112 の `end` の後）に以下を挿入：

```ruby
    context 'when required_attributes are not satisfied' do
      let(:config_hash) do
        {
          'environments' => [
            {
              'environment' => 'develop',
              'stacks' => {
                'terragrunt' => {
                  'aws_region' => 'ap-northeast-1'
                  # iam_role_plan / iam_role_apply missing
                }
              }
            }
          ],
          'directory_conventions' => [
            {
              'root' => '{service}',
              'stacks' => [
                {
                  'name' => 'terragrunt',
                  'directory' => 'terragrunt/{environment}',
                  'required_attributes' => ['aws_region', 'iam_role_plan', 'iam_role_apply']
                }
              ]
            }
          ],
          'services' => []
        }
      end
      let(:config) { Entities::WorkflowConfig.new(config_hash) }

      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
      end

      it 'reports missing required attributes' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.validation_errors.join(' ')).to include('iam_role_plan')
        expect(result.validation_errors.join(' ')).to include('iam_role_apply')
      end
    end

    context 'when required_attributes is empty array' do
      let(:config_hash) do
        {
          'environments' => [{ 'environment' => 'develop', 'stacks' => { 'terragrunt' => {} } }],
          'directory_conventions' => [
            {
              'root' => '{service}',
              'stacks' => [
                {
                  'name' => 'terragrunt',
                  'directory' => 'terragrunt/{environment}',
                  'required_attributes' => []
                }
              ]
            }
          ],
          'services' => []
        }
      end
      let(:config) { Entities::WorkflowConfig.new(config_hash) }

      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
      end

      it 'skips validation' do
        result = use_case.execute
        expect(result).to be_success
      end
    end

    context 'when required_attributes is omitted' do
      let(:config_hash) do
        {
          'environments' => [{ 'environment' => 'develop' }],
          'directory_conventions' => [
            {
              'root' => '{service}',
              'stacks' => [
                {
                  'name' => 'kubernetes',
                  'directory' => 'kubernetes/overlays/{environment}'
                }
              ]
            }
          ],
          'services' => []
        }
      end
      let(:config) { Entities::WorkflowConfig.new(config_hash) }

      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
      end

      it 'is treated as no required attributes' do
        result = use_case.execute
        expect(result).to be_success
      end
    end
```

- [ ] **Step 5.2: テスト実行で fail を確認**

Run: `cd action-scripts && bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb -e "required_attributes"`

Expected: FAIL（旧実装は environments 直下の `aws_region` 必須をチェックしているため、新形式の test fixture で見当違いのエラーを出す）

- [ ] **Step 5.3: `config-manager/use_cases/validate_config.rb` の `validate_environment_config` を書き換え**

line 67-90 の `validate_environment_config` を以下に置換：

```ruby
      # Validate individual environment configuration
      def validate_environment_config(env_name, env_config, config)
        errors = []

        # Validate stacks structure if present
        if env_config.key?('stacks')
          stacks = env_config['stacks']
          unless stacks.is_a?(Hash)
            errors << "Environment '#{env_name}' 'stacks' must be a Hash"
            return errors
          end
        end

        # Check required_attributes for each stack declared in directory_conventions
        config.directory_conventions_config.each do |convention|
          (convention['stacks'] || []).each do |stack_def|
            stack_name = stack_def['name']
            required = stack_def['required_attributes'] || []
            next if required.empty?

            stack_attrs = env_config.dig('stacks', stack_name) || {}
            required.each do |attr|
              unless stack_attrs.key?(attr)
                errors << "Environment '#{env_name}' missing required attribute for stack '#{stack_name}': #{attr}"
              end
            end
          end
        end

        errors
      end
```

呼び出し元（line 59-61 の `validate_environments`）は引数 `config` を渡す必要があるので、以下に書き換える：

line 46-64 の `validate_environments` を以下に置換：

```ruby
      # Validate environments configuration
      def validate_environments(config)
        errors = []
        environments = config.environments

        if environments.empty?
          errors << "No environments defined"
          return errors
        end

        environments.each do |env_name, env_config|
          errors.concat(validate_environment_config(env_name, env_config, config))
        end

        errors
      end
```

- [ ] **Step 5.4: テスト pass を確認**

Run: `cd action-scripts && bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb`

Expected: PASS（全 example。新規追加分も既存分も通過）

- [ ] **Step 5.5: コミット**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/config-manager/use_cases/validate_config.rb \
        action-scripts/spec/config-manager/use_cases/validate_config_spec.rb
git commit -s -m "refactor(validate_config): use required_attributes for environment validation"
```

---

## Task 6: GenerateMatrix の create_*_target を統合し attributes 駆動に変更

**Files:**
- Modify: `label-resolver/use_cases/generated_matrix.rb`
- Modify: `spec/label-resolver/use_cases/generate_matrix_spec.rb`

- [ ] **Step 6.1: `label-resolver/use_cases/generated_matrix.rb` の create_*_target を 1 つに統合**

line 277-333 の `create_terragrunt_target` / `create_kubernetes_target` / `create_generic_target` の 3 メソッドと line 278-286 の `case stack ... end` ブロック（`generate_deployment_target` 末尾の dispatch）を以下に置換：

`generate_deployment_target` の末尾（line 277-287 を含む block）を以下のように変更：

```ruby
        return nil unless working_dir

        create_deployment_target(deploy_label, target_environment, stack, working_dir, config)
      end

      # Create deployment target (unified across stacks)
      def create_deployment_target(deploy_label, target_environment, stack, working_dir, config)
        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: stack,
          working_directory: working_dir,
          directory_conventions_root: extract_root_from_working_dir(working_dir, deploy_label.service, target_environment, config),
          attributes: target_environment ? config.stack_attributes_for(target_environment, stack) : {}
        )
      end
```

旧 `create_terragrunt_target` / `create_kubernetes_target` / `create_generic_target` メソッドは削除。

また `generate_deployment_target` 内の以下の行（line 252）：

```ruby
        env_config = target_environment ? config.environment_config(target_environment) : nil
```

は削除（`env_config` は新実装では使わない）。

- [ ] **Step 6.2: `target&.valid?` ガードを削除**

line 98 の `targets << target if target&.valid?` および line 107 の同様の行を `targets << target if target` に置換：

```ruby
              if stack_directory_exists?(deploy_label.service, env, stack_name, config)
                target = generate_deployment_target(deploy_label, env, stack_name, config)
                targets << target if target
              end
```

```ruby
            if stack_directory_exists?(deploy_label.service, first_env, stack_name, config)
              target = generate_deployment_target(deploy_label, nil, stack_name, config)
              targets << target if target
            end
```

`generate_deployment_target` は working_dir が見つからなければ `nil` を返すので、その nil ガードは残す。

- [ ] **Step 6.3: `spec/label-resolver/use_cases/generate_matrix_spec.rb` の修正**

変更ポイント：

(a) line 20-27 の `let(:env_config)` を新スキーマに（stacks ネスト）。`environment_config` を mock している箇所は env 全体（stacks 含む）を返すように修正。

line 20-27 を以下に置換：

```ruby
      let(:env_config) do
        {
          'environment' => 'develop',
          'stacks' => {
            'terragrunt' => {
              'aws_region' => 'ap-northeast-1',
              'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
              'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
            },
            'kubernetes' => {}
          }
        }
      end
```

(b) `before do` ブロック（line 29-47）に `stack_attributes_for` のスタブを追加：

`allow(config).to receive(:directory_conventions_root).and_return('{service}')` の直後に：

```ruby
        allow(config).to receive(:stack_attributes_for).with('develop', 'terragrunt').and_return(env_config['stacks']['terragrunt'])
        allow(config).to receive(:stack_attributes_for).with('develop', 'kubernetes').and_return({})
```

(c) 同様の修正を以下の context にも適用：

- `context 'with deploy:all label' do`（line 72-118）
- `context 'with mixed valid and invalid labels' do`（line 245-280）
- `context 'with environment-agnostic stack (docker)' do`（line 282-360）

それぞれの `before do` ブロック内、`environment_config` を mock している箇所の直後に、対応する `stack_attributes_for` のスタブを追加：

deploy:all label のケース（line 90-95 の `environment_config` mock の直後）：

```ruby
        allow(config).to receive(:stack_attributes_for).with('develop', 'terragrunt').and_return({
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
        })
        allow(config).to receive(:stack_attributes_for).with('develop', 'kubernetes').and_return({})
```

mixed valid/invalid labels のケース（line 254-259 の `environment_config` mock の直後）：同上

environment-agnostic (docker) のケース（line 310-312 の `environment_config` mock の直後）：

```ruby
        allow(config).to receive(:stack_attributes_for).with('develop', 'terragrunt').and_return({
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
        })
        allow(config).to receive(:stack_attributes_for).with('staging', 'terragrunt').and_return({
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/staging-plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/staging-apply-role'
        })
        allow(config).to receive(:stack_attributes_for).with('production', 'terragrunt').and_return({
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/prod-plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/prod-apply-role'
        })
        allow(config).to receive(:stack_attributes_for).with('develop', 'kubernetes').and_return({})
        allow(config).to receive(:stack_attributes_for).with('staging', 'kubernetes').and_return({})
        allow(config).to receive(:stack_attributes_for).with('production', 'kubernetes').and_return({})
```

(d) docker 用のスタブも必要。line 327 の `directory_conventions_for ... docker` mock の直後に：

```ruby
        # docker is environment-agnostic, but stub returning empty in case called
        allow(config).to receive(:stack_attributes_for).with(anything, 'docker').and_return({})
```

(e) `service-specific directory conventions` の context（line 189-227）でも同様：

line 200 の `environment_config` mock の直後に：

```ruby
        allow(config).to receive(:stack_attributes_for).with('develop', 'terragrunt').and_return(env_config['stacks']['terragrunt'])
```

ここでの `env_config` は line 190-197 で定義されているので、上記書き換えとあわせて：

line 190-197 を以下に置換：

```ruby
      let(:env_config) do
        {
          'environment' => 'develop',
          'stacks' => {
            'terragrunt' => {
              'aws_region' => 'ap-northeast-1',
              'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
              'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
            }
          }
        }
      end
```

- [ ] **Step 6.4: テスト実行で pass を確認**

Run: `cd action-scripts && bundle exec rspec spec/label-resolver/use_cases/generate_matrix_spec.rb`

Expected: PASS（全 example）

- [ ] **Step 6.5: コミット**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/label-resolver/use_cases/generated_matrix.rb \
        action-scripts/spec/label-resolver/use_cases/generate_matrix_spec.rb
git commit -s -m "refactor(generate_matrix): unify deployment target creation via attributes"
```

---

## Task 7: Presenters の target.aws_region 等を attributes 経由に切り替え

**Files:**
- Modify: `shared/interfaces/presenters/console_presenter.rb`
- Modify: `shared/interfaces/presenters/github_actions_presenter.rb`

- [ ] **Step 7.1: `shared/interfaces/presenters/console_presenter.rb#present_deployment_matrix` の書き換え**

line 59-67 の env / target ループを以下に置換：

```ruby
        targets_by_env.each do |env, targets|
          puts "\n  Environment: #{env}".colorize(:cyan)
          targets.each do |target|
            puts "    #{target.service}:#{target.stack} -> #{target.working_directory}"
            target.attributes.each do |key, value|
              puts "      #{key}: #{value}"
            end
          end
        end
```

- [ ] **Step 7.2: `console_presenter.rb#present_service_test_result` の書き換え**

`present_service_test_result` の シグネチャを変更し、env_config 直アクセスを attributes hash に切り替える。line 101-110 を以下に置換：

```ruby
      # Present service test results
      def present_service_test_result(service_name:, environment:, stack_attributes:, service_config:, terragrunt_directory:, kubernetes_directory:)
        puts "🔧 Service Configuration Test".colorize(:blue)
        puts "Service: #{service_name}"
        puts "Environment: #{environment}"
        puts "Terragrunt Directory: #{terragrunt_directory}"
        puts "Kubernetes Directory: #{kubernetes_directory}"
        stack_attributes.each do |stack_name, attrs|
          puts "Stack '#{stack_name}':"
          attrs.each { |key, value| puts "  #{key}: #{value}" }
        end
      end
```

- [ ] **Step 7.3: `shared/interfaces/presenters/github_actions_presenter.rb#present_service_test_result` の書き換え**

line 126-135 を以下に置換：

```ruby
      # Present service test results
      def present_service_test_result(service_name:, environment:, stack_attributes:, service_config:, terragrunt_directory:, kubernetes_directory:)
        puts "🔧 Service Configuration Test"
        puts "Service: #{service_name}"
        puts "Environment: #{environment}"
        puts "Terragrunt Directory: #{terragrunt_directory}"
        puts "Kubernetes Directory: #{kubernetes_directory}"
        stack_attributes.each do |stack_name, attrs|
          puts "Stack '#{stack_name}':"
          attrs.each { |key, value| puts "  #{key}: #{value}" }
        end
      end
```

- [ ] **Step 7.4: `github_actions_presenter.rb#present_config_details` の dead reference を削除**

line 113-123 の `present_config_details` 内で `config.terraform_version` / `config.terragrunt_version` を呼んでいるが `WorkflowConfig` にこれらメソッドは存在しない（dead reference）。line 118-120 を削除：

```ruby
      # Present configuration details
      def present_config_details(config:)
        puts "📋 Workflow Configuration"
        puts "Environments: #{config.environments.keys.join(', ')}"
        puts "Services: #{config.services.keys.join(', ')}"

        puts "\nDirectory Conventions:"
        config.directory_conventions.each do |convention|
          root = convention['root']
          (convention['stacks'] || []).each do |stack|
            puts "  #{stack['name']}: #{root}/#{stack['directory']}"
          end
        end
      end
```

`console_presenter.rb#present_config_details`（line 91-98）も同様に書き換える：

```ruby
      # Present configuration details
      def present_config_details(config:)
        puts "📋 Workflow Configuration".colorize(:blue)
        puts "Environments: #{config.environments.keys.join(', ')}"
        puts "Services: #{config.services.keys.join(', ')}"

        puts "\nDirectory Conventions:"
        config.directory_conventions.each do |convention|
          root = convention['root']
          (convention['stacks'] || []).each do |stack|
            puts "  #{stack['name']}: #{root}/#{stack['directory']}"
          end
        end
      end
```

- [ ] **Step 7.5: テスト実行**

Run: `cd action-scripts && bundle exec rspec`

Expected: PASS（presenter 関連 spec が直接無いため、controller spec / use case spec 経由で正常）

- [ ] **Step 7.6: コミット**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/shared/interfaces/presenters/console_presenter.rb \
        action-scripts/shared/interfaces/presenters/github_actions_presenter.rb
git commit -s -m "refactor(presenters): drop env_config direct access, use attributes hash"
```

---

## Task 8: ConfigManagerController#test_service_configuration と build_config_template の更新

**Files:**
- Modify: `config-manager/controllers/config_manager_controller.rb`
- Modify: `spec/config-manager/controllers/config_manager_controller_spec.rb`

- [ ] **Step 8.1: `test_service_configuration` を新シグネチャに合わせて更新**

`config-manager/controllers/config_manager_controller.rb` の line 67-86 を以下に置換：

```ruby
          # Get service configurations
          service_config = config.services[service_name]

          # Test directory conventions
          terragrunt_dir = config.directory_convention_for(service_name, 'terragrunt')
            &.gsub('{service}', service_name)
            &.gsub('{environment}', environment)

          kubernetes_dir = config.directory_convention_for(service_name, 'kubernetes')
            &.gsub('{service}', service_name)
            &.gsub('{environment}', environment)

          # Collect stack attributes for all stacks declared in directory_conventions
          stack_attributes = {}
          config.directory_conventions_config.each do |convention|
            (convention['stacks'] || []).each do |stack_def|
              stack_name = stack_def['name']
              stack_attributes[stack_name] = config.stack_attributes_for(environment, stack_name)
            end
          end

          @presenter.present_service_test_result(
            service_name: service_name,
            environment: environment,
            stack_attributes: stack_attributes,
            service_config: service_config,
            terragrunt_directory: terragrunt_dir,
            kubernetes_directory: kubernetes_dir
          )
```

- [ ] **Step 8.2: `build_config_template` を新スキーマに更新**

line 161-207 の `build_config_template` 内 heredoc を以下に置換：

```ruby
      def build_config_template
        <<~YAML
          # Workflow Automation Configuration Template
          # Generated by config-manager

          environments:
            - environment: develop
              stacks:
                terragrunt:
                  aws_region: ap-northeast-1
                  iam_role_plan: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-develop-plan-role
                  iam_role_apply: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-develop-apply-role
                kubernetes: {}

            - environment: staging
              stacks:
                terragrunt:
                  aws_region: ap-northeast-1
                  iam_role_plan: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-staging-plan-role
                  iam_role_apply: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-staging-apply-role
                kubernetes: {}

            - environment: production
              stacks:
                terragrunt:
                  aws_region: ap-northeast-1
                  iam_role_plan: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-production-plan-role
                  iam_role_apply: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-production-apply-role
                kubernetes: {}

          directory_conventions:
            - root: "{service}"
              stacks:
                - name: terragrunt
                  directory: "terragrunt/{environment}"
                  required_attributes: [aws_region, iam_role_plan, iam_role_apply]
                - name: kubernetes
                  directory: "kubernetes/overlays/{environment}"

          services:
            - name: excluded-service
              exclude_from_automation: true
              exclusion_config:
                reason: "Manual deployment required due to special requirements"
                type: "permanent"
        YAML
      end
```

- [ ] **Step 8.3: 既存 controller spec の影響を確認・修正**

Run: `cd action-scripts && bundle exec rspec spec/config-manager/controllers/config_manager_controller_spec.rb`

`test_service_configuration` を呼んでいるテストで `present_service_test_result` の `env_config:` を渡している箇所があれば、`stack_attributes:` に書き換える。具体的な変更箇所は spec 実行時の失敗メッセージに従って書き換え：

- 失敗テストで `present_service_test_result` のシグネチャ不一致が出る場合、該当 spec 内の `env_config: anything` を `stack_attributes: anything` に置換。
- 失敗テストで `env_config` を引数として明示的に検証している場合、`stack_attributes` 構造を期待するように修正。

例（推定）：

```ruby
expect(presenter).to receive(:present_service_test_result).with(
  hash_including(
    service_name: 'test-service',
    environment: 'develop',
    stack_attributes: hash_including('terragrunt' => hash_including('aws_region' => 'ap-northeast-1'))
  )
)
```

- [ ] **Step 8.4: テスト pass を確認**

Run: `cd action-scripts && bundle exec rspec spec/config-manager/`

Expected: PASS

- [ ] **Step 8.5: コミット**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/config-manager/controllers/config_manager_controller.rb \
        action-scripts/spec/config-manager/controllers/config_manager_controller_spec.rb
git commit -s -m "refactor(config_manager): pass stack_attributes hash to presenter and update template"
```

---

## Task 9: workflow-config.yaml を新スキーマに書き換え

**Files:**
- Modify: `workflow-config.yaml`

- [ ] **Step 9.1: `action-scripts/workflow-config.yaml` を新スキーマに書き換え**

`workflow-config.yaml` の全内容を以下に置換：

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

directory_conventions:
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
      type: "permanent"
```

- [ ] **Step 9.2: config-manager で新 YAML が valid と判定されることを確認**

Run: `cd action-scripts && WORKFLOW_CONFIG_PATH=workflow-config.yaml bundle exec ruby config-manager/bin/config-manager validate 2>&1`

Expected: `✅ Configuration is valid` または同等の成功表示。エラーがあれば該当箇所を修正。

- [ ] **Step 9.3: コミット**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git add action-scripts/workflow-config.yaml
git commit -s -m "chore(workflow-config): migrate to stack-grouped environment schema"
```

---

## Task 10: 全 spec 通過確認 + label-resolver 出力の手動確認

**Files:**
- (verification only)

- [ ] **Step 10.1: 全 spec を実行**

Run: `cd action-scripts && bundle exec rspec`

Expected: 全 example が PASS。失敗があれば該当 task に戻って修正し、追加コミットを作成。

- [ ] **Step 10.2: label-resolver の matrix 出力を手元で確認**

Run:
```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes/action-scripts
SOURCE_REPO_PATH=../../../ \
  bundle exec ruby label-resolver/bin/label-resolver \
  --deploy-labels '["deploy:demo"]' \
  --target-environments '["develop"]' \
  2>&1 | tail -30 || true
```

Expected: 例外なく終了し、`HAS_TARGETS=false` または demo は exclude されてスキップされる旨のメッセージが表示される。

- [ ] **Step 10.3: 設計書通りの kubernetes target 出力を確認（任意）**

設計上の確認のため、`workflow-config.yaml` の demo を一時的に普通のサービスとして登録した小さな fixture を別途作って `WORKFLOW_CONFIG_PATH` で指定し、kubernetes target の matrix item に `aws_region` キーが含まれていないことを目視で確認。実環境を変更しない範囲でテンポラリにのみ実施。本ステップは省略可。

- [ ] **Step 10.4: PR 用最終確認**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-stack-grouped-attributes
git status
git log --oneline origin/main..HEAD
```

Expected: 全コミットが想定通り並んでおり、未コミットの差分なし。

PR は `--draft` で作成（global CLAUDE.md ルール）。PR 説明文には：
- 本リポジトリの workflow-config.yaml は新スキーマに移行済み
- monorepo / platform の workflow-config.yaml 移行は別 PR で対応する旨
- 後段 action（panicboat-actions）は変更不要
- monorepo / platform の利用側 workflow ファイルは変更不要

を明記。

---

## Self-Review Notes

- **Spec coverage**：spec の全要求項目（schema, validation, generate_matrix, presenters, controller, template, workflow-config 移行）が Task 1〜9 にマッピングされている。Test strategy の追加観点（attributes 空 hash, ArgumentError, required_attributes 未定義/空など）はそれぞれ Task 1 / Task 2 / Task 5 に対応する step がある。
- **Type consistency**：`stack_attributes_for(env, stack)`, `required_attributes_for(stack)`, `present_service_test_result(... stack_attributes: ...)` のシグネチャはタスク横断で統一。
- **Placeholder**：未定義の参照や TODO はなし。Task 8 Step 8.3 のみ「失敗メッセージに従って修正」と記載しており、これは spec 全体のロード後にしか具体内容が判明しない正当な動的調整である（推定の例コードを併記済み）。
