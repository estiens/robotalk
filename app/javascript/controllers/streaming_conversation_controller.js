import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startButton", "continueButton", "messagesContainer"]
  static values = { 
    conversationId: Number,
    nextModel: String 
  }
  
  connect() {
    console.log("Streaming conversation controller connected")
  }

  // The controller now just handles the Turbo Stream responses
  // The actual streaming is handled by RubyLLM's acts_as_chat integration
} 