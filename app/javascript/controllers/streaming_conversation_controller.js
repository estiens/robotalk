import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startButton", "continueButton", "messagesContainer"]
  static values = { 
    conversationId: Number,
    nextModel: String 
  }
  
  connect() {
    console.log("Streaming conversation controller connected")
    
    // Initialize loading state
    this.isStreaming = false
    this.loadingElements = new Set()
    
    // Subscribe to Turbo Stream events to handle streaming updates
    this.handleStreamUpdates = this.handleStreamUpdates.bind(this)
    document.addEventListener("turbo:before-stream-render", this.handleStreamUpdates)
  }
  
  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.handleStreamUpdates)
  }
  
  handleStreamUpdates(event) {
    const streamElement = event.detail.newStream
    
    if (streamElement) {
      const action = streamElement.getAttribute("action")
      const target = streamElement.getAttribute("target")
      
      console.log(`Streaming update: action=${action}, target=${target}`)
      
      // Handle different stream targets for consistent loading states
      switch (target) {
        case "conversation":
          if (action === "replace") {
            this.onConversationComplete()
          }
          break
          
        case "message-loading":
          if (action === "update") {
            this.showLoadingIndicator()
          }
          break
          
        default:
          // Handle individual message streams
          if (target && target.includes('message_')) {
            this.onMessageStream(target, action)
          }
      }
    }
  }
  
  onConversationComplete() {
    console.log("Conversation stream complete - cleaning up loading states")
    this.isStreaming = false
    this.hideAllLoadingIndicators()
    this.broadcastLoadingComplete()
  }
  
  onMessageStream(target, action) {
    if (action === "append" || action === "update") {
      this.isStreaming = true
      console.log(`Message streaming: ${target}`)
    }
  }
  
  showLoadingIndicator() {
    const loadingElement = document.getElementById("message-loading")
    if (loadingElement) {
      loadingElement.classList.remove("hidden")
      this.loadingElements.add(loadingElement)
    }
  }
  
  hideAllLoadingIndicators() {
    // Hide main loading indicator
    const loadingElement = document.getElementById("message-loading")
    if (loadingElement) {
      loadingElement.classList.add("hidden")
    }
    
    // Clear tracked loading elements
    this.loadingElements.forEach(element => {
      element.classList.add("hidden")
    })
    this.loadingElements.clear()
  }
  
  broadcastLoadingComplete() {
    // Dispatch custom event for other controllers to respond to
    const event = new CustomEvent('conversation:loading:complete', {
      detail: { conversationId: this.conversationIdValue }
    })
    document.dispatchEvent(event)
  }
  
  // Legacy method for backwards compatibility
  hideLoadingIndicator() {
    this.hideAllLoadingIndicators()
  }
}