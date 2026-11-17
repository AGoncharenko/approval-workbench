import { Controller } from "@hotwired/stimulus"

// A decision request that ends with no HTTP response (timeout, dropped connection, offline) has an unknown
// outcome. Say so, and keep the form exactly as rendered (same idempotency key and expected version), so
// Retry is replayed by the server instead of applied twice. Reloading shows the authoritative state.
export default class extends Controller {
  static targets = ["unknown"]

  start(event) {
    this.form = event.target
    this.submitter = event.detail.formSubmission.submitter
    this.submitting = true
    this.notice.replaceChildren()
    // The server's answer (e.g. a 409 showing the current version) must bring its own version and key (and the
    // version shown), so the render may replace them. The reason textarea stays permanent.
    this.held = [...this.element.querySelectorAll("[data-turbo-permanent]:not(textarea)")]
    this.held.forEach((field) => field.removeAttribute("data-turbo-permanent"))
  }

  end(event) {
    if (event.detail.fetchResponse) return // the server answered; Turbo renders that answer
    this.submitting = false
    // No answer: keep this exact version and key, so Retry is replayed rather than applied twice.
    this.held?.forEach((field) => field.setAttribute("data-turbo-permanent", ""))

    const message = this.unknownTarget.content.cloneNode(true)
    message.querySelector("[data-decision-form-retry]").addEventListener("click", () => this.retry())
    this.notice.replaceChildren(message)
  }

  // A live refresh (someone else's change) that would remove these controls keeps them while a reason is typed:
  // the refreshed status and history above show what changed, and submitting reports the conflict honestly.
  // The answer to our own submission always renders as sent.
  beforeMorph(event) {
    const { target, detail: { newElement } } = event
    if (target === this.element && !newElement) {
      if (!this.submitting && this.typedReason) event.preventDefault()
    } else if (newElement) {
      // Permanent fields keep their value but take the server's validation state (aria-invalid, describedby, border).
      for (const field of target.querySelectorAll(":scope > [data-turbo-permanent][id]")) {
        const fresh = newElement.querySelector(`:scope > #${CSS.escape(field.id)}`)
        if (!fresh) continue
        for (const name of ["aria-invalid", "aria-describedby", "class"]) {
          fresh.hasAttribute(name) ? field.setAttribute(name, fresh.getAttribute(name)) : field.removeAttribute(name)
        }
      }
    }
  }

  rendered() {
    this.submitting = false
  }

  get typedReason() {
    return [...this.element.querySelectorAll("textarea")].some((field) => field.value.trim())
  }

  retry() {
    this.form?.requestSubmit(this.submitter)
  }

  get notice() {
    return document.getElementById("notice")
  }
}
