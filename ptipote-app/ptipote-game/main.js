(function () {
  let state = window.PTIPOTE_STATE.loadState();
  let tickTimer = null;

  function persistAndRender() {
    window.PTIPOTE_STATE.saveState(state);
    render();
  }

  function render() {
    window.PTIPOTE_UI_ISLAND.showTab(state.selectedTab);
    window.PTIPOTE_UI_ISLAND.renderHud(state);
    window.PTIPOTE_UI_ISLAND.renderBuildings(state, selectBuilding);
    window.PTIPOTE_UI_PANELS.renderPtipotes(state, selectPtipote);
    window.PTIPOTE_UI_PANELS.renderJournal(state);
    window.PTIPOTE_UI_PANELS.renderSheet(state, { onAction: handleAction });
    scheduleTick();
  }

  function scheduleTick() {
    clearInterval(tickTimer);
    if (state.activeTask) {
      tickTimer = setInterval(render, 1000);
    }
  }

  function selectBuilding(buildingId) {
    state.selectedBuilding = buildingId;
    state.selectedTab = "island";
    persistAndRender();
  }

  function selectPtipote(uid) {
    state.selectedPtipoteUid = uid;
    window.PTIPOTE_STATE.addJournal(state, `P'TIPOTE selectionne : ${window.PTIPOTE_STATE.getSelectedPtipote(state).name}.`);
    window.PTIPOTE_STATE.advanceObjective(state, 0);
    state.selectedTab = "island";
    state.selectedBuilding = "bio";
    persistAndRender();
  }

  function handleAction(action, payload) {
    const actions = {
      gather: () => window.PTIPOTE_TASKS.startGather(state),
      finishGather: () => window.PTIPOTE_TASKS.finishGather(state),
      craft: () => window.PTIPOTE_TASKS.craftMeal(state, payload.qty),
      security: () => window.PTIPOTE_TASKS.generateSecurity(state),
      sell: () => window.PTIPOTE_TASKS.sellStock(state, payload.stock),
      rest: () => window.PTIPOTE_TASKS.restAtHome(state),
      feed: () => window.PTIPOTE_TASKS.feedAtHome(state),
      progress: () => window.PTIPOTE_TASKS.applyProgression(state)
    };

    const error = actions[action] ? actions[action]() : "Action inconnue.";
    if (error) window.PTIPOTE_STATE.addJournal(state, error);
    persistAndRender();
  }

  function bindNavigation() {
    document.querySelectorAll(".nav-button").forEach((button) => {
      button.addEventListener("click", () => {
        state.selectedTab = button.dataset.tab;
        persistAndRender();
      });
    });

    document.getElementById("resetButton").addEventListener("click", () => {
      state = window.PTIPOTE_STATE.resetState();
      persistAndRender();
    });
  }

  function applyUrlPtipote() {
    const urlPtipote = window.PTIPOTE_STATE.initPtipoteFromUrlParams();
    if (!urlPtipote) return;

    state.ptipotes = [urlPtipote];
    state.selectedPtipoteUid = urlPtipote.uid;
    window.PTIPOTE_STATE.addJournal(state, `P'TIPOTE initialise depuis l'URL : ${urlPtipote.name}.`);
  }

  bindNavigation();
  applyUrlPtipote();
  persistAndRender();
})();
