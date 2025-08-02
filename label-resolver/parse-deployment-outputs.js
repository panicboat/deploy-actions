module.exports = async ({ core, context }) => {
  try {
    core.info('📊 Parsing deployment outputs');

    const deploymentTargets = process.env.DEPLOYMENT_TARGETS || '[]';
    const hasTargets = process.env.HAS_TARGETS || 'false';
    const safetyStatus = process.env.SAFETY_STATUS || 'unknown';

    core.info(`DEPLOYMENT_TARGETS: ${deploymentTargets}`);
    core.info(`HAS_TARGETS: ${hasTargets}`);
    core.info(`SAFETY_STATUS: ${safetyStatus}`);

  } catch (error) {
    core.setFailed(`Deployment output parsing failed: ${error.message}`);
    throw error;
  }
};
