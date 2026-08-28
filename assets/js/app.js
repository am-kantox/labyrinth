// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/labyrinth"
import topbar from "../vendor/topbar"

const AudioHook = {
  mounted() {
    this.handleEvent("play_sfx", ({ sound }) => {
      this.playSynthesizedSFX(sound)
    })
  },
  playSynthesizedSFX(type) {
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext
      if (!AudioCtx) return
      const ctx = new AudioCtx()
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.connect(gain)
      gain.connect(ctx.destination)

      const now = ctx.currentTime

      if (type === "gunshot") {
        osc.type = "sawtooth"
        osc.frequency.setValueAtTime(300, now)
        osc.frequency.exponentialRampToValueAtTime(30, now + 0.15)
        gain.gain.setValueAtTime(0.5, now)
        gain.gain.exponentialRampToValueAtTime(0.01, now + 0.15)
        osc.start(now)
        osc.stop(now + 0.15)
      } else if (type === "explosion") {
        osc.type = "square"
        osc.frequency.setValueAtTime(120, now)
        osc.frequency.exponentialRampToValueAtTime(10, now + 0.4)
        gain.gain.setValueAtTime(0.8, now)
        gain.gain.exponentialRampToValueAtTime(0.01, now + 0.4)
        osc.start(now)
        osc.stop(now + 0.4)
      } else if (type === "footstep") {
        osc.type = "sine"
        osc.frequency.setValueAtTime(80, now)
        osc.frequency.linearRampToValueAtTime(30, now + 0.08)
        gain.gain.setValueAtTime(0.2, now)
        gain.gain.linearRampToValueAtTime(0.01, now + 0.08)
        osc.start(now)
        osc.stop(now + 0.08)
      } else if (type === "minotaur") {
        osc.type = "sawtooth"
        osc.frequency.setValueAtTime(60, now)
        osc.frequency.linearRampToValueAtTime(40, now + 0.5)
        gain.gain.setValueAtTime(0.6, now)
        gain.gain.exponentialRampToValueAtTime(0.01, now + 0.5)
        osc.start(now)
        osc.stop(now + 0.5)
      }
    } catch (e) {
      console.warn("AudioContext error:", e)
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: { AudioHook, ...colocatedHooks },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
window.liveSocket = liveSocket
