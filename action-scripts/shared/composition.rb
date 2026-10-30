module Composition
  def self.repository_root
    Infrastructure::RepositoryRoot.locate(source_path: ENV['SOURCE_REPO_PATH'], start_path: Dir.pwd)
  end

  def self.config_client
    Infrastructure::ConfigClient.new(config_path: ENV['WORKFLOW_CONFIG_PATH'] || 'workflow-config.yaml')
  end

  def self.git_client
    Infrastructure::GitClient.new(repository_root: repository_root)
  end

  def self.directory_scanner
    Infrastructure::DirectoryScanner.new(repository_root: repository_root)
  end

  def self.github_client
    token = ENV['GITHUB_TOKEN']
    repository = ENV['GITHUB_REPOSITORY']
    raise 'GITHUB_TOKEN and GITHUB_REPOSITORY are required' if token.nil? || repository.nil?

    Infrastructure::GitHubClient.new(token: token, repository: repository)
  end

  def self.github_actions?
    !ENV['GITHUB_ACTIONS'].nil?
  end

  def self.github_output_path
    ENV['GITHUB_OUTPUT']
  end

  def self.presenter
    return Interfaces::Presenters::ConsolePresenter.new unless github_actions?

    output_path = github_output_path
    # Checked before the command runs so dispatch cannot change labels and then fail to write outputs.
    raise 'GITHUB_OUTPUT is not set' if output_path.nil?

    Interfaces::Presenters::GitHubActionsPresenter.new(output_path: output_path)
  end
end
