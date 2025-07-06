# File system client for git operations and file/directory checks
# Handles file change detection and path validation

module Infrastructure
  class FileSystemClient
    # Get list of changed files using git diff
    def get_changed_files(base_ref: nil, head_ref: nil)
      if base_ref && head_ref
        # Check if refs exist before using them
        unless ref_exists?(base_ref) && ref_exists?(head_ref)
          puts "Warning: One or both refs don't exist (#{base_ref}, #{head_ref}). Using current working tree changes."
          return get_current_changes
        end
        `git diff --name-only #{base_ref}...#{head_ref}`.strip.split("\n").reject(&:empty?)
      elsif base_ref
        unless ref_exists?(base_ref)
          puts "Warning: Base ref '#{base_ref}' doesn't exist. Using current working tree changes."
          return get_current_changes
        end
        `git diff --name-only #{base_ref}`.strip.split("\n").reject(&:empty?)
      else
        get_current_changes
      end
    rescue => error
      puts "Warning: Git diff failed: #{error.message}. Using current working tree changes."
      get_current_changes
    end

    private

    # Check if a git reference exists
    def ref_exists?(ref)
      system("git rev-parse --verify #{ref} >/dev/null 2>&1")
    end

    # Get current working tree changes (staged + unstaged)
    def get_current_changes
      # Get both staged and unstaged changes
      staged_files = `git diff --cached --name-only`.strip.split("\n").reject(&:empty?)
      unstaged_files = `git diff --name-only`.strip.split("\n").reject(&:empty?)

      # Combine and deduplicate
      (staged_files + unstaged_files).uniq
    end

    # Check if directory exists
    def directory_exists?(path)
      File.directory?(path)
    end

    # Check if file exists
    def file_exists?(path)
      File.exist?(path)
    end

    # Get all directories matching a pattern
    def find_directories(pattern)
      Dir.glob(pattern).select { |path| File.directory?(path) }
    end

    # Get current git branch
    def current_branch
      `git branch --show-current`.strip
    rescue => error
      raise "Failed to get current branch: #{error.message}"
    end

    # Check if git repository is clean
    def git_clean?
      `git status --porcelain`.strip.empty?
    rescue => error
      raise "Failed to check git status: #{error.message}"
    end
  end
end
