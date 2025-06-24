import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "full", "toggleButton"]
  static values = { limit: Number }
  
  connect() {
    this.isExpanded = false
  }

  toggle() {
    if (this.isExpanded) {
      this.collapse()
    } else {
      this.expand()
    }
  }

  expand() {
    this.previewTarget.classList.add('hidden')
    this.fullTarget.classList.remove('hidden')
    this.toggleButtonTarget.textContent = 'Show less'
    this.isExpanded = true
  }

  collapse() {
    this.previewTarget.classList.remove('hidden')
    this.fullTarget.classList.add('hidden')
    this.toggleButtonTarget.textContent = 'Show more'
    this.isExpanded = false
  }
}