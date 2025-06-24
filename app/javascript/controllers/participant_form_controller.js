import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "addButton"]
  static values = { 
    participantIndex: Number,
    modelOptions: Array,
    characters: Object,
    dialogueTypes: Object
  }

  connect() {
    this.setupExistingParticipants()
  }

  setupExistingParticipants() {
    // Setup character selects for existing participants
    this.element.querySelectorAll('.character-select').forEach(select => {
      this.setupCharacterSelect(select)
      // Ensure preview is hidden initially for existing participants
      const participantDiv = select.closest('.participant-item')
      const previewSection = participantDiv?.querySelector('.character-preview')
      if (previewSection) {
        previewSection.classList.add('hidden')
        previewSection.style.display = 'none'
      }
    })
  }

  addParticipant() {
    const participantHtml = this.buildParticipantHTML()
    this.containerTarget.insertAdjacentHTML('beforeend', participantHtml)
    
    const newParticipant = this.containerTarget.lastElementChild
    const characterSelect = newParticipant.querySelector('.character-select')
    this.setupCharacterSelect(characterSelect)
    
    // Animate the new participant in
    newParticipant.style.opacity = '0'
    newParticipant.style.transform = 'translateY(20px)'
    requestAnimationFrame(() => {
      newParticipant.style.transition = 'all 0.3s ease'
      newParticipant.style.opacity = '1'
      newParticipant.style.transform = 'translateY(0)'
    })
    
    this.participantIndexValue++
  }

  removeParticipant(event) {
    const participantItem = event.target.closest('.participant-item')
    const remainingParticipants = this.containerTarget.children.length
    
    if (remainingParticipants > 1) {
      // Animate out
      participantItem.style.transition = 'all 0.3s ease'
      participantItem.style.opacity = '0'
      participantItem.style.transform = 'translateX(-20px) scale(0.95)'
      
      setTimeout(() => {
        participantItem.remove()
        this.updateParticipantNumbers()
      }, 300)
    } else {
      this.showAlert('You must have at least 1 participant', 'warning')
    }
  }

  setupCharacterSelect(selectElement) {
    selectElement.addEventListener('change', (event) => {
      const selectedCharacter = event.target.value
      const participantDiv = event.target.closest('.participant-item')
      
      if (selectedCharacter && selectedCharacter !== 'custom') {
        this.applyCharacterTemplate(participantDiv, selectedCharacter)
      } else if (selectedCharacter === 'custom') {
        this.clearCharacterTemplate(participantDiv)
      }
    })
  }

  applyCharacterTemplate(participantDiv, characterKey) {
    const character = this.charactersValue[characterKey]
    if (!character) return

    const nameInput = participantDiv.querySelector('.participant-name')
    const characterPromptTextarea = participantDiv.querySelector('.character-prompt')
    const previewSection = participantDiv.querySelector('.character-preview')
    const previewText = participantDiv.querySelector('.character-preview-text')

    // Update name
    if (nameInput && !nameInput.value) {
      nameInput.value = character.default_name || character.name || characterKey
      this.animateInput(nameInput)
    }

    // Update character prompt
    if (characterPromptTextarea) {
      characterPromptTextarea.value = character.prompt
      characterPromptTextarea.placeholder = 'Edit this character description as needed...'
      this.animateInput(characterPromptTextarea)
    }

    // Show preview
    if (previewSection && previewText) {
      previewText.textContent = `${character.default_name || characterKey} will bring ${character.prompt.substring(0, 100)}...`
      previewSection.classList.remove('hidden')
      previewSection.style.opacity = '0'
      requestAnimationFrame(() => {
        previewSection.style.transition = 'opacity 0.3s ease'
        previewSection.style.opacity = '1'
      })
    }
  }

  clearCharacterTemplate(participantDiv) {
    const characterPromptTextarea = participantDiv.querySelector('.character-prompt')
    const nameInput = participantDiv.querySelector('.participant-name')
    const previewSection = participantDiv.querySelector('.character-preview')

    if (characterPromptTextarea) {
      characterPromptTextarea.value = ''
      characterPromptTextarea.placeholder = 'Enter your custom character description...'
    }

    if (nameInput && !nameInput.value) {
      nameInput.placeholder = 'Enter custom name...'
    }

    if (previewSection) {
      previewSection.style.opacity = '0'
      setTimeout(() => previewSection.classList.add('hidden'), 300)
    }
  }

  animateInput(element) {
    element.classList.add('bg-success', 'bg-opacity-10')
    setTimeout(() => {
      element.classList.remove('bg-success', 'bg-opacity-10')
    }, 1000)
  }

  updateParticipantNumbers() {
    this.containerTarget.querySelectorAll('.participant-item').forEach((item, index) => {
      const title = item.querySelector('h4')
      const turnOrderInput = item.querySelector('.turn-order-input, input[name*="turn_order"]')
      
      if (title) {
        title.textContent = `Participant ${index + 1}`
        // Update color class based on index
        title.className = `font-semibold text-lg ${index % 2 === 0 ? 'text-primary' : 'text-secondary'}`
      }
      if (turnOrderInput) turnOrderInput.value = index + 1
    })
  }

  showAlert(message, type = 'info') {
    // Create a toast notification
    const toast = document.createElement('div')
    toast.className = `alert alert-${type} fixed top-4 right-4 z-50 max-w-sm shadow-lg`
    toast.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      </svg>
      <span>${message}</span>
    `
    
    document.body.appendChild(toast)
    
    // Animate in
    toast.style.opacity = '0'
    toast.style.transform = 'translateX(100%)'
    requestAnimationFrame(() => {
      toast.style.transition = 'all 0.3s ease'
      toast.style.opacity = '1'
      toast.style.transform = 'translateX(0)'
    })
    
    // Remove after 3 seconds
    setTimeout(() => {
      toast.style.opacity = '0'
      toast.style.transform = 'translateX(100%)'
      setTimeout(() => toast.remove(), 300)
    }, 3000)
  }

  buildParticipantHTML() {
    return `
      <div class="group bg-base-200/50 hover:bg-base-200/70 border border-base-300 transition-colors duration-200 rounded-lg participant-item" data-test="participant-${this.participantIndexValue}">
        <div class="p-3">
          <div class="flex justify-between items-center mb-3">
            <h4 class="font-semibold text-base ${this.participantIndexValue % 2 === 0 ? 'text-primary' : 'text-secondary'}">
              Participant ${this.participantIndexValue + 1}
            </h4>
            <button type="button" 
                    class="hover:bg-error/10 text-error transition-colors btn btn-ghost btn-circle btn-xs remove-participant"
                    data-action="click->participant-form#removeParticipant"
                    data-test="remove-participant"
                    title="Remove participant">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          
          <div class="grid grid-cols-2 gap-3">
            <div class="form-control">
              <label class="label py-1">
                <span class="text-sm font-medium text-base-content label-text">Name</span>
              </label>
              <input type="text" 
                     name="conversation[participants_attributes][${this.participantIndexValue}][name]" 
                     placeholder="e.g. Dr. Smith" 
                     required 
                     class="input input-sm input-bordered w-full bg-base-100 text-base-content participant-name focus:border-primary transition-colors">
            </div>
            
            <div class="form-control">
              <label class="label py-1">
                <span class="text-sm font-medium text-base-content label-text">AI Model</span>
              </label>
              <select name="conversation[participants_attributes][${this.participantIndexValue}][model_id]" 
                      required 
                      class="select select-sm select-bordered w-full bg-base-100 text-base-content focus:border-primary transition-colors">
                <option value="">Select model...</option>
                ${this.modelOptionsValue.map(option => `<option value="${option.value}">${option.text}</option>`).join('')}
              </select>
            </div>
          </div>
          
          <input type="hidden" 
                 name="conversation[participants_attributes][${this.participantIndexValue}][turn_order]" 
                 value="${this.participantIndexValue + 1}" 
                 class="turn-order-input">
          
          <div class="mt-3 form-control">
            <select class="select select-sm select-bordered w-full bg-base-100 text-base-content character-select" 
                    data-participant-index="${this.participantIndexValue}">
              <option value="">Choose personality (optional)...</option>
              ${this.buildCharacterOptions()}
              <option value="custom">Custom</option>
            </select>
          </div>
          
          <div class="hidden mt-1 character-preview" style="display: none;">
            <div class="text-xs text-success flex items-center gap-1">
              <span>✨</span>
              <span class="character-preview-text"></span>
            </div>
          </div>
          
          <div class="mt-2 form-control">
            <textarea name="conversation[participants_attributes][${this.participantIndexValue}][character_prompt]" 
                      rows="2" 
                      class="textarea textarea-sm textarea-bordered w-full bg-base-100 text-base-content character-prompt focus:border-primary transition-colors resize-none" 
                      placeholder="Custom character description (optional)..."></textarea>
          </div>
          
          <details class="mt-2">
            <summary class="text-xs text-base-content/60 cursor-pointer hover:text-base-content">Advanced system prompt</summary>
            <div class="mt-2">
              <textarea name="conversation[participants_attributes][${this.participantIndexValue}][system_prompt]" 
                        rows="1" 
                        class="textarea textarea-sm textarea-bordered w-full bg-base-100 text-base-content focus:border-primary transition-colors resize-none" 
                        placeholder="Technical instructions for the model..."></textarea>
            </div>
          </details>
        </div>
      </div>
    `
  }

  buildCharacterOptions() {
    const thinking = ['analytical', 'creative', 'pragmatic', 'philosophical']
    const communication = ['socratic', 'collaborative', 'skeptical', 'synthesizer']
    const others = Object.keys(this.charactersValue).filter(k => 
      !thinking.includes(k) && !communication.includes(k)
    )
    
    let options = '<optgroup label="🧠 Thinking Styles">'
    thinking.forEach(key => {
      if (this.charactersValue[key]) {
        const char = this.charactersValue[key]
        options += `<option value="${key}">${char.default_name || char.name || key} - ${char.prompt.substring(0, 50)}...</option>`
      }
    })
    options += '</optgroup>'
    
    options += '<optgroup label="💬 Communication Styles">'
    communication.forEach(key => {
      if (this.charactersValue[key]) {
        const char = this.charactersValue[key]
        options += `<option value="${key}">${char.default_name || char.name || key} - ${char.prompt.substring(0, 50)}...</option>`
      }
    })
    options += '</optgroup>'
    
    if (others.length > 0) {
      options += '<optgroup label="🎭 Personalities">'
      others.forEach(key => {
        const char = this.charactersValue[key]
        options += `<option value="${key}">${char.default_name || char.name || key} - ${char.prompt.substring(0, 50)}...</option>`
      })
      options += '</optgroup>'
    }
    
    return options
  }
}