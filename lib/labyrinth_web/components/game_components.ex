defmodule LabyrinthWeb.Components.GameComponents do
  @moduledoc """
  Reusable UI components for Labyrinth game rendering (Grid, Log Viewer, Post-Its).
  """
  use Phoenix.Component

  attr :log_entries, :list, required: true
  attr :gm_mode, :boolean, default: false

  def log_viewer(assigns) do
    ~H"""
    <div id="game-log-viewer" class="space-y-3 max-h-96 overflow-y-auto pr-1 font-mono text-xs">
      <%= if @log_entries == [] do %>
        <div class="p-4 bg-slate-900/60 rounded-xl border border-slate-800 text-slate-500 text-center italic">
          No turn activity recorded yet. Take the first step!
        </div>
      <% else %>
        <%= for log <- Enum.take(@log_entries, 15) do %>
          <div class="p-3 bg-slate-900/80 rounded-xl border border-slate-800/80 text-slate-300 space-y-1">
            <div class="flex items-center justify-between text-[11px] text-slate-400 border-b border-slate-800 pb-1">
              <span class="font-bold text-amber-400">{log.player_name}</span>
              <span>Round {log.round}</span>
            </div>
            <p class="text-slate-200">{log.message}</p>
            <%= if @gm_mode and log.gm_note do %>
              <p class="text-indigo-300 text-[11px] bg-indigo-950/40 p-1 rounded border border-indigo-800/40">
                👁 GM: {log.gm_note}
              </p>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :post_its, :list, required: true
  attr :player_id, :string, required: true

  def post_it_overlay(assigns) do
    ~H"""
    <div id="post-it-board" class="flex flex-wrap gap-3">
      <%= for post_it <- @post_its do %>
        <div
          id={"post-it-#{post_it.id}"}
          class={[
            "p-3 rounded-xl shadow-lg border w-48 text-xs font-sans relative flex flex-col justify-between transition-all",
            case post_it.color do
              "yellow" -> "bg-amber-100 border-amber-300 text-amber-950"
              "blue" -> "bg-sky-100 border-sky-300 text-sky-950"
              "green" -> "bg-emerald-100 border-emerald-300 text-emerald-950"
              "pink" -> "bg-rose-100 border-rose-300 text-rose-950"
              _ -> "bg-amber-100 border-amber-300 text-amber-950"
            end
          ]}
        >
          <div class="space-y-1">
            <div class="font-bold text-[11px] border-b border-black/10 pb-1 flex justify-between items-center">
              <span>📌 Note</span>
              <%= if post_it.player_id == @player_id do %>
                <button
                  phx-click="delete_post_it"
                  phx-value-id={post_it.id}
                  class="text-rose-700 hover:text-rose-900 font-bold text-xs"
                >
                  ✕
                </button>
              <% end %>
            </div>
            <p class="whitespace-pre-wrap">{post_it.content}</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
