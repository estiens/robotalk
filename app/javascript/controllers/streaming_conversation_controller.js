import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startButton", "continueButton", "messagesContainer"]
  static values = { 
    conversationId: Number,
    nextModel: String 
  }
  
  connect() {
    console.log("Streaming conversation controller connected")
    
    // Subscribe to Turbo Stream events to handle streaming updates
    this.handleStreamUpdates = this.handleStreamUpdates.bind(this)
    document.addEventListener("turbo:before-stream-render", this.handleStreamUpdates)
  }
  
  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.handleStreamUpdates)
  }
  
  handleStreamUpdates(event) {
    const streamElement = event.detail.newStream
    
    // Log stream updates for debugging
    if (streamElement) {
      const action = streamElement.getAttribute("action")
      const target = streamElement.getAttribute("target")
      
      console.log(`Streaming update: action=${action}, target=${target}`)
      
      // Hide loading indicator when conversation frame is replaced
      if (target === "conversation" && action === "replace") {
        this.hideLoadingIndicator()
      }
      
      // Show loading indicator is already visible when message-loading is updated
      if (target === "message-loading" && action === "update") {
        const loadingElement = document.getElementById("message-loading")
        if (loadingElement) {
          loadingElement.classList.remove("hidden")
        }
      }
    }
  }
  
  hideLoadingIndicator() {
    const loadingElement = document.getElementById("message-loading")
    if (loadingElement) {
      loadingElement.classList.add("hidden")
    }
  }
}