import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle"]
  
  connect() {
    // Initialize theme from localStorage or default to light
    const savedTheme = localStorage.getItem('roboconvo-theme') || 'light'
    this.setTheme(savedTheme)
    
    // Add visual feedback for current theme
    this.updateThemeIndicators(savedTheme)
  }
  
  toggle() {
    const currentTheme = document.documentElement.getAttribute('data-theme')
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark'
    this.setTheme(newTheme)
  }
  
  setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme)
    localStorage.setItem('roboconvo-theme', theme)
    
    // Update toggle button if it exists
    if (this.hasToggleTarget) {
      this.updateToggleButton(theme)
    }
    
    // Update all theme indicators
    this.updateThemeIndicators(theme)
    
    // Add visual feedback
    this.showThemeChangeFeedback(theme)
  }
  
  updateToggleButton(theme) {
    const isDark = theme === 'dark'
    const button = this.toggleTarget
    
    // Update button appearance
    button.querySelector('.theme-controller').checked = isDark
    
    // Update icon/text if needed
    const icon = button.querySelector('.swap-on, .swap-off')
    if (icon) {
      if (isDark) {
        button.classList.add('swap-active')
      } else {
        button.classList.remove('swap-active')
      }
    }
  }
  
  updateThemeIndicators(theme) {
    // Update all theme buttons to show current selection
    const allThemeButtons = document.querySelectorAll('[data-theme]')
    allThemeButtons.forEach(button => {
      const buttonTheme = button.dataset.theme
      if (buttonTheme === theme) {
        button.classList.add('bg-primary', 'text-primary-content')
        button.classList.remove('hover:bg-base-300')
      } else {
        button.classList.remove('bg-primary', 'text-primary-content')
        button.classList.add('hover:bg-base-300')
      }
    })
  }
  
  showThemeChangeFeedback(theme) {
    // Create a temporary visual feedback
    const feedback = document.createElement('div')
    feedback.className = 'fixed top-4 right-4 bg-base-200 text-base-content px-4 py-2 rounded-lg shadow-lg z-[60] animate-fade-in'
    feedback.innerHTML = `
      <div class="flex items-center gap-2">
        <span class="text-lg">${this.getThemeIcon(theme)}</span>
        <span class="font-medium">Switched to ${theme.charAt(0).toUpperCase() + theme.slice(1)} theme</span>
      </div>
    `
    
    document.body.appendChild(feedback)
    
    // Remove after 2 seconds
    setTimeout(() => {
      feedback.style.animation = 'fadeOut 0.3s ease-out'
      setTimeout(() => {
        if (feedback.parentNode) {
          feedback.parentNode.removeChild(feedback)
        }
      }, 300)
    }, 2000)
  }
  
  getThemeIcon(theme) {
    const icons = {
      light: '☀️',
      dark: '🌙',
      synthwave: '🌆',
      cyberpunk: '🤖',
      valentine: '💕',
      forest: '🌲'
    }
    return icons[theme] || '🎨'
  }
  
  // Allow setting specific themes from dropdown
  setSpecificTheme(event) {
    const theme = event.target.dataset.theme || event.target.value
    if (theme) {
      this.setTheme(theme)
      
      // Close dropdown if it's open
      const dropdown = event.target.closest('.dropdown')
      if (dropdown) {
        const dropdownButton = dropdown.querySelector('[tabindex="0"]')
        if (dropdownButton) {
          dropdownButton.blur()
        }
      }
    }
  }
}