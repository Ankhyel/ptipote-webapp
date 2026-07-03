(function () {
  function renderHud(state) {
    const hud = document.getElementById("hudStats");
    const ptipote = window.PTIPOTE_STATE.getSelectedPtipote(state);
    hud.innerHTML = `
      <div class="stat-pill">PA ${ptipote.actionPoints}</div>
      <div class="stat-pill">XP ${ptipote.xp}</div>
      <div class="stat-pill">Repas ${state.resources.meals}</div>
      <div class="stat-pill">Sec. ${state.resources.security}</div>
    `;
  }

  function renderBuildings(state, onSelect) {
    const grid = document.getElementById("buildingGrid");
    const ptipote = window.PTIPOTE_STATE.getSelectedPtipote(state);
    grid.style.setProperty("--refuge-bg", `url("${window.PTIPOTE_DATA.refuge.background}")`);
    grid.innerHTML = `
      <div class="refuge-overlay" aria-hidden="true"></div>
      ${window.PTIPOTE_DATA.buildings.map((building) => `
        <button
          class="building-card ${state.selectedBuilding === building.id ? "active" : ""}"
          style="--x:${building.x}%;--y:${building.y}%;--w:${building.w}%;--h:${building.h}%"
          type="button"
          data-building="${building.id}"
        >
          <span>${building.name}</span>
        </button>
      `).join("")}
      <button class="refuge-ptipote" type="button" data-building="home">
        <span class="refuge-ptipote-avatar">${ptipote.name.slice(0, 1)}</span>
        <span>${ptipote.name} · niv. ${ptipote.level}</span>
      </button>
    `;

    grid.querySelectorAll("[data-building]").forEach((button) => {
      button.addEventListener("click", () => onSelect(button.dataset.building));
    });
  }

  function showTab(tab) {
    document.querySelectorAll(".view").forEach((view) => {
      view.classList.toggle("active", view.dataset.view === tab);
    });
    document.querySelectorAll(".nav-button").forEach((button) => {
      button.classList.toggle("active", button.dataset.tab === tab);
    });
  }

  window.PTIPOTE_UI_ISLAND = {
    renderHud,
    renderBuildings,
    showTab
  };
})();
