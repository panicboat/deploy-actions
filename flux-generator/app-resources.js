const fs = require('fs');
const path = require('path');

/**
 * アプリケーション用のKustomizationリソースを生成
 */
function generateAppResources(env, yamlFiles) {
  for (const manifest of yamlFiles) {
    // 相対パスを取得（環境ディレクトリからの相対パス）
    const relativePath = path.relative(env, manifest);
    const serviceName = path.basename(manifest, '.yaml');
    
    // ディレクトリ構造を保持してclusters配下にディレクトリを作成
    const manifestDir = path.dirname(relativePath);
    
    let content;
    let filePath;
    
    if (manifestDir !== '.') {
      // サブディレクトリ内のファイルの場合
      const resourceName = relativePath.replace(/[\/]/g, '-').replace(/\.yaml$/, '');
      content = `apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${resourceName}
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./${env}/${manifestDir}
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  targetNamespace: default
  postBuild:
    substitute:
      service_name: "${serviceName}"
`;
      filePath = `clusters/${env}/apps/${relativePath}`;
    } else {
      // 直接配下のファイルの場合
      content = `apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${serviceName}
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./${env}
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  targetNamespace: default
  postBuild:
    substitute:
      service_name: "${serviceName}"
`;
      filePath = `clusters/${env}/apps/${serviceName}.yaml`;
    }
    
    fs.writeFileSync(filePath, content);
    console.log(`📝 Generated app resource: ${filePath}`);
  }
}

module.exports = { generateAppResources };