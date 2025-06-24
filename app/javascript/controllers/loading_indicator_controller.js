import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modelName"]
  
  show(modelName = "AI Model") {
    this.modelNameTarget.textContent = modelName
    this.element.classList.remove('hidden')
    
    // Scroll to show the loading indicator
    this.element.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }

  hide() {
    this.element.classList.add('hidden')
  }

  updateModelName(modelName) {
    this.modelNameTarget.textContent = modelName
  }
}