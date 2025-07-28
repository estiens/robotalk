import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "startButton", "continueButton" ]

  connect() {
    // Store original button states for restoration
    this.originalStates = new Map()
    
    // Listen for Turbo events to restore button states
    this.boundRestoreButtons = this.restoreAllButtons.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundRestoreButtons)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.boundRestoreButtons)
  }

  showLoading(event) {
    const button = event.currentTarget
    if (!button) return

    // Store original state if not already stored
    if (!this.originalStates.has(button)) {
      this.originalStates.set(button, {
        innerHTML: button.innerHTML,
        disabled: button.disabled,
        classes: [...button.classList]
      })
    }

    // Apply loading state
    this.setButtonLoading(button, this.getLoadingText(button))
    
    // Submit form with error handling
    const form = button.closest("form")
    if (form) {
      try {
        form.requestSubmit()
        
        // Set up timeout to handle stuck loading states
        this.setupLoadingTimeout(button)
      } catch (error) {
        console.error("Form submission failed:", error)
        this.handleSubmissionError(button, "Failed to submit form")
      }
    } else {
      console.warn("Conversation controls: Button is not in a form.", button)
      this.handleSubmissionError(button, "Button configuration error")
    }
  }

  setupLoadingTimeout(button) {
    // Clear any existing timeout
    if (this.loadingTimeout) {
      clearTimeout(this.loadingTimeout)
    }
    
    // Set timeout to detect stuck loading states (30 seconds)
    this.loadingTimeout = setTimeout(() => {
      console.warn("Loading timeout reached - restoring button state")
      this.handleSubmissionError(button, "Request timed out - please try again")
    }, 30000)
  }

  handleSubmissionError(button, message) {
    // Restore button state
    const originalState = this.originalStates.get(button)
    if (originalState) {
      this.restoreButton(button, originalState)
      this.originalStates.delete(button)
    }
    
    // Show error message
    this.showApiStatus(message, 'error')
    
    // Auto-hide error after 5 seconds
    setTimeout(() => {
      this.hideApiStatus()
    }, 5000)
    
    // Clear timeout
    if (this.loadingTimeout) {
      clearTimeout(this.loadingTimeout)
      this.loadingTimeout = null
    }
  }

  setButtonLoading(button, loadingText = 'Processing...') {
    button.classList.add("loading")
    button.disabled = true
    button.innerHTML = `<span class="loading loading-spinner loading-sm"></span> ${loadingText}`
  }

  getLoadingText(button) {
    // Determine appropriate loading text based on button context
    if (button.textContent.includes('Start') || button.textContent.includes('Begin')) {
      return 'Starting dialogue...'
    } else if (button.textContent.includes('Continue') || button.textContent.includes('Next')) {
      return 'Generating response...'
    }
    return 'Processing...'
  }

  restoreAllButtons(event) {
    // Restore buttons when conversation frame is replaced
    const streamElement = event.detail.newStream
    if (streamElement?.getAttribute("target") === "conversation") {
      this.originalStates.forEach((state, button) => {
        this.restoreButton(button, state)
      })
      this.originalStates.clear()
      
      // Clear any pending timeouts
      if (this.loadingTimeout) {
        clearTimeout(this.loadingTimeout)
        this.loadingTimeout = null
      }
    }
  }

  restoreButton(button, originalState) {
    if (button && originalState) {
      button.innerHTML = originalState.innerHTML
      button.disabled = originalState.disabled
      button.className = originalState.classes.join(' ')
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