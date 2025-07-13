const fs = require('fs');
const { execSync } = require('child_process');

/**
 * gotk-sync.yamlを生成
 */
function generateGotkSync(env) {
  const repoUrl = execSync('basename $(git config --get remote.origin.url) .git', { encoding: 'utf-8' }).trim();
  
  const content = `apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/${repoUrl}
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./clusters/${env}
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
`;
  
  const filePath = `clusters/${env}/flux-system/gotk-sync.yaml`;
  fs.writeFileSync(filePath, content);
  console.log(`📝 Generated gotk-sync for ${env}`);
}

module.exports = { generateGotkSync };