module.exports = async ({ core, inputs, steps }) => {
  try {
    core.info('📊 Deploy resolver completed');
    core.info(`Repository: ${inputs.repository}`);
    core.info(`Action type: ${inputs['action-type']}`);
    core.info(`PR Number: ${inputs['pr-number']}`);
    core.info(`Has Targets: ${steps.extract.outputs['has-targets']}`);
    core.info(`Target Environment: ${steps.extract.outputs['target-environment']}`);
    core.info(`Safety Status: ${steps.extract.outputs['safety-status']}`);

  } catch (error) {
    core.setFailed(`Report generation failed: ${error.message}`);
    throw error;
  }
};
