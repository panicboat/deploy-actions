module.exports = async ({ core, context, inputs }) => {
  try {
    core.info('📊 Label dispatch completed');
    core.info(`Repository: ${inputs.repository}`);
    core.info(`PR Number: ${inputs['pr-number']}`);
    core.info(`Status: ${context.job.status || 'unknown'}`);

  } catch (error) {
    core.setFailed(`Report generation failed: ${error.message}`);
    throw error;
  }
};
