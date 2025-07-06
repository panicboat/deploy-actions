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

        # Discover all services from file changes
        all_discovered_services = discover_services(changed_files, config)

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
      def discover_services(changed_files, config)
        services = Set.new
        explicitly_configured_services = Set.new

        # Check explicitly configured services first
        config.services.each do |service_name, service_config|
          if service_has_changed_files?(changed_files, service_name, service_config, config)
            services << service_name
            explicitly_configured_services << service_name
          end
        end

        # Discover services from directory patterns (excluding already configured ones)
        config.directory_conventions.each do |stack_type, pattern|
          next unless pattern && pattern.include?('{service}')
          
          pattern_services = discover_services_from_pattern(changed_files, pattern)
          pattern_services.each do |service|
            unless explicitly_configured_services.include?(service)
              services << service
            end
          end
        end

        # Discover services from existing directory structure (excluding configured service files)
        filesystem_services = discover_services_from_filesystem_filtered(changed_files, explicitly_configured_services)
        services.merge(filesystem_services)

        services.to_a.reject { |service| service.start_with?('.') }
      end

      # Check if a service has changed files
      def service_has_changed_files?(changed_files, service_name, service_config, config)
        # Check simple pattern: {service}/
        return true if changed_files.any? { |file| file.start_with?("#{service_name}/") }

        # Check service-specific or default directory conventions
        conventions = service_config&.dig('directory_conventions') || config.directory_conventions

        conventions.each do |stack, pattern|
          next unless pattern.include?('{service}')

          # Extract the base path up to {service} and check if any files match that prefix
          parts = pattern.split('{service}')
          prefix = parts[0]  # Everything before {service}
          suffix = parts[1]  # Everything after {service}
          
          # Build service-specific prefix
          service_prefix = "#{prefix}#{service_name}"
          
          # Check if any changed files match this service prefix
          return true if changed_files.any? { |file| 
            file.start_with?(service_prefix) && 
            (suffix.nil? || suffix.empty? || file_matches_suffix?(file, service_prefix, suffix))
          }
        end

        false
      end

      private

      # Check if file matches the suffix pattern (ignoring {environment} placeholders)
      def file_matches_suffix?(file, service_prefix, suffix)
        return true if suffix.nil? || suffix.empty?
        
        remaining_path = file[service_prefix.length..-1]
        # Remove {environment} placeholders from suffix for matching
        simplified_suffix = suffix.gsub(/\{environment\}/, '*')
        
        # Simple wildcard matching - if suffix contains placeholders, accept any path
        simplified_suffix.include?('*') || remaining_path.start_with?(simplified_suffix)
      end

      # Discover services by matching changed files against directory pattern
      def discover_services_from_pattern(changed_files, pattern)
        # Convert pattern like "{service}/terragrunt" to regex
        regex_pattern = pattern.gsub('{service}', '([^/]+)')

        services = Set.new
        changed_files.each do |file|
          if match = file.match(/\A#{regex_pattern}/)
            service_name = match[1]
            services << service_name unless service_name.start_with?('.')
          end
        end

        services
      end

      # Discover services from existing filesystem structure, excluding configured service files
      def discover_services_from_filesystem_filtered(changed_files, explicitly_configured_services)
        services = Set.new

        # Filter out files that belong to explicitly configured services
        filtered_files = filter_out_configured_service_files(changed_files, explicitly_configured_services)

        filtered_files.each do |file|
          # Extract service name from file path (first directory component)
          path_parts = file.split('/')
          next if path_parts.empty?

          potential_service = path_parts.first
          next if potential_service.start_with?('.')

          # Check if this looks like a service directory
          if looks_like_service_directory?(potential_service)
            services << potential_service
          end
        end

        services
      end

      # Filter out files that belong to explicitly configured services
      def filter_out_configured_service_files(changed_files, explicitly_configured_services)
        return changed_files if explicitly_configured_services.empty?

        filtered_files = []

        changed_files.each do |file|
          # Check if file belongs to any configured service
          is_configured_service_file = explicitly_configured_services.any? do |service|
            file_belongs_to_configured_service?(file, service)
          end

          # Keep files that don't belong to configured services
          unless is_configured_service_file
            filtered_files << file
          end
        end

        filtered_files
      end

      # Check if a file belongs to a configured service
      def file_belongs_to_configured_service?(file, service_name)
        # Standard pattern: service_name/
        return true if file.start_with?("#{service_name}/")

        # Platform pattern: platform/service_name/
        return true if file.include?("/#{service_name}/")

        false
      end

      # Check if a directory name looks like a service directory
      def looks_like_service_directory?(dir_name)
        # Skip common non-service directories
        excluded_dirs = %w[
          .github docs scripts tests spec bin lib config public assets
          platform infrastructure shared common utils tools
        ]
        return false if excluded_dirs.include?(dir_name)

        # Must be a valid service name
        dir_name.match?(/\A[a-zA-Z0-9\-_]+\z/)
      end
    end
  end
end
