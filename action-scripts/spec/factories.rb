# Factory definitions for testing

FactoryBot.define do
  factory :deploy_label, class: 'Entities::DeployLabel' do
    initialize_with { new(label_string) }
    
    trait :valid_service do
      label_string { "deploy:test-service" }
    end
    
    trait :valid_all do
      label_string { "deploy:all" }
    end
    
    trait :invalid do
      label_string { "invalid-label" }
    end
  end

  factory :deployment_target, class: 'Entities::DeploymentTarget' do
    service { "test-service" }
    environment { "develop" }
    stack { "terragrunt" }
    working_directory { "test-service/terragrunt/develop" }
    aws_region { "ap-northeast-1" }
    iam_role_plan { "arn:aws:iam::123456789012:role/plan-role" }
    iam_role_apply { "arn:aws:iam::123456789012:role/apply-role" }
    directory_conventions_root { "test-service" }
    
    initialize_with do
      new(
        service: service,
        environment: environment,
        stack: stack,
        working_directory: working_directory,
        aws_region: aws_region,
        iam_role_plan: iam_role_plan,
        iam_role_apply: iam_role_apply,
        directory_conventions_root: directory_conventions_root
      )
    end
    
    trait :kubernetes do
      stack { "kubernetes" }
    end
    
    trait :staging do
      environment { "staging" }
    end
  end

  factory :workflow_config, class: 'Entities::WorkflowConfig' do
    config_hash do
      {
        'environments' => [
          {
            'environment' => 'develop',
            'branch' => 'develop',
            'aws_region' => 'ap-northeast-1',
            'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
            'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
          },
          {
            'environment' => 'staging',
            'branch' => 'staging',
            'aws_region' => 'ap-northeast-1',
            'iam_role_plan' => 'arn:aws:iam::123456789012:role/staging-plan-role',
            'iam_role_apply' => 'arn:aws:iam::123456789012:role/staging-apply-role'
          },
          {
            'environment' => 'production',
            'branch' => 'production',
            'aws_region' => 'ap-northeast-1',
            'iam_role_plan' => 'arn:aws:iam::123456789012:role/production-plan-role',
            'iam_role_apply' => 'arn:aws:iam::123456789012:role/production-apply-role'
          }
        ],
        'directory_conventions' => [
          {
            'root' => '{service}',
            'stacks' => [
              {
                'name' => 'terragrunt',
                'directory' => 'terragrunt/{environment}'
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

  factory :result_success, class: 'Entities::Result' do
    data { { test: 'data' } }
    
    initialize_with { Entities::Result.success(**data) }
  end

  factory :result_failure, class: 'Entities::Result' do
    error_message { "Test error message" }
    
    initialize_with { Entities::Result.failure(error_message: error_message) }
  end
end