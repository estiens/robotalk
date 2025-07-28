import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    conversationId: Number,
    maxRounds: Number,
    active: Boolean
  }

  static targets = ["toggle"]

  connect() {
    // Use localStorage to persist auto-continue state by conversation ID
    const key = `auto-continue-active-${this.conversationIdValue}`
    const stored = localStorage.getItem(key)
    
    // Default to false if no stored value
    this.isActive = stored === 'true'
    
    // Update UI to match stored state
    this.updateToggleUI()
    this.updateButtonText()
    
    // Listen for loading completion events
    this.boundHandleLoadingComplete = this.handleLoadingComplete.bind(this)
    document.addEventListener('conversation:loading:complete', this.boundHandleLoadingComplete)
    
    // Don't auto-start on connect - let user explicitly toggle
  }

  disconnect() {
    document.removeEventListener('conversation:loading:complete', this.boundHandleLoadingComplete)
  }

  handleLoadingComplete(event) {
    if (event.detail.conversationId === this.conversationIdValue) {
      console.log('Auto-continue: Received loading complete event')
      
      // Clear safety timeout
      if (this.safetyTimeout) {
        clearTimeout(this.safetyTimeout)
        this.safetyTimeout = null
      }
      
      // Reset processing flag and check if we should continue
      this.isProcessing = false
      setTimeout(() => {
        this.checkAndContinue()
      }, 1000)
    }
  }

  toggle() {
    if (this.isActive) {
      this.stop()
    } else {
      this.start()
    }
  }

  start() {
    this.isActive = true
    localStorage.setItem(`auto-continue-active-${this.conversationIdValue}`, 'true')
    this.updateToggleUI()
    this.updateButtonText()
    
    this.continueConversation()
  }

  stop() {
    this.isActive = false
    localStorage.setItem(`auto-continue-active-${this.conversationIdValue}`, 'false')
    this.updateToggleUI()
    this.updateButtonText()
  }

  updateToggleUI() {
    // Update checkbox state
    this.element.checked = this.isActive
    this.element.setAttribute("data-auto-continue-active-value", this.isActive.toString())
    
    // Update status indicator
    const statusIndicator = document.getElementById('auto-continue-status')
    if (statusIndicator) {
      if (this.isActive) {
        statusIndicator.classList.remove('hidden')
      } else {
        statusIndicator.classList.add('hidden')
      }
    }
  }

  updateButtonText() {
    // Update the continue button text based on auto-continue state
    const buttonText = document.querySelector('.auto-continue-button-text')
    if (buttonText) {
      if (this.isActive) {
        buttonText.innerHTML = '⚡ Auto-continuing...'
      } else {
        buttonText.innerHTML = '🎯 Next Round'
      }
    }
  }

  continueConversation() {
    if (!this.isActive) return
    
    // Prevent multiple simultaneous clicks
    if (this.isProcessing) {
      console.log('Auto-continue: Already processing, skipping')
      return
    }

    console.log('Auto-continue: Starting conversation continuation')
    
    // Find and click the continue button
    const continueForm = document.querySelector('form[action*="/continue"]')
    const continueButton = continueForm?.querySelector('button[type="submit"]')
    
    if (continueButton && !continueButton.disabled) {
      console.log('Auto-continue: Found continue button, clicking it')
      
      // Mark as processing
      this.isProcessing = true
      
      try {
        // Click the button - the new event system will handle completion
        continueButton.click()
        
        // Set up a safety timeout in case event system fails
        this.setupSafetyTimeout()
      } catch (error) {
        console.error('Auto-continue: Error clicking continue button:', error)
        this.handleContinueError('Failed to continue conversation')
      }
    } else {
      console.log('Auto-continue: No continue button found, stopping')
      this.stop()
    }
  }

  setupSafetyTimeout() {
    // Clear any existing timeout
    if (this.safetyTimeout) {
      clearTimeout(this.safetyTimeout)
    }
    
    // Set timeout to reset processing state if event system fails (45 seconds)
    this.safetyTimeout = setTimeout(() => {
      console.warn('Auto-continue: Safety timeout reached - resetting state')
      this.handleContinueError('Auto-continue timed out')
    }, 45000)
  }

  handleContinueError(message) {
    // Reset processing state
    this.isProcessing = false
    
    // Clear timeout
    if (this.safetyTimeout) {
      clearTimeout(this.safetyTimeout)
      this.safetyTimeout = null
    }
    
    // Show error notification
    this.showErrorNotification(message)
    
    // Stop auto-continue to prevent infinite error loops
    console.log('Auto-continue: Stopping due to error:', message)
    this.stop()
  }

  showErrorNotification(message) {
    // Create or update error notification
    let errorElement = document.getElementById('auto-continue-error')
    if (!errorElement) {
      errorElement = document.createElement('div')
      errorElement.id = 'auto-continue-error'
      errorElement.className = 'fixed top-4 left-4 z-50 max-w-sm'
      document.body.appendChild(errorElement)
    }
    
    errorElement.innerHTML = `
      <div class="alert alert-error shadow-lg">
        <div class="flex items-center gap-3">
          <span class="text-lg">⚠️</span>
          <div>
            <div class="font-bold">Auto-continue Error</div>
            <div class="text-sm">${message}</div>
          </div>
        </div>
      </div>
    `
    
    errorElement.classList.remove('hidden')
    
    // Auto-hide after 8 seconds
    setTimeout(() => {
      if (errorElement) {
        errorElement.classList.add('hidden')
      }
    }, 8000)
  }

  checkAndContinue() {
    if (!this.isActive) return
    
    // Check if we should continue - look for the round badge in the hero section
    const roundBadge = document.querySelector('.badge.badge-lg')
    const roundText = roundBadge?.textContent
    const roundMatch = roundText?.match(/Round (\d+)\/(\d+)/)
    
    if (roundMatch) {
      const currentRound = parseInt(roundMatch[1])
      const maxRounds = parseInt(roundMatch[2])
      
      console.log('Auto-continue: Current round:', currentRound, 'Max rounds:', maxRounds)
      
      if (currentRound < maxRounds && this.isActive) {
        // Check if conversation is still active by looking for the continue button
        const continueForm = document.querySelector('form[action*="/continue"]')
        const continueButton = continueForm?.querySelector('button[type="submit"]')
        
        if (continueButton) {
          console.log('Auto-continue: Continuing in 2 seconds...')
          // Add a small delay between messages
          setTimeout(() => {
            this.continueConversation()
          }, 2000)
        } else {
          console.log('Auto-continue: No continue button found, conversation may be complete')
          this.stop()
        }
      } else {
        console.log('Auto-continue: Reached max rounds')
        this.stop()
      }
    } else {
      console.log('Auto-continue: Could not parse round info, stopping')
      this.stop()
    }
  }

  getNextSpeakerInfo() {
    // Try to get the next speaker from the conversation controls data
    const controlsElement = document.querySelector('[data-controller="conversation-controls"]')
    const nextModel = controlsElement?.dataset?.conversationControlsNextModelValue
    
    if (nextModel) {
      // Get participant name by matching the model
      const participantElements = document.querySelectorAll('div.text-sm')
      for (let element of participantElements) {
        const text = element.textContent
        if (text.includes(nextModel)) {
          const nameMatch = text.match(/Model \d+:\s*(.+?)\s*\(/)
          if (nameMatch) {
            return { name: nameMatch[1], model: nextModel }
          }
        }
      }
    }
    
    return { name: "AI Model", model: nextModel || "unknown" }
  }

} 
