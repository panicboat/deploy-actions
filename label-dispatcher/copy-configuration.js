const fs = require('fs');
const path = require('path');

module.exports = async ({ core, inputs }) => {
  try {
    core.info('📋 Copying configuration from source repository');

    const configPath = inputs['config-path'];
    const sourcePath = `source-repo/${configPath}`;
    const targetPath = 'deploy-actions/action-scripts/workflow-config.yaml';

    core.info(`Source path: ${sourcePath}`);
    core.info(`Target path: ${targetPath}`);

    // Check if source file exists
    if (!fs.existsSync(sourcePath)) {
      core.setFailed(`Configuration file not found: ${configPath}`);
      return;
    }

    // Copy file
    fs.copyFileSync(sourcePath, targetPath);

    core.info('✅ Configuration copied successfully');

  } catch (error) {
    core.setFailed(`Configuration copy failed: ${error.message}`);
    throw error;
  }
};
