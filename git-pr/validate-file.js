const fs = require('fs');
const yaml = require('js-yaml');

module.exports = async ({ core, inputs }) => {
  try {
    core.info('📋 Validating source file');
    
    const sourceFile = inputs['source-file'];
    const serviceName = inputs['service-name'];
    
    // ファイルサイズのチェック
    const stats = fs.statSync(sourceFile);
    if (stats.size === 0) {
      core.setFailed(`Source file is empty: ${sourceFile}`);
      return;
    }
    
    // ファイル内容の読み取り
    const content = fs.readFileSync(sourceFile, 'utf8');
    
    // 基本的なYAML形式の検証
    if (!content.includes('apiVersion') || !content.includes('kind')) {
      core.setFailed('Source file does not appear to be valid Kubernetes YAML (missing apiVersion or kind)');
      return;
    }
    
    // YAMLパースの検証
    try {
      const documents = yaml.loadAll(content);
      
      if (!documents || documents.length === 0) {
        core.setFailed('Source file does not contain valid YAML documents');
        return;
      }
      
      // 各ドキュメントの基本検証
      let validDocuments = 0;
      for (const doc of documents) {
        if (doc && doc.apiVersion && doc.kind) {
          validDocuments++;
        }
      }
      
      if (validDocuments === 0) {
        core.setFailed('No valid Kubernetes resources found in source file');
        return;
      }
      
      core.info(`✅ Source file validation successful`);
      core.info(`File size: ${stats.size} bytes`);
      core.info(`Valid documents: ${validDocuments}`);
      core.info(`Total documents: ${documents.length}`);
      
      // 成功時の出力設定
      core.setOutput('status', '✅ Success');
      core.setOutput('valid-documents', validDocuments.toString());
      core.setOutput('total-documents', documents.length.toString());
      
    } catch (yamlError) {
      core.setFailed(`Invalid YAML syntax in source file: ${yamlError.message}`);
      return;
    }
    
  } catch (error) {
    core.setFailed(`Source file validation failed: ${error.message}`);
    throw error;
  }
};