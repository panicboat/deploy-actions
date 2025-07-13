const fs = require('fs');
const path = require('path');

/**
 * 環境ディレクトリ内のYAMLファイルを再帰的に探索
 */
function findYamlFiles(dir) {
  let results = [];
  const list = fs.readdirSync(dir);
  list.forEach(file => {
    const filepath = path.join(dir, file);
    const stat = fs.statSync(filepath);
    if (stat && stat.isDirectory()) {
      results = results.concat(findYamlFiles(filepath));
    } else if (filepath.endsWith('.yaml')) {
      results.push(filepath);
    }
  });
  return results.sort();
}

/**
 * apps配下のkustomization.yamlを生成
 */
function generateAppsKustomization(env) {
  let content = `apiVersion: kustomize.config.k8s.io/v1
kind: Kustomization
`;

  // 環境ディレクトリが存在するかチェック
  if (fs.existsSync(env)) {
    const yamlFiles = findYamlFiles(env);
    
    if (yamlFiles.length > 0) {
      content += 'resources:\n';
      
      for (const manifest of yamlFiles) {
        // 相対パスを取得（環境ディレクトリからの相対パス）
        const relativePath = path.relative(env, manifest);
        const serviceName = path.basename(manifest, '.yaml');
        
        // ディレクトリ構造を保持してclusters配下にディレクトリを作成
        const manifestDir = path.dirname(relativePath);
        if (manifestDir !== '.') {
          fs.mkdirSync(`clusters/${env}/apps/${manifestDir}`, { recursive: true });
          content += `  - ${relativePath}\n`;
        } else {
          // 直接配下のファイルの場合
          content += `  - ${serviceName}.yaml\n`;
        }
      }
    } else {
      console.log(`⚠️  No YAML files found in ${env} directory`);
      content += 'resources: []\n';
    }
  } else {
    console.log(`📝 Environment directory ${env} does not exist, creating empty structure`);
    content += 'resources: []\n';
  }
  
  const filePath = `clusters/${env}/apps/kustomization.yaml`;
  fs.writeFileSync(filePath, content);
  console.log(`📝 Generated apps kustomization for ${env}`);
  
  return { yamlFiles: fs.existsSync(env) ? findYamlFiles(env) : [] };
}

module.exports = { generateAppsKustomization };