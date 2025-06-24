import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "startButton", "continueButton" ] // Add continueButton

  connect() {
    // console.log("Conversation controls connected")
  }

  
  showLoading(event) { // Accept event
    const button = event.currentTarget // Get the button that was clicked
    if (button) {
      button.classList.add("loading")
      button.disabled = true
      
      // Preserve existing icons/SVG if possible, just add spinner and text
      const originalContent = button.innerHTML; // Store original content if needed for restoration
      let spinnerSVG = '<span class="loading loading-spinner"></span>';
      let textNode = 'Generating...';

      // Check if button is start or continue to adjust text/icon if necessary
      // For now, generic "Generating..."
      // A more robust way would be to have specific spinner content elements within the button
      // and toggle their visibility, or use data attributes for loading text.
      
      button.innerHTML = `${spinnerSVG} ${textNode}`;
      
      // Manually submit the form because disabling the button prevents default submission
      // This assumes the button is a submit button or inside a form.
      const form = button.closest("form");
      if (form) {
        form.requestSubmit();
      } else {
        console.warn("Conversation controls: Button is not in a form.", button);
      }
    }
  }

  showApiStatus(message, type = 'info') {
    let statusElement = document.getElementById('api-status-indicator')
    
    if (!statusElement) {
      statusElement = document.createElement('div')
      statusElement.id = 'api-status-indicator'
      statusElement.className = 'fixed top-4 right-4 z-50 max-w-sm'
      document.body.appendChild(statusElement)
    }
    
    const alertClass = type === 'error' ? 'alert-error' : type === 'success' ? 'alert-success' : 'alert-info'
    const icon = type === 'error' ? '❌' : type === 'success' ? '✅' : 'ℹ️'
    
    statusElement.innerHTML = `
      <div class="alert ${alertClass} shadow-lg">
        <div class="flex items-center gap-3">
          <span class="text-lg">${icon}</span>
          <span class="text-sm">${message}</span>
        </div>
      </div>
    `
    
    statusElement.classList.remove('hidden')
  }

  hideApiStatus() {
    const statusElement = document.getElementById('api-status-indicator')
    if (statusElement) {
      statusElement.classList.add('hidden')
    }
  }
  
  getModelDisplayName(modelIdentifier) {
    const modelNames = {
      'deepseek/deepseek-r1-0528': 'DeepSeek R1 0528', // Added DeepSeek
      'openai/gpt-4o': 'OpenAI GPT-4o',
      'openai/gpt-4o-mini': 'OpenAI GPT-4o Mini',
      'anthropic/claude-3-5-sonnet': 'Anthropic Claude 3.5 Sonnet',
      'anthropic/claude-3-haiku': 'Anthropic Claude 3 Haiku',
      // Removed specific google/gemini-pro from here unless it's a general OpenRouter offering you want listed
      // Add other OpenRouter models and their friendly names as needed
      'google/gemini-pro': 'Google Gemini Pro (OpenRouter)', // Kept if it's a general OpenRouter option
      'meta-llama/llama-3.1-8b-instruct': 'Meta Llama 3.1 8B (OpenRouter)',
      'meta-llama/llama-3.1-70b-instruct': 'Meta Llama 3.1 70B (OpenRouter)'
    }
    
    return modelNames[modelIdentifier] || modelIdentifier
  }
}