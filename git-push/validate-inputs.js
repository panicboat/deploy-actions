const fs = require('fs');

module.exports = async ({ core, inputs }) => {
  try {
    core.info('🔍 Validating inputs for Git Push Action');
    
    const sourceFile = inputs['source-file'];
    const serviceName = inputs['service-name'];
    const environment = inputs['environment'];
    const targetRepository = inputs['target-repository'];
    const targetBranch = inputs['target-branch'] || 'main';
    const githubToken = inputs['github-token'];
    const prNumber = inputs['pr-number'];
    
    // 必須項目の検証
    if (!sourceFile) {
      core.setFailed('source-file is required');
      return;
    }
    
    if (!serviceName) {
      core.setFailed('service-name is required');
      return;
    }
    
    if (!environment) {
      core.setFailed('environment is required');
      return;
    }
    
    if (!targetRepository) {
      core.setFailed('target-repository is required');
      return;
    }
    
    if (!githubToken) {
      core.setFailed('github-token is required');
      return;
    }
    
    // source-fileの存在確認
    if (!fs.existsSync(sourceFile)) {
      core.setFailed(`Source file does not exist: ${sourceFile}`);
      return;
    }
    
    // target-repositoryの形式確認
    if (!targetRepository.includes('/')) {
      core.setFailed('target-repository must be in format "owner/repo"');
      return;
    }
    
    // service-nameの形式確認（英数字とハイフンのみ）
    if (!/^[a-zA-Z0-9-]+$/.test(serviceName)) {
      core.setFailed('service-name must contain only alphanumeric characters and hyphens');
      return;
    }
    
    // environmentの形式確認
    if (!/^[a-zA-Z0-9-]+$/.test(environment)) {
      core.setFailed('environment must contain only alphanumeric characters and hyphens');
      return;
    }
    
    // pr-numberの形式確認（オプション）
    if (prNumber && !/^\d+$/.test(prNumber)) {
      core.setFailed('pr-number must be a numeric value');
      return;
    }
    
    // source-fileの基本情報をログ出力
    const stats = fs.statSync(sourceFile);
    
    core.info(`✅ Input validation successful`);
    core.info(`Source file: ${sourceFile}`);
    core.info(`Service: ${serviceName}`);
    core.info(`Environment: ${environment}`);
    core.info(`Target: ${targetRepository}:${targetBranch}`);
    core.info(`PR Number: ${prNumber || 'not specified'}`);
    core.info(`Source file size: ${stats.size} bytes`);
    
  } catch (error) {
    core.setFailed(`Input validation failed: ${error.message}`);
    throw error;
  }
};