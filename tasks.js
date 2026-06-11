(function () {
  function now() {
    return Date.now();
  }

  function startGather(state) {
    const ptipote = window.PTIPOTE_STATE.getSelectedPtipote(state);
    if (state.activeTask) return "Une tache est deja en cours.";
    if (ptipote.actionPoints <= 0) return `${ptipote.name} n'a plus de points d'action.`;

    window.PTIPOTE_STATE.updateSelectedPtipote(state, () => ({
      actionPoints: ptipote.actionPoints - 1,
      rest: Math.max(0, ptipote.rest - 8),
      wellbeing: Math.max(0, ptipote.wellbeing - 4)
    }));
    state.activeTask = {
      type: "gather",
      uid: ptipote.uid,
      startedAt: now(),
      endsAt: now() + 7000
    };
    window.PTIPOTE_STATE.addJournal(state, `${ptipote.name} part recolter a la Lisiere.`);
    window.PTIPOTE_STATE.advanceObjective(state, 1);
    return "";
  }

  function finishGather(state) {
    if (!state.activeTask || state.activeTask.type !== "gather") return "Aucune recolte a recuperer.";
    if (state.activeTask.endsAt > now()) return "La recolte n'est pas terminee.";

    const ptipote = window.PTIPOTE_STATE.getSelectedPtipote(state);
    state.resources.debris += 3;
    state.resources.organic += 2;
    window.PTIPOTE_STATE.updateSelectedPtipote(state, () => ({
      xp: ptipote.xp + 12
    }));
    state.activeTask = null;
    window.PTIPOTE_STATE.addJournal(state, `${ptipote.name} revient avec +3 Debris, +2 Organique et +12 XP.`);
    window.PTIPOTE_STATE.advanceObjective(state, 2);
    return "";
  }

  function craftMeal(state, requestedQuantity) {
    const requested = requestedQuantity === "infinite" ? 999 : Number(requestedQuantity);
    const quantity = state.tutorialCraftLimit ? 1 : requested;
    const possible = Math.min(quantity, Math.floor(state.resources.organic / 2));
    if (possible <= 0) return "Il faut 2 Organiques pour crafter 1 Repas.";

    state.resources.organic -= possible * 2;
    state.resources.meals += possible;
    state.tutorialCraftLimit = false;
    window.PTIPOTE_STATE.addJournal(state, `Atelier : ${possible} Repas crafte.`);
    window.PTIPOTE_STATE.advanceObjective(state, 3);
    return "";
  }

  function generateSecurity(state) {
    state.resources.security = Math.max(state.resources.security, 10);
    window.PTIPOTE_STATE.addJournal(state, "La Tour stabilise la Securite a 10.");
    return "";
  }

  function sellStock(state, stockKey) {
    const prices = { debris: 1, organic: 2, meals: 5 };
    const amount = state.resources[stockKey] || 0;
    if (!prices[stockKey] || amount <= 0) return "Aucun stock vendable selectionne.";

    state.resources[stockKey] = 0;
    state.resources.credits += amount * prices[stockKey];
    window.PTIPOTE_STATE.addJournal(state, `Marche : vente auto de ${amount} ${stockKey} pour ${amount * prices[stockKey]} credits.`);
    return "";
  }

  function restAtHome(state) {
    const ptipote = window.PTIPOTE_STATE.getSelectedPtipote(state);
    window.PTIPOTE_STATE.updateSelectedPtipote(state, () => ({
      rest: Math.min(100, ptipote.rest + 26),
      actionPoints: Math.min(3, ptipote.actionPoints + 1)
    }));
    window.PTIPOTE_STATE.addJournal(state, `${ptipote.name} se repose a la Maison.`);
    return "";
  }

  function feedAtHome(state) {
    const ptipote = window.PTIPOTE_STATE.getSelectedPtipote(state);
    if (state.resources.meals <= 0) return "Aucun Repas disponible.";

    state.resources.meals -= 1;
    window.PTIPOTE_STATE.updateSelectedPtipote(state, () => ({
      wellbeing: Math.min(100, ptipote.wellbeing + 24)
    }));
    window.PTIPOTE_STATE.addJournal(state, `${ptipote.name} mange un Repas et va mieux.`);
    window.PTIPOTE_STATE.advanceObjective(state, 4);
    return "";
  }

  function applyProgression(state) {
    const ptipote = window.PTIPOTE_STATE.getSelectedPtipote(state);
    if (ptipote.xp < 20) return "Il faut 20 XP pour gagner un niveau dans ce proto.";

    window.PTIPOTE_STATE.updateSelectedPtipote(state, () => ({
      level: ptipote.level + 1,
      xp: ptipote.xp - 20,
      wellbeing: Math.min(100, ptipote.wellbeing + 8)
    }));
    window.PTIPOTE_STATE.addJournal(state, `${ptipote.name} progresse au niveau ${ptipote.level + 1}.`);
    window.PTIPOTE_STATE.advanceObjective(state, 5);
    return "";
  }

  window.PTIPOTE_TASKS = {
    startGather,
    finishGather,
    craftMeal,
    generateSecurity,
    sellStock,
    restAtHome,
    feedAtHome,
    applyProgression
  };
})();
