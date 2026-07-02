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
    grid.innerHTML = window.PTIPOTE_DATA.buildings.map((building) => `
      <button class="building-card ${state.selectedBuilding === building.id ? "active" : ""}" type="button" data-building="${building.id}">
        <span class="building-icon">${building.icon}</span>
        <h3>${building.name}</h3>
        <p>${building.summary}</p>
      </button>
    `).join("");

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
