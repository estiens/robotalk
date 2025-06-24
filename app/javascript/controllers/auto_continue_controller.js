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
    
    // Prevent multiple simultaneous clicks
    if (this.isProcessing) {
      console.log('Auto-continue: Already processing, skipping')
      return
    }

    console.log('Auto-continue: Starting conversation continuation')
    
    // Find and click the continue button
    // button_to creates a form with a button inside, so we need to find the form first
    const continueForm = document.querySelector('form[action*="/continue"]')
    const continueButton = continueForm?.querySelector('button[type="submit"]')
    
    if (continueButton && !continueButton.disabled) {
      console.log('Auto-continue: Found continue button, clicking it')
      
      // Mark as processing
      this.isProcessing = true
      
      // Set up a promise to wait for the streaming to complete
      const streamingComplete = new Promise((resolve) => {
        let messageFrameAdded = false
        let streamingStarted = false
        let timeoutId = null
        
        // Listen for the message frame being added (indicates streaming started)
        const handleMessageFrame = (event) => {
          const target = event.detail?.newStream?.target
          if (target && target.includes('message_')) {
            console.log('Auto-continue: Message frame added, streaming started')
            messageFrameAdded = true
            streamingStarted = true
            
            // Reset timeout now that streaming has started
            if (timeoutId) clearTimeout(timeoutId)
            timeoutId = setTimeout(() => {
              console.log('Auto-continue: Streaming timeout after message frame')
              cleanup()
              resolve()
            }, 30000) // 30 second timeout after streaming starts
          }
        }
        
        // Listen for the conversation frame being replaced (indicates round complete)
        const handleConversationUpdate = (event) => {
          const target = event.detail?.newStream?.target
          if (target === 'conversation' && streamingStarted) {
            console.log('Auto-continue: Conversation frame updated, round complete')
            cleanup()
            resolve()
          }
        }
        
        // Listen for streaming indicator being shown/hidden
        const handleStreamingIndicator = (event) => {
          const target = event.detail?.newStream?.target
          if (target === 'message-loading') {
            console.log('Auto-continue: Streaming indicator updated')
            if (!streamingStarted) {
              streamingStarted = true
              // Reset timeout when streaming starts
              if (timeoutId) clearTimeout(timeoutId)
              timeoutId = setTimeout(() => {
                console.log('Auto-continue: Streaming timeout')
                cleanup()
                resolve()
              }, 30000)
            }
          }
        }
        
        const cleanup = () => {
          document.removeEventListener('turbo:before-stream-render', handleMessageFrame)
          document.removeEventListener('turbo:before-stream-render', handleConversationUpdate)
          document.removeEventListener('turbo:before-stream-render', handleStreamingIndicator)
          if (timeoutId) clearTimeout(timeoutId)
          this.isProcessing = false
        }
        
        // Set up listeners
        document.addEventListener('turbo:before-stream-render', handleMessageFrame)
        document.addEventListener('turbo:before-stream-render', handleConversationUpdate)
        document.addEventListener('turbo:before-stream-render', handleStreamingIndicator)
        
        // Set initial timeout
        timeoutId = setTimeout(() => {
          console.log('Auto-continue: Initial timeout reached')
          cleanup()
          resolve()
        }, 10000) // 10 second initial timeout
      })
      
      // Click the button
      continueButton.click()
      
      // Wait for streaming to complete
      await streamingComplete
      
      // Add a small delay before checking if we should continue
      setTimeout(() => {
        this.checkAndContinue()
      }, 1000)
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
