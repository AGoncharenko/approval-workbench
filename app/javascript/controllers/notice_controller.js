import { Controller } from "@hotwired/stimulus"

// The page's live region. A live refresh (someone else's change) re-renders the page without a flash, which would
// wipe the outcome of the user's own last command. Keep that message through refreshes; clear it when the user
// submits again, so the next answer is the only one shown.
export default class extends Controller {
  keep(event) {
    if (event.target !== this.element) return
    const incoming = event.detail.newElement
    if (this.element.textContent.trim() && !incoming?.textContent.trim()) event.preventDefault()
  }

  clear() {
    this.element.replaceChildren()
  }
}
