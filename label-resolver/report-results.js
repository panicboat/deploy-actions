module.exports = async ({ core, inputs, steps }) => {
  try {
    core.info('📊 Label Resolver completed');
    core.info(`Repository: ${inputs.repository}`);
    core.info(`PR Number: ${inputs['pr-number']}`);
    core.info(`Target Environments: ${inputs['target-environments'] || 'all'}`);
    core.info(`Has Targets: ${steps.extract.outputs['has-targets']}`);
    core.info(`Safety Status: ${steps.extract.outputs['safety-status']}`);

  } catch (error) {
    core.setFailed(`Report generation failed: ${error.message}`);
    throw error;
  }
};
