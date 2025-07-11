# Use case for detecting changed services from file modifications
# Analyzes git diff output to determine which services need deployment

module UseCases
  module LabelManagement
    class DetectChangedServices
      def initialize(file_client:, config_client:)
        @file_client = file_client
        @config_client = config_client
      end

      # Execute service detection based on changed files
      def execute(base_ref: nil, head_ref: nil)
        config = @config_client.load_workflow_config
        changed_files = @file_client.get_changed_files(base_ref: base_ref, head_ref: head_ref)

        # Discover all services from file changes using pattern matching
        all_discovered_services = discover_services_from_patterns(changed_files, config)

        # Filter out excluded services
        filtered_services = filter_excluded_services(all_discovered_services, config, changed_files)
        excluded_services = all_discovered_services - filtered_services

        # Generate deploy labels for non-excluded services
        deploy_labels = filtered_services.map { |service| Entities::DeployLabel.from_service(service: service) }

        # Log excluded services if any
        log_excluded_services(excluded_services, config) if excluded_services.any?

        Entities::Result.success(
          deploy_labels: deploy_labels,
          changed_files: changed_files,
          services_detected: filtered_services,
          excluded_services: excluded_services,
          total_services_discovered: all_discovered_services.length
        )
      rescue => error
        Entities::Result.failure(error_message: error.message)
      end

      private

      # Filter out services that are excluded from automation
      def filter_excluded_services(discovered_services, config, changed_files)
        discovered_services.reject do |service|
          excluded_from_automation?(service, config, changed_files)
        end
      end

      # Check if a service is excluded from automation
      def excluded_from_automation?(service, config, changed_files)
        # Check if service is in excluded_services list
        return true if config.excluded_services.include?(service)

        # Check if service config has exclude_from_automation flag
        service_config = config.services[service]
        return false unless service_config

        return true if service_config['exclude_from_automation'] == true

        false
      end

      # Log excluded services for visibility
      def log_excluded_services(excluded_services, config)
        return if excluded_services.empty?

        puts "⚠️  Services excluded from automation (#{excluded_services.length}):"
        excluded_services.each do |service|
          service_config = config.services[service]
          exclusion_config = service_config&.[]('exclusion_config') || {}
          reason = exclusion_config['reason'] || 'No reason specified'
          type = exclusion_config['type'] || 'unspecified'

          puts "  - #{service} (#{type}): #{reason}"
        end
      end

      # Discover services from changed files and configuration
      def discover_services_from_patterns(changed_files, config)
        services = Set.new

        # Get all possible directory patterns from configuration
        patterns = config.all_directory_patterns
        
        patterns.each do |pattern|
          pattern_services = discover_services_from_pattern(changed_files, pattern)
          services.merge(pattern_services)
        end

        services.to_a.reject { |service| service.start_with?('.') }
      end

      private

      # Discover services by matching changed files against directory pattern
      def discover_services_from_pattern(changed_files, pattern)
        # Convert pattern like "{service}/terragrunt" to regex
        regex_pattern = pattern.gsub('{service}', '([^/]+)')
        # Also handle {environment} placeholders in pattern
        regex_pattern = regex_pattern.gsub('{environment}', '[^/]+')

        services = Set.new
        changed_files.each do |file|
          # Try to match the pattern against the file path
          # The pattern might not include all parts of the file path
          if match = file.match(/#{regex_pattern}/)
            service_name = match[1]
            services << service_name unless service_name.start_with?('.')
          end
        end

        services
      end

    end
  end
end
