const fs = require('fs');

/**
 * flux-system用のkustomization.yamlを生成
 */
function generateFluxSystemKustomization(env) {
  const content = `apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gotk-sync.yaml
`;
  
  const filePath = `clusters/${env}/flux-system/kustomization.yaml`;
  fs.writeFileSync(filePath, content);
  console.log(`📝 Generated flux-system kustomization for ${env}`);
}

module.exports = { generateFluxSystemKustomization };