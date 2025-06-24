import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["controls"]

  connect() {
    this.element.addEventListener("conversation:completed", this.enableControls.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("conversation:completed", this.enableControls.bind(this))
  }

  enableControls() {
    if (this.hasControlsTarget) {
      this.controlsTarget.classList.remove("hidden")
    }
  }
}