module Controllers
  class SetupController
    def initialize(file_system_repository)
      @file_system = file_system_repository
    end

    def setup_directories(environment_names)
      puts "🚀 Setting up FluxCD directories..."

      environment_names.each do |env_name|
        environment = Entities::Environment.from_name(env_name)
        setup_environment_directories(environment)
      end
    end

    def setup_missing_directories
      puts "🔧 Setting up missing environment directories and files..."

      missing_environments = %w[staging production].select do |env_name|
        !@file_system.directory_exists?(env_name)
      end

      missing_environments.each do |env_name|
        puts "📝 Creating missing environment: #{env_name}"
        environment = Entities::Environment.from_name(env_name)

        # Create basic directory structure
        @file_system.ensure_directory(environment.name)
        @file_system.ensure_directory("#{environment.name}/services")
        @file_system.ensure_directory(environment.flux_system_path)
        @file_system.ensure_directory(environment.apps_path)

        # Create placeholder kustomization files
        create_placeholder_kustomizations(environment)
      end

      puts "✅ Missing directories setup completed!" if missing_environments.any?
    end

    def setup_missing_kustomizations(environment_names)
      puts "📝 Setting up missing kustomization files..."

      environment_names.each do |env_name|
        environment = Entities::Environment.from_name(env_name)

        # Check for missing root kustomization
        root_kustomization_path = "#{environment.name}/kustomization.yaml"
        unless File.exist?(root_kustomization_path)
          create_root_kustomization(environment)
        end

        # Check for missing services kustomization
        services_kustomization_path = "#{environment.name}/services/kustomization.yaml"
        if @file_system.directory_exists?("#{environment.name}/services") && !File.exist?(services_kustomization_path)
          create_services_kustomization(environment)
        end
      end

      puts "✅ Missing kustomization files setup completed!"
    end

    private

    attr_reader :file_system

    def setup_environment_directories(environment)
      puts "📦 Creating directories for environment: #{environment.name}"

      unless @file_system.directory_exists?(environment.name)
        puts "📝 Environment directory #{environment.name} does not exist, creating empty FluxCD structure..."
      end

      @file_system.ensure_directory(environment.flux_system_path)
      @file_system.ensure_directory(environment.apps_path)
      @file_system.ensure_directory(environment.name)
    end

    def create_placeholder_kustomizations(environment)
      create_root_kustomization(environment)
      create_services_kustomization(environment)
    end

    def create_root_kustomization(environment)
      # Determine resources to include based on existing subdirectories
      subdirs = find_subdirectories(environment)
      resources = subdirs.empty? ? [] : subdirs.map { |dir| "#{dir}/" }

      kustomization = Entities::FluxResource.kustomize_config(resources: resources)
      content = kustomization.to_yaml.gsub(/^metadata:\s*\{\}\n/, '')

      @file_system.write_file("#{environment.name}/kustomization.yaml", content)
      puts "📝 Created root kustomization for #{environment.name}"
    end

    def create_services_kustomization(environment)
      # Find all service manifest files in services directory (excluding kustomization.yaml)
      services_dir = "#{environment.name}/services"
      return unless @file_system.directory_exists?(services_dir)

      yaml_files = @file_system.find_yaml_files(services_dir)
      resources = yaml_files
        .map { |file| File.basename(file) }
        .reject { |filename| filename == 'kustomization.yaml' }

      kustomization = Entities::FluxResource.kustomize_config(resources: resources)
      content = kustomization.to_yaml.gsub(/^metadata:\s*\{\}\n/, '')

      @file_system.write_file("#{services_dir}/kustomization.yaml", content)
      puts "📝 Created services kustomization for #{environment.name}"
    end

    def find_subdirectories(environment)
      return [] unless @file_system.directory_exists?(environment.name)

      Dir.entries(environment.name)
         .select { |entry| File.directory?(File.join(environment.name, entry)) }
         .reject { |entry| entry.start_with?('.') }
    end
  end
end
