# File system client for git operations and file/directory checks
# Handles file change detection and path validation

module Infrastructure
  class FileSystemClient
    # Get list of changed files using git diff
    def get_changed_files(base_ref: nil, head_ref: nil)
      # Determine the correct git repository directory
      git_dir = source_repo_path || '.'
      
      if base_ref && head_ref
        # Check if refs exist before using them
        unless ref_exists?(base_ref, git_dir) && ref_exists?(head_ref, git_dir)
          puts "Warning: One or both refs don't exist (#{base_ref}, #{head_ref}). Using current working tree changes."
          return get_current_changes(git_dir)
        end
        execute_git_command("git diff --name-only #{base_ref}...#{head_ref}", git_dir)
      elsif base_ref
        unless ref_exists?(base_ref, git_dir)
          puts "Warning: Base ref '#{base_ref}' doesn't exist. Using current working tree changes."
          return get_current_changes(git_dir)
        end
        execute_git_command("git diff --name-only #{base_ref}", git_dir)
      else
        get_current_changes(git_dir)
      end
    rescue => error
      puts "Warning: Git diff failed: #{error.message}. Using current working tree changes."
      get_current_changes(git_dir)
    end

    private

    # Get the source repository path for composite actions
    def source_repo_path
      # In composite actions, source repo is checked out to ../source-repo or ../../source-repo
      candidates = ['../../source-repo', '../source-repo', ENV['SOURCE_REPO_PATH']].compact
      candidates.find { |path| File.directory?(path) && File.directory?(File.join(path, '.git')) }
    end

    # Execute git command in specific directory
    def execute_git_command(command, git_dir)
      if git_dir != '.'
        result = `cd #{git_dir} && #{command}`.strip.split("\n").reject(&:empty?)
      else
        result = `#{command}`.strip.split("\n").reject(&:empty?)
      end
      result
    end

    # Check if a git reference exists
    def ref_exists?(ref, git_dir = '.')
      if git_dir != '.'
        system("cd #{git_dir} && git rev-parse --verify #{ref} >/dev/null 2>&1")
      else
        system("git rev-parse --verify #{ref} >/dev/null 2>&1")
      end
    end

    # Get current working tree changes (staged + unstaged)
    def get_current_changes(git_dir = '.')
      # Get both staged and unstaged changes
      if git_dir != '.'
        staged_files = `cd #{git_dir} && git diff --cached --name-only`.strip.split("\n").reject(&:empty?)
        unstaged_files = `cd #{git_dir} && git diff --name-only`.strip.split("\n").reject(&:empty?)
      else
        staged_files = `git diff --cached --name-only`.strip.split("\n").reject(&:empty?)
        unstaged_files = `git diff --name-only`.strip.split("\n").reject(&:empty?)
      end

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
