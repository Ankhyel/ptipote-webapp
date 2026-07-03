(function () {
  const STORAGE_KEY = "ptipote_zone0_proto1_state";
  const URL_FIELDS = ["uid", "name", "type", "level", "xp"];

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function defaultState() {
    const data = window.PTIPOTE_DATA;
    return {
      selectedTab: "island",
      selectedBuilding: "kernel",
      selectedPtipoteUid: data.ptipotes[0].uid,
      ptipotes: clone(data.ptipotes),
      resources: clone(data.resources),
      activeTask: null,
      tutorialCraftLimit: true,
      objectiveIndex: 0,
      journal: [
        {
          time: Date.now(),
          text: "Proto initialise : choisis un P'TIPOTE pour commencer."
        }
      ]
    };
  }

  function loadState() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (!saved) return defaultState();
      return mergeState(defaultState(), JSON.parse(saved));
    } catch (_) {
      return defaultState();
    }
  }

  function mergeState(base, saved) {
    const next = {
      ...base,
      ...saved,
      resources: { ...base.resources, ...(saved.resources || {}) },
      ptipotes: Array.isArray(saved.ptipotes) ? saved.ptipotes : base.ptipotes,
      journal: Array.isArray(saved.journal) ? saved.journal : base.journal
    };
    if (next.selectedBuilding === "bio") next.selectedBuilding = "kernel";
    return next;
  }

  function saveState(state) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  function getSelectedPtipote(state) {
    return state.ptipotes.find((ptipote) => ptipote.uid === state.selectedPtipoteUid) || state.ptipotes[0];
  }

  function updateSelectedPtipote(state, updater) {
    const uid = getSelectedPtipote(state).uid;
    state.ptipotes = state.ptipotes.map((ptipote) => {
      if (ptipote.uid !== uid) return ptipote;
      return { ...ptipote, ...updater(ptipote) };
    });
  }

  function addJournal(state, text) {
    state.journal.unshift({ time: Date.now(), text });
    state.journal = state.journal.slice(0, 30);
  }

  function advanceObjective(state, index) {
    if (state.objectiveIndex <= index) {
      state.objectiveIndex = Math.min(index + 1, window.PTIPOTE_DATA.objectives.length - 1);
    }
  }

  function resetState() {
    localStorage.removeItem(STORAGE_KEY);
    return defaultState();
  }

  function initPtipoteFromUrlParams(paramsLike) {
    const params = paramsLike || new URLSearchParams(window.location.search);
    const hasAnyField = URL_FIELDS.some((field) => params.has(field));
    if (!hasAnyField) return null;

    const fallback = window.PTIPOTE_DATA.ptipotes[0];
    return {
      ...fallback,
      uid: params.get("uid") || fallback.uid,
      name: params.get("name") || fallback.name,
      type: params.get("type") || fallback.type,
      level: Number(params.get("level") || fallback.level),
      xp: Number(params.get("xp") || fallback.xp)
    };
  }

  window.PTIPOTE_STATE = {
    loadState,
    saveState,
    resetState,
    getSelectedPtipote,
    updateSelectedPtipote,
    addJournal,
    advanceObjective,
    initPtipoteFromUrlParams
  };
})();
