import { Controller } from "@hotwired/stimulus"

// Chat form controller
// Handles form submission, input clearing, and auto-scroll
export default class extends Controller {
  static targets = [ "input", "submit" ]

  connect() {
    console.log("Chat form controller connected")
  }

  submit(event) {
    // Prevent default form submission if input is empty
    if (this.inputTarget.value.trim() === "") {
      event.preventDefault()
      return
    }

    // Disable submit button to prevent double submission
    this.submitTarget.disabled = true
    this.submitTarget.textContent = "送信中..."

    // Re-enable after a short delay (form will be reset by Turbo Stream)
    setTimeout(() => {
      this.submitTarget.disabled = false
      this.submitTarget.textContent = "送信"
      this.inputTarget.focus()
    }, 1000)
  }
}
