# GitHub API client for interacting with GitHub repositories
# Handles PR labels and PR information retrieval

require 'octokit'

module Infrastructure
  class GitHubClient
    def initialize(token:, repository:)
      @client = Octokit::Client.new(access_token: token)
      @repository = repository
    end

    # Get all deploy labels from a PR
    def get_deploy_labels(pr_number, prefix:)
      labels = @client.labels_for_issue(@repository, pr_number)
      labels.map(&:name).select { |name| name.start_with?(prefix) }
    rescue Octokit::Error => error
      raise "Failed to get PR labels: #{error.message}"
    end

    # Get PR information including labels
    def get_pr_info(pr_number)
      pr = @client.pull_request(@repository, pr_number)
      labels = @client.labels_for_issue(@repository, pr_number)

      {
        labels: labels.map(&:name),
        head_ref: pr.head.ref,
        base_ref: pr.base.ref,
        head_sha: pr.head.sha,
        base_sha: pr.base.sha,
        title: pr.title,
        state: pr.state,
        merged: pr.merged,
        number: pr.number,
        html_url: pr.html_url
      }
    end

    # Add a label to a PR
    def add_label_to_pr(pr_number, label)
      @client.add_labels_to_an_issue(@repository, pr_number, [label])
    rescue Octokit::Error => error
      raise "Failed to add label #{label}: #{error.message}"
    end

    # Remove a label from a PR
    def remove_label_from_pr(pr_number, label)
      @client.remove_label(@repository, pr_number, label)
    rescue Octokit::NotFound
      # Label doesn't exist on PR, ignore
    rescue Octokit::Error => error
      raise "Failed to remove label #{label}: #{error.message}"
    end

    # Ensure a label exists in the repository
    def ensure_label_exists(label_name)
      @client.label(@repository, label_name)
    rescue Octokit::NotFound
      @client.add_label(@repository, label_name, '0052cc', {
        description: 'Auto-generated deployment label'
      })
    rescue Octokit::Error => error
      raise "Failed to ensure label exists #{label_name}: #{error.message}"
    end
  end
end
