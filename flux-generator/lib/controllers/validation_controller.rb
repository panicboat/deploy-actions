
module Controllers
  class ValidationController
    def initialize(file_system_repository, manifest_repository)
      @file_system = file_system_repository
      @manifest_repository = manifest_repository
    end

    def validate_environments(environment_names)
      environment_names.each do |env_name|
        environment = Entities::Environment.from_name(env_name)
        validate_environment(environment)
      end
    end

    private

    attr_reader :file_system, :manifest_repository

    def validate_environment(environment)
      puts "  🔍 Checking environment: #{environment.name}"

      unless environment.valid?
        puts "    ❌ Invalid environment name: #{environment.name}"
        return
      end

      validate_environment_directory(environment)
      validate_flux_directories(environment)
      validate_manifests(environment)
    end

    def validate_environment_directory(environment)
      unless @file_system.directory_exists?(environment.name)
        puts "    ⚠️  Environment directory missing: #{environment.name}"
      else
        puts "    ✅ Environment directory exists: #{environment.name}"
      end
    end

    def validate_flux_directories(environment)
      unless @file_system.directory_exists?(environment.flux_system_path)
        puts "    ❌ Missing flux-system directory: #{environment.flux_system_path}"
      else
        puts "    ✅ flux-system directory exists"
      end

      unless @file_system.directory_exists?(environment.apps_path)
        puts "    ❌ Missing apps directory: #{environment.apps_path}"
      else
        puts "    ✅ apps directory exists"
      end
    end

    def validate_manifests(environment)
      manifests = @manifest_repository.find_manifests_for_environment(environment)
      puts "    📄 Found #{manifests.size} manifest(s)"

      manifests.each do |manifest|
        puts "      - #{manifest.relative_path} (#{manifest.service_name})"
      end
    end
  end
end
