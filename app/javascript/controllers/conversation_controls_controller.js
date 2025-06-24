import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "startButton" ]

  connect() {
    // console.log("Conversation controls connected")
  }

  
  showLoading() {
      if (this.hasStartButtonTarget) {
        this.startButtonTarget.classList.add("loading")
        this.startButtonTarget.disabled = true
        this.startButtonTarget.innerHTML = `
          <span class="loading loading-spinner"></span>
          Generating...
        `
        // Manually submit the form because disabling the button prevents default submission
        this.startButtonTarget.closest("form").requestSubmit();
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
      'openai/gpt-4o': 'OpenAI GPT-4o',
      'openai/gpt-4o-mini': 'OpenAI GPT-4o Mini',
      'anthropic/claude-3-5-sonnet': 'Anthropic Claude 3.5 Sonnet',
      'anthropic/claude-3-haiku': 'Anthropic Claude 3 Haiku',
      'google/gemini-pro': 'Google Gemini Pro',
      'meta-llama/llama-3.1-8b-instruct': 'Meta Llama 3.1 8B',
      'meta-llama/llama-3.1-70b-instruct': 'Meta Llama 3.1 70B'
    }
    
    return modelNames[modelIdentifier] || modelIdentifier
  }
}