# Uniform Placeholder Handling via PatternMatcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Entities::PatternMatcher` to unify placeholder regex generation, expansion, and extraction across label-dispatcher, label-resolver, and config-manager; flatten captured placeholder values into `DeploymentTarget` matrix output; reject reserved-name collisions and structurally ambiguous conventions at validate time.

**Architecture:** Introduce a single Value Object (`Entities::PatternMatcher`) in `action-scripts/shared/entities/` that owns three operations (`placeholders`, `expand`, `extract`/`extract_prefix`). All three components route placeholder work through it. `DeploymentTarget` gains an optional `captures:` keyword that merges into `to_matrix_item` alongside `attributes`. `validate_config` rejects collisions and ambiguous structures before runtime.

**Tech Stack:** Ruby 4.0.3, RSpec, the existing action-scripts modules (`config-manager`, `label-dispatcher`, `label-resolver`, `shared`). Auto-load via `shared/shared_loader.rb` picks up new entity files in `shared/entities/`.

---

## Working Environment

All work happens in this worktree:

```
/Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/feat-uniform-placeholders/
```

Branch: `feat/uniform-placeholders` (already tracking `origin/main`).

All file paths below are relative to that worktree root. All test commands run from inside `action-scripts/`:

```bash
cd action-scripts
bundle exec rspec <args>
```

If `bundle install` has not been run in the worktree yet, run it once before Task 1:

```bash
cd action-scripts
bundle install
```

## File Map

| File | Status | Responsibility |
|---|---|---|
| `action-scripts/shared/entities/pattern_matcher.rb` | New | Pattern grammar value object: `placeholders`, `expand`, `extract`, `extract_prefix`, error class |
| `action-scripts/shared/entities/deployment_target.rb` | Modify | Add `captures:` keyword; merge into `to_matrix_item`; reject collisions with fixed fields and `attributes` keys |
| `action-scripts/label-dispatcher/use_cases/detect_changed_services.rb` | Modify | Replace hand-rolled gsub regex with `PatternMatcher.extract_prefix`; read `service` key from captures |
| `action-scripts/label-resolver/use_cases/generated_matrix.rb` | Modify | Replace `expand_directory_pattern` and `find_matching_conventions` gsub logic with `PatternMatcher.expand`; extract captures from working_dir; raise instead of `puts "Warning..."` |
| `action-scripts/config-manager/use_cases/validate_config.rb` | Modify | Add four new validation rules: fixed reserved names, dynamic reserved names, syntax-outside `{...}` literals, structural equivalence |
| `action-scripts/spec/shared/entities/pattern_matcher_spec.rb` | New | Specs for all PatternMatcher methods |
| `action-scripts/spec/shared/entities/deployment_target_spec.rb` | Modify | Add specs for `captures:` argument and collision detection |
| `action-scripts/spec/label-dispatcher/use_cases/detect_changed_services_spec.rb` | Modify | Add spec for arbitrary placeholder pattern still detecting `service` |
| `action-scripts/spec/label-resolver/use_cases/generated_matrix_spec.rb` | Modify | Add specs for captures flattened in matrix items and `Warning` paths now raising |
| `action-scripts/spec/config-manager/use_cases/validate_config_spec.rb` | Modify | Add specs for the four new validation rules |
| `README.md` | Modify | Add Matrix Output section, update Configuration example |
| `README-ja.md` | Modify | Mirror README.md in Japanese (headings stay English) |
| `action-scripts/config-manager/README.md` | Modify | Add Placeholder rules section |

`shared/shared_loader.rb` already does `Dir[...].sort` over `entities/**/*.rb`, so dropping `pattern_matcher.rb` into `shared/entities/` is enough to make it loadable; no require edits.

## Reserved Name Constants

When implementing collision checks, use these exact lists:

- **Fixed reserved names** (forbidden as placeholder names):
  - `stack`
  - `working_directory`
  - `stack_convention_root`
- **Allowed built-ins** (placeholders that map to dedicated keyword args, not captures):
  - `service`
  - `environment`
- **Dynamic reserved names**: every key found under any `environments[].stacks[<stack_name>]` hash in the loaded config (e.g. `aws_region`, `iam_role_plan`, `iam_role_apply`).

---

## Task 1: PatternMatcher — placeholders method

**Files:**
- Create: `action-scripts/shared/entities/pattern_matcher.rb`
- Test: `action-scripts/spec/shared/entities/pattern_matcher_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `action-scripts/spec/shared/entities/pattern_matcher_spec.rb`:

```ruby
# spec/shared/entities/pattern_matcher_spec.rb

require 'spec_helper'

RSpec.describe Entities::PatternMatcher do
  describe '.placeholders' do
    it 'returns a single placeholder name' do
      expect(described_class.placeholders('{service}')).to eq(['service'])
    end

    it 'returns all placeholder names in left-to-right order' do
      expect(
        described_class.placeholders('{team}/{service}/terragrunt/{environment}')
      ).to eq(%w[team service environment])
    end

    it 'preserves duplicates' do
      expect(described_class.placeholders('{a}/{a}')).to eq(%w[a a])
    end

    it 'ignores uppercase names' do
      expect(described_class.placeholders('{Foo}')).to eq([])
    end

    it 'ignores hyphenated names' do
      expect(described_class.placeholders('{my-var}')).to eq([])
    end

    it 'ignores names with whitespace' do
      expect(described_class.placeholders('{a b}')).to eq([])
    end

    it 'returns empty for patterns with no placeholders' do
      expect(described_class.placeholders('static/path')).to eq([])
    end

    it 'returns empty for nil' do
      expect(described_class.placeholders(nil)).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd action-scripts
bundle exec rspec spec/shared/entities/pattern_matcher_spec.rb
```

Expected: `NameError: uninitialized constant Entities::PatternMatcher` (the file does not exist yet).

- [ ] **Step 3: Create the entity file with minimal implementation**

Create `action-scripts/shared/entities/pattern_matcher.rb`:

```ruby
# Value object encoding workflow-config placeholder grammar.
# Used by label-dispatcher, label-resolver, and config-manager to share
# a single source of truth for "{name}" handling.

module Entities
  class PatternMatcher
    # Matches placeholders like {service}, {team}, {env_a1}.
    # Uppercase and hyphenated names ({Team}, {my-var}) are treated as literals.
    PLACEHOLDER_REGEX = /\{([a-z_][a-z0-9_]*)\}/

    # Returns placeholder names in left-to-right order, including duplicates.
    def self.placeholders(pattern)
      return [] if pattern.nil?
      pattern.scan(PLACEHOLDER_REGEX).map(&:first)
    end
  end

  class UnresolvedPlaceholderError < StandardError; end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd action-scripts
bundle exec rspec spec/shared/entities/pattern_matcher_spec.rb
```

Expected: 8 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add action-scripts/shared/entities/pattern_matcher.rb action-scripts/spec/shared/entities/pattern_matcher_spec.rb
git commit -s -m "feat(shared): add Entities::PatternMatcher.placeholders"
```

---

## Task 2: PatternMatcher — expand method

**Files:**
- Modify: `action-scripts/shared/entities/pattern_matcher.rb`
- Test: `action-scripts/spec/shared/entities/pattern_matcher_spec.rb`

- [ ] **Step 1: Append the failing tests**

Append to `action-scripts/spec/shared/entities/pattern_matcher_spec.rb` (before the final `end` of the `RSpec.describe` block):

```ruby
  describe '.expand' do
    it 'substitutes a single placeholder' do
      expect(described_class.expand('{service}', { 'service' => 'api' })).to eq('api')
    end

    it 'substitutes multiple placeholders' do
      result = described_class.expand(
        '{team}/{service}/terragrunt/{environment}',
        { 'team' => 'payments', 'service' => 'api', 'environment' => 'develop' }
      )
      expect(result).to eq('payments/api/terragrunt/develop')
    end

    it 'substitutes duplicate placeholders with the same value' do
      expect(described_class.expand('{a}/{a}', { 'a' => 'x' })).to eq('x/x')
    end

    it 'returns the pattern unchanged when it has no placeholders' do
      expect(described_class.expand('static/path', {})).to eq('static/path')
    end

    it 'raises UnresolvedPlaceholderError when a placeholder has no value' do
      expect {
        described_class.expand('{a}/{b}', { 'a' => 'x' })
      }.to raise_error(Entities::UnresolvedPlaceholderError, /b/)
    end

    it 'raises ArgumentError when a substituted value contains "/"' do
      expect {
        described_class.expand('{a}', { 'a' => 'x/y' })
      }.to raise_error(ArgumentError, %r{/})
    end

    it 'does not validate unused values' do
      # value for 'unused' contains "/" but is never substituted, so no error
      expect(
        described_class.expand('{a}', { 'a' => 'x', 'unused' => 'has/slash' })
      ).to eq('x')
    end
  end
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run:

```bash
cd action-scripts
bundle exec rspec spec/shared/entities/pattern_matcher_spec.rb
```

Expected: 8 examples pass (the placeholders specs), 7 examples fail with `NoMethodError: undefined method 'expand'`.

- [ ] **Step 3: Implement expand**

Insert into `action-scripts/shared/entities/pattern_matcher.rb` inside the `PatternMatcher` class, after the `placeholders` method:

```ruby
    # Substitutes {name} with values[name]. Values are looked up by string key.
    # Raises UnresolvedPlaceholderError if a placeholder has no value.
    # Raises ArgumentError if a substituted value contains "/".
    def self.expand(pattern, values)
      return pattern if pattern.nil?

      pattern.gsub(PLACEHOLDER_REGEX) do
        name = Regexp.last_match(1)
        unless values.key?(name)
          raise UnresolvedPlaceholderError, "no value for '{#{name}}' in pattern: #{pattern}"
        end
        value = values[name].to_s
        if value.include?('/')
          raise ArgumentError, "value for '{#{name}}' must not contain '/': #{value}"
        end
        value
      end
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd action-scripts
bundle exec rspec spec/shared/entities/pattern_matcher_spec.rb
```

Expected: 15 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add action-scripts/shared/entities/pattern_matcher.rb action-scripts/spec/shared/entities/pattern_matcher_spec.rb
git commit -s -m "feat(shared): add Entities::PatternMatcher.expand"
```

---

## Task 3: PatternMatcher — extract and extract_prefix

**Files:**
- Modify: `action-scripts/shared/entities/pattern_matcher.rb`
- Test: `action-scripts/spec/shared/entities/pattern_matcher_spec.rb`

- [ ] **Step 1: Append the failing tests**

Append to `action-scripts/spec/shared/entities/pattern_matcher_spec.rb` before the final `end`:

```ruby
  describe '.extract' do
    it 'returns the captured value as a Hash on a full match' do
      expect(described_class.extract('{service}', 'api')).to eq('service' => 'api')
    end

    it 'returns all captures on a full match with multiple placeholders' do
      expect(
        described_class.extract('{team}/{service}/terragrunt/{environment}', 'payments/api/terragrunt/develop')
      ).to eq('team' => 'payments', 'service' => 'api', 'environment' => 'develop')
    end

    it 'returns nil when path has more segments than pattern' do
      expect(described_class.extract('{service}', 'api/extra')).to be_nil
    end

    it 'returns nil when path has fewer segments than pattern' do
      expect(described_class.extract('{a}/{b}', 'one')).to be_nil
    end

    it 'returns nil when a literal segment does not match' do
      expect(described_class.extract('a/{service}', 'b/c')).to be_nil
    end

    it 'returns an empty hash when the pattern has no placeholders and matches' do
      expect(described_class.extract('static', 'static')).to eq({})
    end

    it 'returns nil when a duplicate placeholder gets different values' do
      expect(described_class.extract('{a}/{a}', 'x/y')).to be_nil
    end

    it 'returns the single value when a duplicate placeholder gets the same value' do
      expect(described_class.extract('{a}/{a}', 'x/x')).to eq('a' => 'x')
    end

    it 'returns nil for nil pattern or path' do
      expect(described_class.extract(nil, 'x')).to be_nil
      expect(described_class.extract('{a}', nil)).to be_nil
    end
  end

  describe '.extract_prefix' do
    it 'matches the prefix and ignores additional segments' do
      result = described_class.extract_prefix(
        '{service}/terragrunt',
        'foo/terragrunt/develop/main.tf'
      )
      expect(result).to eq('service' => 'foo')
    end

    it 'matches when path equals the pattern exactly' do
      expect(
        described_class.extract_prefix('{service}/terragrunt', 'foo/terragrunt')
      ).to eq('service' => 'foo')
    end

    it 'returns nil when the path is shorter than the pattern' do
      expect(described_class.extract_prefix('{a}/{b}/c', 'x/y')).to be_nil
    end

    it 'returns nil when a literal segment does not match' do
      expect(described_class.extract_prefix('a/{b}', 'x/y/z')).to be_nil
    end

    it 'returns an empty hash when the pattern has no placeholders and the prefix matches' do
      expect(described_class.extract_prefix('static', 'static/sub/path')).to eq({})
    end

    it 'returns nil for nil pattern or path' do
      expect(described_class.extract_prefix(nil, 'x')).to be_nil
      expect(described_class.extract_prefix('{a}', nil)).to be_nil
    end
  end
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run:

```bash
cd action-scripts
bundle exec rspec spec/shared/entities/pattern_matcher_spec.rb
```

Expected: 15 examples pass (placeholders + expand), 15 examples fail with `NoMethodError: undefined method 'extract'` and `'extract_prefix'`.

- [ ] **Step 3: Implement extract and extract_prefix using a shared compile helper**

Insert into `action-scripts/shared/entities/pattern_matcher.rb` inside the `PatternMatcher` class, after the `expand` method:

```ruby
    # Returns a Hash mapping placeholder names to captured values, or nil if
    # the path does not match the pattern in full. Captures cannot span "/".
    def self.extract(pattern, path)
      return nil if pattern.nil? || path.nil?
      regex = Regexp.new("\\A#{compile_regex_body(pattern)}\\z")
      match_to_hash(regex.match(path), pattern)
    end

    # Like extract, but only requires the pattern to match the prefix of path.
    # Path may carry additional "/"-separated segments after the pattern.
    def self.extract_prefix(pattern, path)
      return nil if pattern.nil? || path.nil?
      regex = Regexp.new("\\A#{compile_regex_body(pattern)}(?:/.*)?\\z")
      match_to_hash(regex.match(path), pattern)
    end

    # Build a regex body where each {name} becomes a named capture (or
    # backreference for duplicates) and every other character is escaped.
    def self.compile_regex_body(pattern)
      seen = []
      buffer = +''
      rest = pattern.dup

      loop do
        break if rest.empty?

        if (m = rest.match(/\A\{([a-z_][a-z0-9_]*)\}/))
          name = m[1]
          if seen.include?(name)
            buffer << "\\k<#{name}>"
          else
            buffer << "(?<#{name}>[^/]+)"
            seen << name
          end
          rest = rest[m[0].length..]
        else
          buffer << Regexp.escape(rest[0])
          rest = rest[1..]
        end
      end

      buffer
    end
    private_class_method :compile_regex_body

    def self.match_to_hash(match_data, pattern)
      return nil unless match_data
      placeholders(pattern).uniq.each_with_object({}) do |name, hash|
        hash[name] = match_data[name]
      end
    end
    private_class_method :match_to_hash
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd action-scripts
bundle exec rspec spec/shared/entities/pattern_matcher_spec.rb
```

Expected: 30 examples, 0 failures.

- [ ] **Step 5: Run the full suite to confirm nothing else broke**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green. `PatternMatcher` is only used by its own spec at this point.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/shared/entities/pattern_matcher.rb action-scripts/spec/shared/entities/pattern_matcher_spec.rb
git commit -s -m "feat(shared): add PatternMatcher extract and extract_prefix"
```

---

## Task 4: DeploymentTarget — captures keyword and collision detection

**Files:**
- Modify: `action-scripts/shared/entities/deployment_target.rb`
- Test: `action-scripts/spec/shared/entities/deployment_target_spec.rb`

- [ ] **Step 1: Append the failing tests**

Append to `action-scripts/spec/shared/entities/deployment_target_spec.rb` before the final `end`:

```ruby
  describe 'captures' do
    let(:base_args) do
      {
        service: 'api',
        stack: 'terragrunt',
        working_directory: 'payments/api/terragrunt/develop',
        environment: 'develop',
        stack_convention_root: 'payments/api',
        attributes: { 'aws_region' => 'ap-northeast-1' }
      }
    end

    it 'defaults captures to an empty hash when omitted' do
      target = described_class.new(**base_args)
      expect(target.captures).to eq({})
    end

    it 'stores captures and exposes them via #captures' do
      target = described_class.new(**base_args, captures: { 'team' => 'payments' })
      expect(target.captures).to eq('team' => 'payments')
    end

    it 'flattens captures into to_matrix_item with symbol keys' do
      target = described_class.new(**base_args, captures: { 'team' => 'payments' })
      expect(target.to_matrix_item).to include(
        service: 'api',
        environment: 'develop',
        stack: 'terragrunt',
        working_directory: 'payments/api/terragrunt/develop',
        stack_convention_root: 'payments/api',
        aws_region: 'ap-northeast-1',
        team: 'payments'
      )
    end

    it 'raises ArgumentError when a captures key collides with a fixed field' do
      expect {
        described_class.new(**base_args, captures: { 'stack' => 'oops' })
      }.to raise_error(ArgumentError, /reserved/i)
    end

    it 'raises ArgumentError when a captures key collides with an attributes key' do
      expect {
        described_class.new(**base_args, captures: { 'aws_region' => 'us-east-1' })
      }.to raise_error(ArgumentError, /attributes/i)
    end
  end
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run:

```bash
cd action-scripts
bundle exec rspec spec/shared/entities/deployment_target_spec.rb
```

Expected: 5 new examples fail with `NoMethodError: undefined method 'captures'` or unexpected behavior.

- [ ] **Step 3: Modify the entity**

Replace the body of `action-scripts/shared/entities/deployment_target.rb` with:

```ruby
# Deployment target entity representing a specific deployment configuration
# Contains all necessary information for a deployment matrix item

module Entities
  class DeploymentTarget
    FIXED_RESERVED_KEYS = %w[service environment stack working_directory stack_convention_root].freeze

    attr_reader :service, :environment, :stack,
                :working_directory, :stack_convention_root, :attributes, :captures

    def initialize(service:, stack:, working_directory:,
                   environment: nil, stack_convention_root: nil,
                   attributes: {}, captures: {})
      raise ArgumentError, "service is required"           if service.nil?           || service.empty?
      raise ArgumentError, "stack is required"             if stack.nil?             || stack.empty?
      raise ArgumentError, "working_directory is required" if working_directory.nil? || working_directory.empty?

      attr_keys = attributes.keys.map(&:to_s)
      captures.each_key do |raw_key|
        key = raw_key.to_s
        if FIXED_RESERVED_KEYS.include?(key)
          raise ArgumentError, "captures key '#{key}' collides with a reserved DeploymentTarget field"
        end
        if attr_keys.include?(key)
          raise ArgumentError, "captures key '#{key}' collides with an attributes key"
        end
      end

      @service               = service
      @environment           = environment
      @stack                 = stack
      @working_directory     = working_directory
      @stack_convention_root = stack_convention_root
      @attributes            = attributes.freeze
      @captures              = captures.freeze
    end

    def to_matrix_item
      {
        service: service,
        environment: environment,
        stack: stack,
        working_directory: working_directory,
        stack_convention_root: stack_convention_root,
      }.merge(attributes.transform_keys(&:to_sym))
       .merge(captures.transform_keys(&:to_sym))
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

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd action-scripts
bundle exec rspec spec/shared/entities/deployment_target_spec.rb
```

Expected: all examples (existing + 5 new) pass.

- [ ] **Step 5: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/shared/entities/deployment_target.rb action-scripts/spec/shared/entities/deployment_target_spec.rb
git commit -s -m "feat(shared): add captures keyword to DeploymentTarget"
```

---

## Task 5: validate_config — fixed reserved name placeholders

**Files:**
- Modify: `action-scripts/config-manager/use_cases/validate_config.rb`
- Test: `action-scripts/spec/config-manager/use_cases/validate_config_spec.rb`

Skim the existing spec file once to understand the test scaffolding it uses (helpers from `spec_helper.rb` like `create_test_config`, `default_test_config`). New specs follow the same pattern.

- [ ] **Step 1: Add the failing test**

Append a new context inside the top-level `RSpec.describe` of `action-scripts/spec/config-manager/use_cases/validate_config_spec.rb` (place it next to the other validation contexts):

```ruby
  context 'when a stack_conventions placeholder uses a fixed reserved name' do
    let(:bad_config) do
      <<~YAML
        environments:
          - environment: develop
            stacks:
              terragrunt:
                aws_region: ap-northeast-1
                iam_role_plan: arn:aws:iam::1:role/plan
                iam_role_apply: arn:aws:iam::1:role/apply

        stack_conventions:
          - root: "{service}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{stack}"
                required_attributes: [aws_region, iam_role_plan, iam_role_apply]

        services: []
      YAML
    end

    it 'returns a validation error mentioning the reserved name' do
      temp = create_test_config(bad_config)
      begin
        config_client = Infrastructure::ConfigClient.new(workflow_config_path: temp.path)
        result = described_class.new(config_client: config_client).execute
        expect(result.success).to be(false)
        expect(result.validation_errors.join("\n")).to match(/reserved.*stack/i)
      ensure
        temp.unlink
      end
    end
  end
```

If `Infrastructure::ConfigClient.new(workflow_config_path:)` does not match the existing spec's instantiation pattern, use whatever the surrounding specs already use (search the file for `ConfigClient.new` and copy that form). The behaviour under test (the new validation rule) is what matters; reuse the surrounding test plumbing.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd action-scripts
bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb
```

Expected: the new example fails because no validation error is raised.

- [ ] **Step 3: Add the validation rule**

In `action-scripts/config-manager/use_cases/validate_config.rb`, inside `validate_stack_conventions`, after the existing per-stack `each_with_index` loop (around line 173 in the existing file, after the commented-out `{environment}` check), insert a placeholder collision check. Replace the inner per-stack block so it looks like this:

```ruby
          # Validate each stack
          stacks.each_with_index do |stack, index|
            unless stack['name']
              errors << "Stack at index #{index} in convention #{conv_index} missing required 'name' field"
            end

            unless stack['directory']
              errors << "Stack at index #{index} in convention #{conv_index} missing required 'directory' field"
            end

            errors.concat(validate_placeholder_names(convention, stack, conv_index))
          end
```

Then add a private helper inside the same class, near the other private methods:

```ruby
      FIXED_RESERVED_PLACEHOLDERS = %w[stack working_directory stack_convention_root].freeze

      # Check pattern placeholders against the fixed reserved name list.
      def validate_placeholder_names(convention, stack, conv_index)
        errors = []
        root_pattern = convention['root'] || ''
        dir_pattern = stack['directory'] || ''

        placeholders = Entities::PatternMatcher.placeholders(root_pattern) +
                       Entities::PatternMatcher.placeholders(dir_pattern)

        placeholders.uniq.each do |name|
          if FIXED_RESERVED_PLACEHOLDERS.include?(name)
            errors << "Convention #{conv_index} stack '#{stack['name']}' uses reserved placeholder name '{#{name}}'"
          end
        end

        errors
      end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd action-scripts
bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/config-manager/use_cases/validate_config.rb action-scripts/spec/config-manager/use_cases/validate_config_spec.rb
git commit -s -m "feat(config-manager): reject fixed reserved placeholder names"
```

---

## Task 6: validate_config — dynamic reserved name placeholders

**Files:**
- Modify: `action-scripts/config-manager/use_cases/validate_config.rb`
- Test: `action-scripts/spec/config-manager/use_cases/validate_config_spec.rb`

- [ ] **Step 1: Add the failing test**

Append next to the previous context in the spec:

```ruby
  context 'when a stack_conventions placeholder uses an attribute key name' do
    let(:bad_config) do
      <<~YAML
        environments:
          - environment: develop
            stacks:
              terragrunt:
                aws_region: ap-northeast-1
                iam_role_plan: arn:aws:iam::1:role/plan
                iam_role_apply: arn:aws:iam::1:role/apply

        stack_conventions:
          - root: "{service}/{aws_region}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{environment}"
                required_attributes: [aws_region, iam_role_plan, iam_role_apply]

        services: []
      YAML
    end

    it 'returns a validation error mentioning the attribute key collision' do
      temp = create_test_config(bad_config)
      begin
        config_client = Infrastructure::ConfigClient.new(workflow_config_path: temp.path)
        result = described_class.new(config_client: config_client).execute
        expect(result.success).to be(false)
        expect(result.validation_errors.join("\n")).to match(/attribute.*aws_region/i)
      ensure
        temp.unlink
      end
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd action-scripts
bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb
```

Expected: the new example fails.

- [ ] **Step 3: Extend the validation rule**

Edit `action-scripts/config-manager/use_cases/validate_config.rb`. In `validate_stack_conventions`, before the conventions loop, collect the dynamic reserved names from the loaded config and pass them into the helper. Replace the start of `validate_stack_conventions` so it looks like:

```ruby
      def validate_stack_conventions(config)
        errors = []
        conventions = config.stack_conventions

        if conventions.empty?
          errors << "No directory conventions defined"
          return errors
        end

        dynamic_reserved = collect_attribute_keys(config)

        conventions.each_with_index do |convention, conv_index|
```

Update the call inside the per-stack loop to pass the set:

```ruby
            errors.concat(validate_placeholder_names(convention, stack, conv_index, dynamic_reserved))
```

Update `validate_placeholder_names`:

```ruby
      def validate_placeholder_names(convention, stack, conv_index, dynamic_reserved)
        errors = []
        root_pattern = convention['root'] || ''
        dir_pattern = stack['directory'] || ''

        placeholders = Entities::PatternMatcher.placeholders(root_pattern) +
                       Entities::PatternMatcher.placeholders(dir_pattern)

        placeholders.uniq.each do |name|
          if FIXED_RESERVED_PLACEHOLDERS.include?(name)
            errors << "Convention #{conv_index} stack '#{stack['name']}' uses reserved placeholder name '{#{name}}'"
          end
          if dynamic_reserved.include?(name)
            errors << "Convention #{conv_index} stack '#{stack['name']}' placeholder '{#{name}}' collides with environments attribute key"
          end
        end

        errors
      end

      # Collect every key used under environments[].stacks[<stack>] across all
      # environments. These keys end up as top-level keys in matrix output via
      # DeploymentTarget#to_matrix_item.
      def collect_attribute_keys(config)
        keys = []
        config.environments.each_value do |env_config|
          stacks = env_config['stacks']
          next unless stacks.is_a?(Hash)
          stacks.each_value do |attrs|
            next unless attrs.is_a?(Hash)
            keys.concat(attrs.keys.map(&:to_s))
          end
        end
        keys.uniq
      end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd action-scripts
bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/config-manager/use_cases/validate_config.rb action-scripts/spec/config-manager/use_cases/validate_config_spec.rb
git commit -s -m "feat(config-manager): reject placeholder names that collide with attribute keys"
```

---

## Task 7: validate_config — syntax-outside `{...}` literals

**Files:**
- Modify: `action-scripts/config-manager/use_cases/validate_config.rb`
- Test: `action-scripts/spec/config-manager/use_cases/validate_config_spec.rb`

- [ ] **Step 1: Add the failing test**

Append:

```ruby
  context 'when a stack_conventions pattern contains a syntactically invalid placeholder literal' do
    let(:bad_config) do
      <<~YAML
        environments:
          - environment: develop
            stacks:
              terragrunt:
                aws_region: ap-northeast-1
                iam_role_plan: arn:aws:iam::1:role/plan
                iam_role_apply: arn:aws:iam::1:role/apply

        stack_conventions:
          - root: "{service}/{Team}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{environment}"
                required_attributes: [aws_region, iam_role_plan, iam_role_apply]

        services: []
      YAML
    end

    it 'returns a validation error for the invalid literal' do
      temp = create_test_config(bad_config)
      begin
        config_client = Infrastructure::ConfigClient.new(workflow_config_path: temp.path)
        result = described_class.new(config_client: config_client).execute
        expect(result.success).to be(false)
        expect(result.validation_errors.join("\n")).to match(/\{Team\}/)
      ensure
        temp.unlink
      end
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd action-scripts
bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb
```

Expected: the new example fails.

- [ ] **Step 3: Add the validation logic**

Add a constant near the other class-level constants in `validate_config.rb`:

```ruby
      INVALID_PLACEHOLDER_LITERAL = /\{[^{}]*\}/
```

Extend `validate_placeholder_names` to scan for `{...}` literals that the matcher did *not* recognize as placeholders. Append inside the method, after the `placeholders.uniq.each do |name|` block:

```ruby
        all_braced = [root_pattern, dir_pattern].flat_map { |p| p.to_s.scan(INVALID_PLACEHOLDER_LITERAL) }
        valid_braced = placeholders.map { |n| "{#{n}}" }
        invalid = all_braced - valid_braced
        invalid.uniq.each do |literal|
          errors << "Convention #{conv_index} stack '#{stack['name']}' contains invalid placeholder literal '#{literal}'"
        end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd action-scripts
bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/config-manager/use_cases/validate_config.rb action-scripts/spec/config-manager/use_cases/validate_config_spec.rb
git commit -s -m "feat(config-manager): reject invalid {...} literals in convention patterns"
```

---

## Task 8: validate_config — structural equivalence check

**Files:**
- Modify: `action-scripts/config-manager/use_cases/validate_config.rb`
- Test: `action-scripts/spec/config-manager/use_cases/validate_config_spec.rb`

- [ ] **Step 1: Add the failing tests**

Append two contexts:

```ruby
  context 'when two conventions share a stack name and same structural shape but different placeholder names' do
    let(:bad_config) do
      <<~YAML
        environments:
          - environment: develop
            stacks:
              terragrunt:
                aws_region: ap-northeast-1
                iam_role_plan: arn:aws:iam::1:role/plan
                iam_role_apply: arn:aws:iam::1:role/apply

        stack_conventions:
          - root: "{team}/{service}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{environment}"
                required_attributes: [aws_region, iam_role_plan, iam_role_apply]
          - root: "{team99}/{service}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{environment}"
                required_attributes: [aws_region, iam_role_plan, iam_role_apply]

        services: []
      YAML
    end

    it 'returns a validation error mentioning the conflicting placeholder names' do
      temp = create_test_config(bad_config)
      begin
        config_client = Infrastructure::ConfigClient.new(workflow_config_path: temp.path)
        result = described_class.new(config_client: config_client).execute
        expect(result.success).to be(false)
        joined = result.validation_errors.join("\n")
        expect(joined).to match(/team/)
        expect(joined).to match(/team99/)
      ensure
        temp.unlink
      end
    end
  end

  context 'when two conventions share a stack name and identical placeholder names at the same positions' do
    let(:good_config) do
      <<~YAML
        environments:
          - environment: develop
            stacks:
              terragrunt:
                aws_region: ap-northeast-1
                iam_role_plan: arn:aws:iam::1:role/plan
                iam_role_apply: arn:aws:iam::1:role/apply

        stack_conventions:
          - root: "{team}/{service}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{environment}"
                required_attributes: [aws_region, iam_role_plan, iam_role_apply]
          - root: "{team}/{service}"
            stacks:
              - name: kubernetes
                directory: "kubernetes/overlays/{environment}"

        services: []
      YAML
    end

    it 'passes validation (different stack names are not compared)' do
      temp = create_test_config(good_config)
      begin
        config_client = Infrastructure::ConfigClient.new(workflow_config_path: temp.path)
        result = described_class.new(config_client: config_client).execute
        expect(result.success).to be(true)
      ensure
        temp.unlink
      end
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cd action-scripts
bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb
```

Expected: the negative example fails (no error currently); the positive example may already pass. Make sure both end up green by the end of this task.

- [ ] **Step 3: Add the validation logic**

In `validate_stack_conventions`, after the per-convention loop, add a structural cross-check before returning `errors`:

```ruby
        errors.concat(validate_structural_equivalence(conventions))
```

Add the helper near the other private methods:

```ruby
      # Detect conventions that share a stack name and have the same
      # placeholder *positions* but use different placeholder *names*. If
      # consumers point both at the same on-disk path, captures keys become
      # YAML-order dependent.
      def validate_structural_equivalence(conventions)
        errors = []

        full_patterns = []
        conventions.each_with_index do |convention, conv_index|
          (convention['stacks'] || []).each_with_index do |stack, stack_index|
            name = stack['name']
            next if name.nil?
            root = convention['root'] || ''
            dir = stack['directory'] || ''
            joined = root.empty? ? dir : "#{root}/#{dir}"
            full_patterns << {
              stack: name,
              pattern: joined,
              conv_index: conv_index,
              stack_index: stack_index
            }
          end
        end

        full_patterns.group_by { |p| p[:stack] }.each_value do |group|
          next if group.length < 2

          by_signature = group.group_by { |p| structural_signature(p[:pattern]) }
          by_signature.each_value do |patterns|
            next if patterns.length < 2

            base = patterns.first
            base_names = Entities::PatternMatcher.placeholders(base[:pattern])
            patterns.drop(1).each do |other|
              other_names = Entities::PatternMatcher.placeholders(other[:pattern])
              next if other_names == base_names

              errors << "Conventions #{base[:conv_index]} and #{other[:conv_index]} stack '#{base[:stack]}' share a placeholder structure but use different names: #{base_names.inspect} vs #{other_names.inspect}"
            end
          end
        end

        errors
      end

      # Return a structural signature for a pattern by replacing each
      # placeholder with a positional marker {X0}, {X1}, ... in occurrence
      # order. Two patterns share a signature iff they have the same literal
      # text and the same placeholder positions, regardless of placeholder
      # names.
      def structural_signature(pattern)
        index = 0
        pattern.gsub(Entities::PatternMatcher::PLACEHOLDER_REGEX) do
          token = "{X#{index}}"
          index += 1
          token
        end
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
cd action-scripts
bundle exec rspec spec/config-manager/use_cases/validate_config_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/config-manager/use_cases/validate_config.rb action-scripts/spec/config-manager/use_cases/validate_config_spec.rb
git commit -s -m "feat(config-manager): reject structurally equivalent conventions with diverging placeholder names"
```

---

## Task 9: detect_changed_services — route through PatternMatcher

**Files:**
- Modify: `action-scripts/label-dispatcher/use_cases/detect_changed_services.rb`
- Test: `action-scripts/spec/label-dispatcher/use_cases/detect_changed_services_spec.rb`

- [ ] **Step 1: Add the failing test**

Look in the existing spec for a context that exercises `discover_services_from_pattern` (search for `discover_services` or `detect_changes`). Append a new context that uses a pattern with an arbitrary placeholder name:

```ruby
  context 'when a directory pattern contains an arbitrary placeholder beyond {service} and {environment}' do
    let(:config_yaml) do
      <<~YAML
        environments:
          - environment: develop
            stacks:
              terragrunt:
                aws_region: ap-northeast-1
                iam_role_plan: arn:aws:iam::1:role/plan
                iam_role_apply: arn:aws:iam::1:role/apply

        stack_conventions:
          - root: "{team}/{service}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{environment}"
                required_attributes: [aws_region, iam_role_plan, iam_role_apply]

        services: []
      YAML
    end

    let(:changed_files) { ['payments/api/terragrunt/develop/main.tf'] }

    it 'still detects the service from the changed file path' do
      temp = create_test_config(config_yaml)
      begin
        config_client = Infrastructure::ConfigClient.new(workflow_config_path: temp.path)
        file_client = instance_double('FileClient', get_changed_files: changed_files)
        result = described_class.new(file_client: file_client, config_client: config_client).execute
        expect(result.success).to be(true)
        expect(result.services_detected).to include('api')
      ensure
        temp.unlink
      end
    end
  end
```

If the existing spec uses a different test-double approach for `file_client` or instantiates `ConfigClient` differently, mirror its style. The behaviour assertion (`services_detected` includes `'api'`) is the part that must remain.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd action-scripts
bundle exec rspec spec/label-dispatcher/use_cases/detect_changed_services_spec.rb
```

Expected: the new example fails because `{team}` is not stripped and the regex misses the file.

- [ ] **Step 3: Replace discover_services_from_pattern**

Edit `action-scripts/label-dispatcher/use_cases/detect_changed_services.rb`. Replace the `discover_services_from_pattern` method (currently at the bottom of the file, lines around 96-113) with:

```ruby
      # Discover services by matching changed files against a directory
      # pattern. Uses PatternMatcher so arbitrary placeholders ({team}, {region},
      # etc.) match correctly even though only {service} feeds downstream.
      def discover_services_from_pattern(changed_files, pattern)
        services = Set.new
        changed_files.each do |file|
          captures = Entities::PatternMatcher.extract_prefix(pattern, file)
          next unless captures

          service_name = captures['service']
          next if service_name.nil? || service_name.start_with?('.')

          services << service_name
        end
        services
      end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd action-scripts
bundle exec rspec spec/label-dispatcher/use_cases/detect_changed_services_spec.rb
```

Expected: all examples pass — both new and existing.

- [ ] **Step 5: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/label-dispatcher/use_cases/detect_changed_services.rb action-scripts/spec/label-dispatcher/use_cases/detect_changed_services_spec.rb
git commit -s -m "feat(label-dispatcher): route service detection through PatternMatcher"
```

---

## Task 10: generated_matrix — route expansion through PatternMatcher and raise on unresolved

**Files:**
- Modify: `action-scripts/label-resolver/use_cases/generated_matrix.rb`
- Test: `action-scripts/spec/label-resolver/use_cases/generated_matrix_spec.rb`

This task swaps the existing hand-rolled gsub logic in `expand_directory_pattern` for `PatternMatcher.expand` and converts the two `puts "Warning..."` paths into exceptions. Captures wiring (the new behaviour) is added in Task 11.

- [ ] **Step 1: Add the failing test**

Append to `action-scripts/spec/label-resolver/use_cases/generated_matrix_spec.rb`:

```ruby
  context 'when {environment} appears but target_environment is nil at expansion time' do
    it 'raises UnresolvedPlaceholderError (no silent warning)' do
      use_case = described_class.allocate
      expect {
        use_case.send(:expand_directory_pattern, 'foo/{environment}/main', 'svc', nil)
      }.to raise_error(Entities::UnresolvedPlaceholderError)
    end
  end
```

If the spec file does not already reach into private methods this way (search for `send(:`), prefer a higher-level spec that triggers `generate_targets_for_service` with a config that has `{environment}` and an environment-agnostic call site. Otherwise, the private-method test above is acceptable for verifying the swap.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/use_cases/generated_matrix_spec.rb
```

Expected: the new example fails because the code currently `puts` a warning and returns `nil`.

- [ ] **Step 3: Replace expand_directory_pattern**

In `action-scripts/label-resolver/use_cases/generated_matrix.rb`, replace `expand_directory_pattern` (currently around lines 282-305) with:

```ruby
      # Expand directory pattern with placeholders. Delegates to PatternMatcher
      # so all placeholder rules live in one place. Builds the values map
      # conditionally because {environment} is optional for env-agnostic stacks.
      def expand_directory_pattern(pattern, service_name, target_environment)
        return nil unless pattern

        values = { 'service' => service_name }
        if pattern.include?('{environment}')
          if target_environment.nil?
            raise Entities::UnresolvedPlaceholderError,
                  "{environment} appears in pattern '#{pattern}' but target_environment is nil"
          end
          values['environment'] = target_environment
        end

        Entities::PatternMatcher.expand(pattern, values)
      end
```

The existing `find_matching_conventions` and `extract_root_from_working_dir` methods still use inline `gsub`. Replace those `gsub` calls with `PatternMatcher.expand` too. Specifically:

In `find_matching_conventions` (around line 122), replace the body of the inner `stacks.any?` block:

```ruby
            stacks.any? do |stack_config|
              @target_environments.any? do |env|
                root_pattern = convention['root']
                stack_directory = stack_config['directory']

                full_pattern = if root_pattern.nil? || root_pattern.empty?
                                stack_directory
                              else
                                "#{root_pattern}/#{stack_directory}"
                              end

                values = { 'service' => service_name }
                values['environment'] = env if full_pattern.include?('{environment}')

                begin
                  expanded_pattern = Entities::PatternMatcher.expand(full_pattern, values)
                rescue Entities::UnresolvedPlaceholderError
                  next false
                end

                File.directory?(File.join(repo_root, expanded_pattern))
              end
            end
```

In `extract_root_from_working_dir` (around line 308), replace the inner expansion logic similarly:

```ruby
          stacks.each do |stack_config|
            full_pattern = if root_pattern.nil? || root_pattern.empty?
                            stack_config['directory']
                          else
                            "#{root_pattern}/#{stack_config['directory']}"
                          end

            values = { 'service' => service_name }
            values['environment'] = target_environment if full_pattern.include?('{environment}') && target_environment

            begin
              expanded_pattern = Entities::PatternMatcher.expand(full_pattern, values)
            rescue Entities::UnresolvedPlaceholderError
              next
            end

            if working_dir == expanded_pattern
              values_for_root = { 'service' => service_name }
              values_for_root['environment'] = target_environment if (root_pattern || '').include?('{environment}') && target_environment

              begin
                return Entities::PatternMatcher.expand(root_pattern || '', values_for_root)
              rescue Entities::UnresolvedPlaceholderError
                next
              end
            end
          end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/use_cases/generated_matrix_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/label-resolver/use_cases/generated_matrix.rb action-scripts/spec/label-resolver/use_cases/generated_matrix_spec.rb
git commit -s -m "feat(label-resolver): route pattern expansion through PatternMatcher and raise on unresolved placeholders"
```

---

## Task 11: generated_matrix — extract captures and flatten into matrix items

**Files:**
- Modify: `action-scripts/label-resolver/use_cases/generated_matrix.rb`
- Test: `action-scripts/spec/label-resolver/use_cases/generated_matrix_spec.rb`

- [ ] **Step 1: Add the failing test**

Append:

```ruby
  context 'when stack_conventions root contains an arbitrary placeholder' do
    let(:config_yaml) do
      <<~YAML
        environments:
          - environment: develop
            stacks:
              terragrunt:
                aws_region: ap-northeast-1
                iam_role_plan: arn:aws:iam::1:role/plan
                iam_role_apply: arn:aws:iam::1:role/apply

        stack_conventions:
          - root: "{team}/{service}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{environment}"
                required_attributes: [aws_region, iam_role_plan, iam_role_apply]

        services: []
      YAML
    end

    it 'flattens the captured value into matrix items' do
      temp = create_test_config(config_yaml)
      allow(File).to receive(:directory?).and_call_original
      allow(File).to receive(:directory?).with(%r{payments/api/terragrunt/develop}).and_return(true)
      begin
        config_client = Infrastructure::ConfigClient.new(workflow_config_path: temp.path)
        labels = [Entities::DeployLabel.from_service(service: 'api')]
        result = described_class.new(config_client: config_client).execute(
          deploy_labels: labels,
          target_environments: ['develop']
        )
        expect(result.success).to be(true)
        targets = result.deployment_targets
        expect(targets).not_to be_empty
        item = targets.first.to_matrix_item
        expect(item).to include(service: 'api', team: 'payments')
      ensure
        temp.unlink
      end
    end
  end
```

If the existing spec uses different stubbing for `File.directory?` or instantiates the resolver differently, mirror its style. The behaviour assertion (`item` includes `team: 'payments'`) is what matters.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/use_cases/generated_matrix_spec.rb
```

Expected: the new example fails because matrix items have no `team` key.

- [ ] **Step 3: Capture placeholders in generate_deployment_target**

In `action-scripts/label-resolver/use_cases/generated_matrix.rb`, modify `generate_deployment_target` (around line 242). Track which `dir_pattern` matched and which full pattern (root joined with dir_pattern) corresponds to it, then extract captures from `working_dir` using that full pattern:

```ruby
      # Generate a deployment target from deploy label, environment, and stack
      def generate_deployment_target(deploy_label, target_environment, stack, config)
        dir_patterns = config.stack_conventions_for(deploy_label.service, stack)
        return nil if dir_patterns.empty?

        working_dir = nil
        matched_dir_pattern = nil
        repo_root = find_repository_root

        dir_patterns.each do |dir_pattern|
          candidate_dir = expand_directory_pattern(dir_pattern, deploy_label.service, target_environment)
          next unless candidate_dir

          full_path = File.join(repo_root, candidate_dir)
          if File.directory?(full_path)
            working_dir = candidate_dir
            matched_dir_pattern = dir_pattern
            break
          end
        end

        return nil unless working_dir

        full_match_pattern = full_pattern_for(deploy_label.service, matched_dir_pattern, config)
        captures = extract_captures(full_match_pattern, working_dir, deploy_label.service, target_environment, config)

        create_deployment_target(deploy_label, target_environment, stack, working_dir, config, captures)
      end
```

Add helpers near the other private methods:

```ruby
      # Find the full (root + "/" + directory) pattern that produced this
      # matched dir_pattern. Returns nil if it cannot be resolved.
      def full_pattern_for(service_name, dir_pattern, config)
        config.stack_conventions_config.each do |convention|
          (convention['stacks'] || []).each do |stack_config|
            next unless stack_config['directory'] == dir_pattern

            root_pattern = convention['root']
            return root_pattern.nil? || root_pattern.empty? ? dir_pattern : "#{root_pattern}/#{dir_pattern}"
          end
        end

        # Service-specific stack_conventions fallback (services[].stack_conventions)
        service_config = config.services[service_name]
        if service_config && service_config['stack_conventions']
          service_config['stack_conventions'].each_value do |pattern|
            return pattern if pattern == dir_pattern
          end
        end

        dir_pattern
      end

      # Build the captures map for one target. Drops the {service} and
      # {environment} keys because those map to dedicated DeploymentTarget
      # fields. Raises if the working_dir doesn't match the pattern (invariant
      # violation, never expected at runtime).
      def extract_captures(full_match_pattern, working_dir, service_name, target_environment, config)
        return {} unless full_match_pattern

        raw = Entities::PatternMatcher.extract(full_match_pattern, working_dir)
        if raw.nil?
          raise "PatternMatcher.extract returned nil for pattern '#{full_match_pattern}' and working_dir '#{working_dir}'"
        end

        raw.reject { |k, _| k == 'service' || k == 'environment' }
      end
```

Update `create_deployment_target` to accept and forward the captures:

```ruby
      # Create deployment target (unified across stacks)
      def create_deployment_target(deploy_label, target_environment, stack, working_dir, config, captures = {})
        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: stack,
          working_directory: working_dir,
          stack_convention_root: extract_root_from_working_dir(working_dir, deploy_label.service, target_environment, config),
          attributes: target_environment ? config.stack_attributes_for(target_environment, stack) : {},
          captures: captures
        )
      end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/use_cases/generated_matrix_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add action-scripts/label-resolver/use_cases/generated_matrix.rb action-scripts/spec/label-resolver/use_cases/generated_matrix_spec.rb
git commit -s -m "feat(label-resolver): flatten extracted captures into matrix items"
```

---

## Task 12: generated_matrix — remove residual puts warnings

**Files:**
- Modify: `action-scripts/label-resolver/use_cases/generated_matrix.rb`

The remaining `puts "Warning: Environment configuration not found for: #{env}"` (around line 95) and `puts "Warning: Unresolved placeholders in pattern: ..."` (already removed in Task 10 via PatternMatcher.expand) are the last warning-style early-returns. Audit and address.

- [ ] **Step 1: Grep for any remaining warning paths**

Run:

```bash
cd action-scripts
grep -n 'puts "Warning' label-resolver/use_cases/generated_matrix.rb
```

Expected: any lines that still call `puts "Warning..."` are listed.

- [ ] **Step 2: Decide per occurrence**

For each remaining `puts "Warning..."`:

- If the surrounding code does `puts ...; next` or `puts ...; return nil` and the situation should never occur for a valid config: replace with `raise "<descriptive message>"`.
- If the situation is recoverable (e.g. an environment listed but not configured, where the user's intent is "skip"): keep the early return, but replace `puts "Warning..."` with a comment explaining the silent skip. Per the project rule against silent failures, add a `// FALLBACK:` style comment marker (`# FALLBACK:` in Ruby).

For `generated_matrix.rb` line 95 specifically (the env-config-not-found path inside the per-environment loop), the configuration loader already validates environment presence at top-of-execute (`generated_matrix.rb` lines 17-24), so this branch is unreachable for valid configs. Replace it with a `raise`:

```ruby
            env_config = config.environment_config(env)
            unless env_config
              raise "environment configuration not found for: #{env} (should have been caught by validate_config)"
            end
```

- [ ] **Step 3: Run the full suite**

Run:

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green. The earlier env-validation path keeps this branch unreachable in normal flows, so existing specs do not exercise it.

- [ ] **Step 4: Commit**

```bash
git add action-scripts/label-resolver/use_cases/generated_matrix.rb
git commit -s -m "fix(label-resolver): replace residual puts Warning with raises"
```

---

## Task 13: README — Matrix Output section and configuration example update

**Files:**
- Modify: `README.md`
- Modify: `README-ja.md`

- [ ] **Step 1: Update README.md**

Edit `README.md`. After the closing of the `## Workflow integration` section (i.e. immediately before `## License`, after the `panicboat-actions` paragraph), insert a new `## Matrix Output` section:

```markdown
## Matrix Output

`label-resolver` produces a JSON array on `outputs.targets` (and the `DEPLOYMENT_TARGETS` env var). Each matrix item is flat:

| Key | Source | Notes |
|---|---|---|
| `service` | Fixed | `deploy:<service>` label |
| `environment` | Fixed | `null` for environment-agnostic stacks |
| `stack` | Fixed | e.g. `terragrunt`, `kubernetes` |
| `working_directory` | Fixed | Resolved deploy directory |
| `stack_convention_root` | Fixed | `root` portion of the matched pattern, expanded |
| (attributes keys) | Dynamic | Everything under `environments[].stacks[stack].*` |
| (captures keys) | Dynamic | Values of arbitrary `{placeholder}` segments in the matched pattern, excluding `service` / `environment` |

Example item for a convention `root: "{team}/{service}"` matching `payments/api/terragrunt/develop`:

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "terragrunt",
  "working_directory": "payments/api/terragrunt/develop",
  "stack_convention_root": "payments/api",
  "aws_region": "ap-northeast-1",
  "iam_role_plan": "arn:aws:iam::ACCOUNT:role/plan-role",
  "iam_role_apply": "arn:aws:iam::ACCOUNT:role/apply-role",
  "team": "payments"
}
```

Downstream composite actions can reference any key directly, e.g. `${{ matrix.team }}`. Placeholder names that would collide with a fixed key or with any attribute key are rejected at `config-manager validate` time.
```

Also update the `## Configuration` section's `stack_conventions` sample to mention arbitrary placeholders. Edit the existing yaml block to add a comment line:

```yaml
stack_conventions:
  - root: "{service}"          # placeholders other than {service}/{environment}
                               # are also allowed; their values are emitted as
                               # top-level keys in matrix output (e.g. {team}).
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        required_attributes: [aws_region, iam_role_plan, iam_role_apply]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
```

- [ ] **Step 2: Mirror in README-ja.md**

Edit `README-ja.md`. Insert the same structural changes with Japanese prose (headings stay English per the project rule):

After `panicboat-actions` paragraph and before `## License`, add `## Matrix Output`:

```markdown
## Matrix Output

`label-resolver` は `outputs.targets`（および環境変数 `DEPLOYMENT_TARGETS`）として JSON 配列を出力します。各 matrix item はフラット構造です。

| Key | 由来 | 補足 |
|---|---|---|
| `service` | 固定 | `deploy:<service>` ラベルの service 名 |
| `environment` | 固定 | environment-agnostic stack では `null` |
| `stack` | 固定 | 例: `terragrunt`, `kubernetes` |
| `working_directory` | 固定 | 実在する deploy 対象ディレクトリ |
| `stack_convention_root` | 固定 | マッチした root pattern の展開後の値 |
| (attributes のキー) | 動的 | `environments[].stacks[stack].*` で定義された値 |
| (captures のキー) | 動的 | マッチした pattern 中の任意 `{placeholder}` の抽出値（`service` / `environment` を除く） |

`root: "{team}/{service}"` の convention が `payments/api/terragrunt/develop` にマッチした場合の item 例:

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "terragrunt",
  "working_directory": "payments/api/terragrunt/develop",
  "stack_convention_root": "payments/api",
  "aws_region": "ap-northeast-1",
  "iam_role_plan": "arn:aws:iam::ACCOUNT:role/plan-role",
  "iam_role_apply": "arn:aws:iam::ACCOUNT:role/apply-role",
  "team": "payments"
}
```

下流の Composite Action では `${{ matrix.team }}` のように任意のキーを直接参照できます。固定キーや attributes キーと衝突する placeholder 名は `config-manager validate` の段階で拒否されます。
```

Then update the `## 設定` section's yaml example with a comment line in Japanese:

```yaml
stack_conventions:
  - root: "{service}"          # {service}/{environment} 以外の任意 placeholder
                               # も使用可能。抽出された値は matrix item の
                               # トップレベル（例: {team}）に展開される。
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        required_attributes: [aws_region, iam_role_plan, iam_role_apply]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
```

- [ ] **Step 3: Commit**

```bash
git add README.md README-ja.md
git commit -s -m "docs(readme): document matrix output schema and arbitrary placeholders"
```

---

## Task 14: config-manager/README — Placeholder rules section

**Files:**
- Modify: `action-scripts/config-manager/README.md`

- [ ] **Step 1: Read the existing README**

Run:

```bash
cd action-scripts/config-manager
cat README.md | head -200
```

Locate the "Directory Validation" section.

- [ ] **Step 2: Insert a new Placeholder Rules section after Directory Validation**

Insert the following block immediately after the existing "Directory Validation" section:

```markdown
## Placeholder Rules

Patterns in `stack_conventions[].root` and `stack_conventions[].stacks[].directory` accept `{name}` placeholders. The grammar:

- `name` must match `[a-z_][a-z0-9_]*` (lowercase letter or underscore followed by lowercase letters, digits, or underscores).
- Strings like `{Team}`, `{my-var}`, or `{a b}` are not recognized as placeholders; the entire literal is rejected by `validate`.
- The same placeholder name may appear multiple times in one pattern. Expansion uses the same value at every occurrence; extraction requires the same value at every occurrence.

### Built-in placeholders

- `{service}` is required in `root` (unless `root` is the empty string).
- `{environment}` is optional in `stacks[].directory` — omitting it makes the stack environment-agnostic.

### Custom placeholders

Any additional placeholder name acts as a capture. After resolving a deploy target, its value is emitted as a top-level key on the matrix item (see `README.md` `## Matrix Output`). Custom placeholder names are rejected at validate time if they would collide with:

- A reserved DeploymentTarget field: `stack`, `working_directory`, `stack_convention_root`.
- Any attribute key used under `environments[].stacks[].*` (e.g. `aws_region`).

### Structural equivalence

If two conventions share a stack name and have placeholders at the same positions but with different names (e.g. `{team}/{service}` and `{team99}/{service}` both for stack `terragrunt`), `validate` rejects the configuration: the captured key name would otherwise depend on YAML order.

### Implementation

Placeholder parsing, expansion, and extraction are centralized in `Entities::PatternMatcher` (`shared/entities/pattern_matcher.rb`). All three components (`config-manager`, `label-dispatcher`, `label-resolver`) call into it, so the grammar above is authoritative.
```

- [ ] **Step 3: Commit**

```bash
git add action-scripts/config-manager/README.md
git commit -s -m "docs(config-manager): add Placeholder Rules section"
```

---

## Final Verification

After Task 14:

- [ ] **Run the full RSpec suite once more**

```bash
cd action-scripts
bundle exec rspec
```

Expected: all green, no warnings about uninitialized constants or missing methods.

- [ ] **Inspect the branch state**

```bash
git log --oneline origin/main..HEAD
git status
```

Expected: clean working tree; commit log shows the design doc commits followed by the per-task implementation commits.

- [ ] **Optional: open a draft PR**

Per CLAUDE.md, PRs are always opened as drafts. When ready:

```bash
git push -u origin HEAD
gh pr create --draft --title "Uniform placeholder handling via PatternMatcher" --body "$(cat <<'EOF'
## Summary
- Add Entities::PatternMatcher to centralize placeholder grammar (regex, expand, extract).
- Flatten arbitrary placeholder values into DeploymentTarget matrix output.
- Reject reserved-name collisions and structurally ambiguous conventions at validate time.
- Replace puts-based warnings with exceptions; document matrix output schema in README files.

See docs/superpowers/specs/2026-05-19-pattern-matcher-uniform-placeholders-design.md for the full design.

## Test plan
- [ ] bundle exec rspec passes in action-scripts/
- [ ] Manual workflow-config.yaml with a {team}/{service} root produces matrix items with a top-level "team" key
- [ ] Manual workflow-config.yaml with {stack} or {aws_region} placeholder fails validate with a clear error
EOF
)"
```
