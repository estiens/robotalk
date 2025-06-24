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
    
    // Don't auto-start on connect - let user explicitly toggle
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

  async continueConversation() {
    if (!this.isActive) return

    console.log('Auto-continue: Starting conversation continuation')
    
    // Find and click the continue button
    // button_to creates a form with a button inside, so we need to find the form first
    const continueForm = document.querySelector('form[action*="/continue"]')
    const continueButton = continueForm?.querySelector('button[type="submit"]')
    
    if (continueButton && !continueButton.disabled) {
      console.log('Auto-continue: Found continue button, clicking it')
      
      // Show loading indicator if it exists
      const loadingIndicator = document.querySelector('#message-loading[data-controller="loading-indicator"]')
      if (loadingIndicator) {
        const nextSpeakerInfo = this.getNextSpeakerInfo()
        const loadingController = this.application.getControllerForElementAndIdentifier(loadingIndicator, 'loading-indicator')
        if (loadingController) {
          loadingController.show(nextSpeakerInfo.name)
        }
      }
      
      // Listen for new messages being added via Turbo Streams (streaming job)
      const handleNewMessage = (event) => {
        console.log('Auto-continue: New message detected via Turbo Stream')
        
        // Remove the event listener
        document.removeEventListener('turbo:before-stream-render', handleNewMessage)
        
        // Hide loading indicator
        if (loadingIndicator) {
          const loadingController = this.application.getControllerForElementAndIdentifier(loadingIndicator, 'loading-indicator')
          if (loadingController) {
            loadingController.hide()
          }
        }
        
        // Check if we should continue after a short delay to allow streaming to complete
        setTimeout(() => {
          this.checkAndContinue()
        }, 3000) // Longer delay to allow streaming to finish
      }
      
      // Listen for Turbo Stream updates (from streaming job)
      document.addEventListener('turbo:before-stream-render', handleNewMessage)
      
      // Set a timeout fallback in case streaming doesn't complete
      setTimeout(() => {
        console.log('Auto-continue: Timeout reached, cleaning up')
        document.removeEventListener('turbo:before-stream-render', handleNewMessage) 
        if (loadingIndicator) {
          const loadingController = this.application.getControllerForElementAndIdentifier(loadingIndicator, 'loading-indicator')
          if (loadingController) {
            loadingController.hide()
          }
        }
        this.checkAndContinue()
      }, 45000) // Longer timeout for streaming
      
      // Click the button
      continueButton.click()
    } else {
      console.log('Auto-continue: No continue button found, stopping')
      this.stop()
    }
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
