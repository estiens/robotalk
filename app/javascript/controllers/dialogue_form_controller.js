import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "dialogueType", "dialogueInstructionsTextarea", "maxRoundsInput", "dialogueInstructionsField" ]
  static values = {
    types: Object
  }

  connect() {
    console.log("Dialogue Form Controller connected!");
    this.updateInstructions(); // Initial update
  }

  updateInstructions() {
    const selectedType = this.dialogueTypeTarget.value;
    const template = this.typesValue[selectedType];

    if (selectedType === 'custom' || !template) {
      this.dialogueInstructionsTextareaTarget.value = '';
      this.dialogueInstructionsTextareaTarget.placeholder = 'Enter custom dialogue instructions (e.g., "Have a thoughtful debate about the topic" or "Brainstorm creative solutions together")...';
      this.maxRoundsInputTarget.value = 10;
    } else {
      // Assuming the template object has a field like 'dialogue_instructions' or 'instructions'
      // Adjust 'template.dialogue_instructions' if the key name is different in your DIALOGUE_TYPES
      this.dialogueInstructionsTextareaTarget.value = template.dialogue_instructions || template.instructions || template.text || '';
      this.dialogueInstructionsTextareaTarget.placeholder = 'Edit these template instructions as needed...';
      this.maxRoundsInputTarget.value = template.suggested_rounds || 10;
      this.flashBackground(this.dialogueInstructionsTextareaTarget);
    }

    this.dialogueInstructionsFieldTarget.value = this.dialogueInstructionsTextareaTarget.value;
  }

  syncHiddenField() {
    this.dialogueInstructionsFieldTarget.value = this.dialogueInstructionsTextareaTarget.value;
  }

  flashBackground(element) {
    element.classList.add('bg-success', 'bg-opacity-10');
    setTimeout(() => {
      element.classList.remove('bg-success', 'bg-opacity-10');
    }, 500);
  }
}