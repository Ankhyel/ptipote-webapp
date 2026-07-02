(function () {
  function pct(value) {
    return Math.max(0, Math.min(100, Number(value) || 0));
  }

  function formatTime(timestamp) {
    return new Date(timestamp).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  }

  function renderPtipotes(state, onSelect) {
    const list = document.getElementById("ptipoteList");
    list.innerHTML = state.ptipotes.map((ptipote) => `
      <article class="ptipote-card ${state.selectedPtipoteUid === ptipote.uid ? "selected" : ""}">
        <p class="eyebrow">${ptipote.uid}</p>
        <h3>${ptipote.name}</h3>
        <p>${ptipote.species} - ${ptipote.type} - Niveau ${ptipote.level}</p>
        <div class="stat-grid">
          <div class="small-stat">XP <b>${ptipote.xp}</b></div>
          <div class="small-stat">PA <b>${ptipote.actionPoints}</b></div>
        </div>
        <p>Bien-etre</p>
        <div class="meter"><span style="--value:${pct(ptipote.wellbeing)}%"></span></div>
        <p>Repos</p>
        <div class="meter"><span style="--value:${pct(ptipote.rest)}%"></span></div>
        <div class="action-row">
          <button class="primary-button" type="button" data-ptipote="${ptipote.uid}">Choisir</button>
        </div>
      </article>
    `).join("");

    list.querySelectorAll("[data-ptipote]").forEach((button) => {
      button.addEventListener("click", () => onSelect(button.dataset.ptipote));
    });
  }

  function renderJournal(state) {
    document.getElementById("currentObjective").textContent = window.PTIPOTE_DATA.objectives[state.objectiveIndex];
    const list = document.getElementById("journalList");
    list.innerHTML = state.journal.length ? state.journal.map((entry) => `
      <article class="journal-entry">
        <p class="eyebrow">${formatTime(entry.time)}</p>
        <p>${entry.text}</p>
      </article>
    `).join("") : `<div class="empty-state">Aucun evenement.</div>`;
  }

  function renderSheet(state, handlers) {
    const sheet = document.getElementById("bottomSheet");
    const content = document.getElementById("sheetContent");
    const building = window.PTIPOTE_DATA.buildings.find((item) => item.id === state.selectedBuilding);
    if (!building) {
      sheet.classList.remove("open");
      return;
    }

    sheet.classList.add("open");
    content.innerHTML = panelHtml(building, state);
    bindPanelActions(content, handlers);
  }

  function panelHtml(building, state) {
    const ptipote = window.PTIPOTE_STATE.getSelectedPtipote(state);
    const taskReady = state.activeTask && state.activeTask.endsAt <= Date.now();
    const remaining = state.activeTask ? Math.max(0, Math.ceil((state.activeTask.endsAt - Date.now()) / 1000)) : 0;
    const header = `
      <article class="sheet-card">
        <p class="eyebrow">${building.name}</p>
        <h3>${building.summary}</h3>
    `;
    const footer = `</article>`;

    if (building.id === "bio") {
      return `${header}
        <p>${ptipote.name} selectionne. UID ${ptipote.uid}, espece ${ptipote.species}, type ${ptipote.type}.</p>
        <div class="action-row"><button class="primary-button" type="button" data-action="progress">Appliquer progression</button></div>
      ${footer}`;
    }

    if (building.id === "forest") {
      return `${header}
        <p>${state.activeTask ? `Recolte en cours : ${remaining}s restantes.` : "Envoyer le P'TIPOTE recolter Debris + Organique + XP."}</p>
        <div class="action-row">
          <button class="primary-button" type="button" data-action="gather" ${state.activeTask ? "disabled" : ""}>Envoyer recolter</button>
          <button class="secondary-button" type="button" data-action="finishGather" ${!taskReady ? "disabled" : ""}>Recuperer</button>
        </div>
      ${footer}`;
    }

    if (building.id === "workshop") {
      return `${header}
        <p>Recette Repas : 2 Organiques. Le tuto limite le premier craft a 1.</p>
        <div class="quantity-row">
          <button class="quantity-button" type="button" data-action="craft" data-qty="1">1</button>
          <button class="quantity-button" type="button" data-action="craft" data-qty="5">5</button>
          <button class="quantity-button" type="button" data-action="craft" data-qty="10">10</button>
          <button class="quantity-button" type="button" data-action="craft" data-qty="infinite">Infini</button>
        </div>
      ${footer}`;
    }

    if (building.id === "tower") {
      return `${header}
        <p>Securite actuelle : ${state.resources.security}. Stable cible : 10.</p>
        <div class="action-row"><button class="primary-button" type="button" data-action="security">Generer Securite stable</button></div>
      ${footer}`;
    }

    if (building.id === "market") {
      return `${header}
        <select class="select-field" data-market-stock>
          <option value="debris">Debris (${state.resources.debris})</option>
          <option value="organic">Organique (${state.resources.organic})</option>
          <option value="meals">Repas (${state.resources.meals})</option>
        </select>
        <div class="action-row"><button class="primary-button" type="button" data-action="sell">Vendre automatiquement</button></div>
      ${footer}`;
    }

    return `${header}
      <p>Chambres : 1 / Repas : ${state.resources.meals}. Repos ${ptipote.rest}, bien-etre ${ptipote.wellbeing}.</p>
      <div class="action-row">
        <button class="primary-button" type="button" data-action="rest">Repos</button>
        <button class="secondary-button" type="button" data-action="feed">Repas</button>
      </div>
    ${footer}`;
  }

  function bindPanelActions(root, handlers) {
    root.querySelectorAll("[data-action]").forEach((button) => {
      button.addEventListener("click", () => {
        const action = button.dataset.action;
        const qty = button.dataset.qty;
        const stock = root.querySelector("[data-market-stock]")?.value;
        handlers.onAction(action, { qty, stock });
      });
    });
  }

  window.PTIPOTE_UI_PANELS = {
    renderPtipotes,
    renderJournal,
    renderSheet
  };
})();
