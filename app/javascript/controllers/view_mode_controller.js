import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "historyView", "liveView"]
  static values = { default: String }

  connect() {
    console.log('View mode controller connected')
    this.setInitialMode()
  }

  setInitialMode() {
    // Check if targets exist before proceeding
    if (!this.hasHistoryViewTarget || !this.hasLiveViewTarget) {
      console.warn('View mode controller: Missing required targets')
      return
    }
    
    // Always default to live view initially, but allow localStorage override
    const savedMode = localStorage.getItem('conversation-view-mode') || 'live'
    console.log('Setting initial mode to:', savedMode)
    this.setMode(savedMode)
  }

  switchMode(event) {
    const mode = event.target.dataset.mode
    console.log('Switching to mode:', mode)
    this.setMode(mode)
    localStorage.setItem('conversation-view-mode', mode)
  }

  setMode(mode) {
    console.log('Setting mode to:', mode)
    
    // Check if targets exist before using them
    if (!this.hasHistoryViewTarget || !this.hasLiveViewTarget) {
      console.warn('View mode controller: Cannot set mode - missing targets')
      return
    }
    
    console.log('History view element:', this.historyViewTarget)
    console.log('Live view element:', this.liveViewTarget)
    
    // Remove active classes from all tabs first
    this.toggleTargets.forEach(toggle => {
      toggle.classList.remove('tab-active')
    })
    
    if (mode === 'live') {
      // Hide history, show live
      this.historyViewTarget.classList.add('hidden')
      this.liveViewTarget.classList.remove('hidden')
      
      // Activate live tab
      this.toggleTargets.forEach(toggle => {
        if (toggle.dataset.mode === 'live') {
          toggle.classList.add('tab-active')
        }
      })
      
      console.log('Live view activated')
    } else if (mode === 'history') {
      // Hide live, show history  
      this.liveViewTarget.classList.add('hidden')
      this.historyViewTarget.classList.remove('hidden')
      
      // Activate history tab
      this.toggleTargets.forEach(toggle => {
        if (toggle.dataset.mode === 'history') {
          toggle.classList.add('tab-active')
        }
      })
      
      console.log('History view activated')
    }
    
    console.log('Mode set complete - History hidden:', this.historyViewTarget.classList.contains('hidden'))
    console.log('Mode set complete - Live hidden:', this.liveViewTarget.classList.contains('hidden'))
  }
}