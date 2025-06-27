import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon", "spinner"]

  connect() {
    console.log("Loading button controller connected")
  }

  showLoading() {
    // Show spinner, hide icon
    this.iconTarget.classList.add("hidden")
    this.spinnerTarget.classList.remove("hidden")
    
    // Disable button to prevent multiple clicks
    this.element.disabled = true
    this.element.classList.add("loading")
  }
}