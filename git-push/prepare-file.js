const fs = require('fs');
const path = require('path');

module.exports = async ({ core, inputs }) => {
  try {
    core.info('📋 Preparing source file');
    
    const sourceFile = inputs['source-file'];
    const targetPath = inputs['target-path'];
    
    // ターゲットリポジトリでの配置先パス（generated-manifests ディレクトリ内）
    const workspaceDir = 'generated-manifests';
    const fullTargetPath = path.join(workspaceDir, targetPath);
    const targetDir = path.dirname(fullTargetPath);
    const targetFile = path.basename(fullTargetPath);
    
    core.info(`Source: ${sourceFile}`);
    core.info(`Target path: ${targetPath}`);
    core.info(`Full target path: ${fullTargetPath}`);
    core.info(`Target directory: ${targetDir}`);
    core.info(`Target file: ${targetFile}`);
    
    // ターゲットディレクトリの作成
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir, { recursive: true });
      core.info(`Created directory: ${targetDir}`);
    }
    
    // ソースファイルのコピー
    fs.copyFileSync(sourceFile, fullTargetPath);
    core.info(`Copied file to: ${fullTargetPath}`);
    
    // ファイルサイズの確認
    const stats = fs.statSync(fullTargetPath);
    core.info(`Target file size: ${stats.size} bytes`);
    
    // 出力の設定
    core.setOutput('target-file', targetPath);
    core.setOutput('target-directory', targetDir);
    core.setOutput('target-filename', targetFile);
    
    core.info('✅ Source file prepared successfully');
    
  } catch (error) {
    core.setFailed(`Source file preparation failed: ${error.message}`);
    throw error;
  }
};