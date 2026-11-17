import { Controller } from "@hotwired/stimulus"

// A decision request that ends with no HTTP response (timeout, dropped connection, offline) has an unknown
// outcome. Say so, and keep the form exactly as rendered (same idempotency key and expected version), so
// Retry is replayed by the server instead of applied twice. Reloading shows the authoritative state.
export default class extends Controller {
  static targets = ["unknown"]

  start(event) {
    this.form = event.target
    this.submitter = event.detail.formSubmission.submitter
    this.notice.replaceChildren()
  }

  end(event) {
    if (event.detail.fetchResponse) return // the server answered; Turbo renders that answer

    const message = this.unknownTarget.content.cloneNode(true)
    message.querySelector("[data-decision-form-retry]").addEventListener("click", () => this.retry())
    this.notice.replaceChildren(message)
  }

  retry() {
    this.form?.requestSubmit(this.submitter)
  }

  get notice() {
    return document.getElementById("notice")
  }
}
