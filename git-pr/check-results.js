module.exports = async ({ core, inputs, steps }) => {
  try {
    core.info('📊 Checking Git Push results');
    
    const serviceName = inputs['service-name'];
    const environment = inputs['environment'];
    const targetRepository = inputs['target-repository'];
    
    // ファイル検証の結果チェック
    const fileValidation = steps.validateFile;
    if (fileValidation.outcome !== 'success') {
      core.setFailed(`File validation failed for ${serviceName}:${environment}`);
      core.setOutput('validation-status', '❌ Failed');
      core.setOutput('has-changes', 'false');
      return;
    }
    
    // PR作成の結果チェック
    const prCreation = steps.createPr;
    const prNumber = prCreation.outputs['pull-request-number'];
    const prUrl = prCreation.outputs['pull-request-url'];
    
    if (prCreation.outcome === 'success' && prNumber) {
      // PR作成成功
      core.info(`✅ Successfully created Git Push PR #${prNumber}`);
      core.info(`PR URL: ${prUrl}`);
      core.info(`Target repository: ${targetRepository}`);
      core.info(`Service: ${serviceName}`);
      core.info(`Environment: ${environment}`);
      
      core.setOutput('validation-status', '✅ Success');
      core.setOutput('has-changes', 'true');
      
    } else if (prCreation.outcome === 'success' && !prNumber) {
      // 変更なし
      core.info(`ℹ️ No changes detected for ${serviceName}:${environment}`);
      core.info('No PR was created because there were no changes to commit');
      
      core.setOutput('validation-status', '✅ Success');
      core.setOutput('has-changes', 'false');
      
    } else {
      // PR作成失敗
      core.error(`❌ Failed to create Git Push PR for ${serviceName}:${environment}`);
      core.error(`Target repository: ${targetRepository}`);
      
      core.setOutput('validation-status', '❌ PR Creation Failed');
      core.setOutput('has-changes', 'false');
      
      // PR作成が失敗した場合は全体を失敗にする
      core.setFailed('Git Push PR creation failed');
    }
    
    // 最終サマリー
    core.info('📊 Git Push Summary:');
    core.info(`Service: ${serviceName}`);
    core.info(`Environment: ${environment}`);
    core.info(`Target: ${targetRepository}`);
    core.info(`Validation: ${fileValidation.outcome}`);
    core.info(`PR Creation: ${prCreation.outcome}`);
    core.info(`Has Changes: ${core.getInput('has-changes') || 'false'}`);
    
  } catch (error) {
    core.setFailed(`Result checking failed: ${error.message}`);
    core.setOutput('validation-status', '❌ Error');
    core.setOutput('has-changes', 'false');
    throw error;
  }
};