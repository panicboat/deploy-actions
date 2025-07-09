/**
 * Remove ANSI color codes from text
 * Based on terragrunt-action's clean_colors function
 */
function cleanColors(text) {
  if (!text) return '';
  // Remove ANSI escape sequences: \x1B[<numbers and semicolons>[mGK]
  return text.replace(/\x1B\[[0-9;]*[mGK]/g, '');
}

/**
 * Process multiline text for safe output
 * Based on terragrunt-action's clean_multiline_text function
 */
function cleanMultilineText(text) {
  if (!text) return '';
  
  // First, clean ANSI color codes
  let cleaned = cleanColors(text);
  
  // URL decode if needed (terragrunt-action URL encodes the output)
  try {
    cleaned = decodeURIComponent(cleaned);
  } catch (error) {
    // If decoding fails, use original text
  }
  
  // Trim whitespace
  cleaned = cleaned.trim();
  
  return cleaned;
}

module.exports = async ({ core, inputs, steps }) => {
  try {
    core.info('📊 Parsing Terragrunt execution results');
    
    const exitCode = steps.terragrunt.outputs.tg_action_exit_code;
    const actionType = inputs['action-type'];
    const rawOutput = steps.terragrunt.outputs.tg_action_output;
    
    core.info(`Exit Code: ${exitCode}`);
    core.info(`Action Type: ${actionType}`);
    
    // Determine status and failure state
    const isSuccess = exitCode === '0';
    const status = isSuccess ? '✅ Success' : `❌ Failed (exit code: ${exitCode})`;
    const isFailed = !isSuccess;
    
    // Process output following terragrunt-action's approach
    let output;
    if (!rawOutput || rawOutput.trim() === '') {
      output = `${actionType} execution completed. See workflow logs for detailed output.`;
    } else {
      // Clean the output using terragrunt-action's approach
      output = cleanMultilineText(rawOutput);
      
      // Truncate if too long (GitHub comment limit consideration)
      const maxLength = 30000;
      if (output.length > maxLength) {
        output = output.substring(0, maxLength) + '\n... (output truncated, see workflow logs for full details)';
      }
    }
    
    // Set outputs
    core.setOutput('status', status);
    core.setOutput('is-failed', isFailed.toString());
    core.setOutput('output', output);
    
    // Log summary
    core.info('📊 Execution Summary:');
    core.info(`Status: ${status}`);
    core.info(`Action: ${actionType}`);
    core.info(`Service: ${inputs['service-name']}`);
    core.info(`Environment: ${inputs['environment']}`);
    
  } catch (error) {
    core.setFailed(`Result parsing failed: ${error.message}`);
    throw error;
  }
};