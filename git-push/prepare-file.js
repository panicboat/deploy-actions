const fs = require('fs');
const path = require('path');

module.exports = async ({ core, inputs }) => {
  try {
    core.info('📋 Preparing source file');
    
    const sourceFile = inputs['source-file'];
    const serviceName = inputs['service-name'];
    const environment = inputs['environment'];
    
    // ターゲットリポジトリでの配置先パス（generated-manifests ディレクトリ内）
    const workspaceDir = 'generated-manifests';
    const targetDir = path.join(workspaceDir, environment);
    const targetFile = `${serviceName}.yaml`;
    const targetPath = path.join(targetDir, targetFile);
    
    core.info(`Source: ${sourceFile}`);
    core.info(`Target directory: ${targetDir}`);
    core.info(`Target file: ${targetFile}`);
    core.info(`Target path: ${targetPath}`);
    
    // ターゲットディレクトリの作成
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir, { recursive: true });
      core.info(`Created directory: ${targetDir}`);
    }
    
    // ソースファイルのコピー
    fs.copyFileSync(sourceFile, targetPath);
    core.info(`Copied file to: ${targetPath}`);
    
    // ファイルサイズの確認
    const stats = fs.statSync(targetPath);
    core.info(`Target file size: ${stats.size} bytes`);
    
    // 相対パスを出力（PRの説明で使用）
    const relativePath = path.join(environment, targetFile);
    
    // 出力の設定
    core.setOutput('target-file', relativePath);
    core.setOutput('target-directory', targetDir);
    core.setOutput('target-filename', targetFile);
    
    core.info('✅ Source file prepared successfully');
    
  } catch (error) {
    core.setFailed(`Source file preparation failed: ${error.message}`);
    throw error;
  }
};