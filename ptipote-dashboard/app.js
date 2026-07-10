import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import {
  collection,
  collectionGroup,
  doc,
  getCountFromServer,
  getDoc,
  getFirestore,
  query,
  where,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js";

const BOOTSTRAP_ADMIN_UIDS = new Set(["taNxWXLMh2gJx5CHgmBB8Phl4c93"]);

const firebaseConfig = {
  apiKey: "AIzaSyCol40AnP-uim5rxMT63ZzuO-E2dfoFTpQ",
  authDomain: "ptipote-13508.firebaseapp.com",
  projectId: "ptipote-13508",
  storageBucket: "ptipote-13508.firebasestorage.app",
  messagingSenderId: "141039369930",
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const provider = new GoogleAuthProvider();
let currentDashboardRole = "";
let ptipoteStatsConfig = {};
let campHeartConfig = {};
let lisiereForageConfig = {};

const PTIPOTE_STATS_STORAGE_KEY = "ptipote_stats_config_v1";
const PTIPOTE_STATS_FIELDS = [
  "maxVitality",
  "vitalityRecoveryPerMinute",
  "minVitalityBeforeAutoRest",
  "baseHappiness",
  "maxHappiness",
  "happinessDecayPerHour",
  "xpRequiredBase",
  "xpRequiredMultiplier",
  "baseEVG",
  "baseForageEfficiency",
  "baseSafetyContribution",
  "baseMarketContribution",
];

const ids = [
  "authState",
  "authDetail",
  "authButton",
  "refreshButton",
  "notice",
  "usersCount",
  "usersHint",
  "figurinesCount",
  "figurinesHint",
  "publicFigurinesCount",
  "publicFigurinesHint",
  "transferRequestsCount",
  "transferRequestsHint",
  "transferPending",
  "transferAccepted",
  "transferConfirmed",
  "transferRefused",
  "statPtipoteForm",
  "statPtipoteStatus",
  "resetPtipoteStatsButton",
  "exportPtipoteStatsButton",
  "campHeartStatus",
  "campHeartStageList",
  "exportCampHeartButton",
  "lisiereForageStatus",
  "lisiereForageList",
  "exportLisiereForageButton",
];

const el = Object.fromEntries(ids.map((id) => [id, document.getElementById(id)]));
const dashboardTabButtons = Array.from(document.querySelectorAll("[data-dashboard-tab]"));
const dashboardPanels = Array.from(document.querySelectorAll("[data-dashboard-panel]"));

function setupDashboardTabs() {
  dashboardTabButtons.forEach((button) => {
    button.addEventListener("click", () => {
      const target = button.dataset.dashboardTab;
      dashboardTabButtons.forEach((item) => {
        item.classList.toggle("active", item === button);
      });
      dashboardPanels.forEach((panel) => {
        panel.classList.toggle("active", panel.dataset.dashboardPanel === target);
      });
    });
  });
}

function setNotice(title, message, isError = false) {
  el.notice.classList.toggle("error", isError);
  el.notice.innerHTML = `<strong>${escapeHtml(title)}</strong><span>${escapeHtml(message)}</span>`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function setValue(valueId, hintId, result) {
  if (result.ok) {
    el[valueId].textContent = new Intl.NumberFormat("fr-FR").format(result.count);
    el[hintId].textContent = result.label;
    return;
  }

  el[valueId].textContent = "-";
  el[hintId].textContent = result.message;
}

async function safeCount(label, ref) {
  try {
    const snapshot = await getCountFromServer(ref);
    return { ok: true, count: snapshot.data().count, label };
  } catch (error) {
    return {
      ok: false,
      count: null,
      label,
      message: readableFirebaseError(error),
      error,
    };
  }
}

function readableFirebaseError(error) {
  if (error?.code === "permission-denied") return "Acces refuse par les rules";
  if (error?.code === "unauthenticated") return "Connexion requise";
  return error?.message || "Lecture impossible";
}

function clearStats() {
  setValue("usersCount", "usersHint", { ok: false, message: "Reserve admin/dev" });
  setValue("figurinesCount", "figurinesHint", { ok: false, message: "Reserve admin/dev" });
  setValue("publicFigurinesCount", "publicFigurinesHint", { ok: false, message: "Reserve admin/dev" });
  setValue("transferRequestsCount", "transferRequestsHint", { ok: false, message: "Reserve admin/dev" });
  el.transferPending.textContent = "-";
  el.transferAccepted.textContent = "-";
  el.transferConfirmed.textContent = "-";
  el.transferRefused.textContent = "-";
}

async function getDashboardRole(user) {
  if (BOOTSTRAP_ADMIN_UIDS.has(user.uid)) {
    return "admin";
  }

  const snapshot = await getDoc(doc(db, "users", user.uid));
  const role = snapshot.exists() ? snapshot.data().role : "";
  return role === "admin" || role === "dev" ? role : "";
}

async function loadStats(role) {
  if (!auth.currentUser) {
    setNotice("Connexion requise", "Les compteurs sont lances apres authentification Google.", false);
    return;
  }

  if (!role) {
    clearStats();
    setNotice("Acces refuse", "Ton document utilisateur doit avoir le role admin ou dev.", true);
    return;
  }

  setLoading(true);
  setNotice("Lecture en cours", "Comptage Firestore via agregations count(), sans exporter les documents.", false);

  const [users, figurines, publicFigurines, transferRequests, pending, accepted, confirmed, refused] =
    await Promise.all([
      safeCount("users", collection(db, "users")),
      safeCount("users/*/figurines", collectionGroup(db, "figurines")),
      safeCount("publicFigurines", collection(db, "publicFigurines")),
      safeCount("transferRequests", collection(db, "transferRequests")),
      safeCount("status == pending", query(collection(db, "transferRequests"), where("status", "==", "pending"))),
      safeCount("status == accepted", query(collection(db, "transferRequests"), where("status", "==", "accepted"))),
      safeCount("status == confirmed", query(collection(db, "transferRequests"), where("status", "==", "confirmed"))),
      safeCount("status == refused", query(collection(db, "transferRequests"), where("status", "==", "refused"))),
    ]);

  setValue("usersCount", "usersHint", users);
  setValue("figurinesCount", "figurinesHint", figurines);
  setValue("publicFigurinesCount", "publicFigurinesHint", publicFigurines);
  setValue("transferRequestsCount", "transferRequestsHint", transferRequests);
  el.transferPending.textContent = pending.ok ? pending.count : "-";
  el.transferAccepted.textContent = accepted.ok ? accepted.count : "-";
  el.transferConfirmed.textContent = confirmed.ok ? confirmed.count : "-";
  el.transferRefused.textContent = refused.ok ? refused.count : "-";

  const failures = [users, figurines, publicFigurines, transferRequests, pending, accepted, confirmed, refused]
    .filter((result) => !result.ok);

  if (failures.length) {
    setNotice(
      "Rules a completer",
      `${failures.length} compteur(s) refuse(s) ou indisponible(s). Voir README du dashboard pour les rules admin.`,
      true,
    );
  } else {
    setNotice("Stats a jour", `Derniere lecture: ${new Date().toLocaleString("fr-FR")}.`, false);
  }

  setLoading(false);
}

function setLoading(isLoading) {
  el.refreshButton.disabled = isLoading;
  el.authButton.disabled = isLoading;
}

async function loadPtipoteStatsConfig({ reset = false } = {}) {
  try {
    const response = await fetch("./ptipote-stats-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const baseConfig = await response.json();
    const savedConfig = reset
      ? null
      : JSON.parse(localStorage.getItem(PTIPOTE_STATS_STORAGE_KEY) || "null");
    ptipoteStatsConfig = { ...baseConfig, ...(savedConfig || {}) };
    if (reset) {
      localStorage.removeItem(PTIPOTE_STATS_STORAGE_KEY);
    }
    renderPtipoteStatsForm();
    el.statPtipoteStatus.textContent = reset
      ? "Valeurs rechargees depuis le JSON versionne."
      : "Valeurs chargees. Les modifications restent locales jusqu'a integration Firestore/app.";
  } catch (error) {
    el.statPtipoteStatus.textContent = `Configuration Stat Ptipote illisible: ${error.message}`;
  }
}

function renderPtipoteStatsForm() {
  el.statPtipoteForm.innerHTML = PTIPOTE_STATS_FIELDS.map((field) => `
    <div class="stat-field">
      <label for="stat-${field}">${escapeHtml(field)}</label>
      <input id="stat-${field}" name="${escapeHtml(field)}" type="number" step="0.01" value="${escapeHtml(ptipoteStatsConfig[field] ?? "")}">
    </div>
  `).join("") + `
    <div class="stat-field stat-field-wide">
      <label>XP requis par niveau</label>
      <p id="xpRequiredPreview"></p>
    </div>
  `;
  renderXpRequiredPreview();

  el.statPtipoteForm.querySelectorAll("input").forEach((input) => {
    input.addEventListener("input", () => {
      const value = Number(input.value);
      ptipoteStatsConfig[input.name] = Number.isFinite(value) ? value : input.value;
      localStorage.setItem(PTIPOTE_STATS_STORAGE_KEY, JSON.stringify(ptipoteStatsConfig, null, 2));
      renderXpRequiredPreview();
      el.statPtipoteStatus.textContent = "Modification locale sauvegardee. Exporter le JSON pour synchroniser le fichier source.";
    });
  });
}

function renderXpRequiredPreview() {
  const preview = document.getElementById("xpRequiredPreview");
  if (!preview) return;
  const xpBase = Number(ptipoteStatsConfig.xpRequiredBase || 100);
  const xpMultiplier = Number(ptipoteStatsConfig.xpRequiredMultiplier || 1.25);
  preview.textContent = [1, 2, 3, 4, 5]
    .map((level) => `Niv. ${level}→${level + 1}: ${Math.round(xpBase * Math.pow(xpMultiplier, level - 1))} XP`)
    .join(" · ");
}

function exportPtipoteStatsConfig() {
  const blob = new Blob([JSON.stringify(ptipoteStatsConfig, null, 2)], {
    type: "application/json",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "ptipote-stats-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

async function loadCampHeartConfig() {
  try {
    const response = await fetch("./camp-heart-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    campHeartConfig = await response.json();
    renderCampHeartConfig();
    el.campHeartStatus.textContent = "Paliers charges depuis le JSON versionne.";
  } catch (error) {
    el.campHeartStatus.textContent = `Configuration Cœur du Camp illisible: ${error.message}`;
  }
}

function renderCampHeartConfig() {
  const stages = Array.isArray(campHeartConfig.stages) ? campHeartConfig.stages : [];
  el.campHeartStageList.innerHTML = stages.map((stage) => `
    <div class="stage-row">
      <div>
        <strong>Niv. ${escapeHtml(stage.level)} - ${escapeHtml(stage.label)}</strong>
        <span>${escapeHtml(stage.populationLabel)} · ${escapeHtml(stage.activePtipoteComfortLimit)} P'TIPOTE(s) confort · bonheur +${escapeHtml(stage.refugeHappinessBonus)}</span>
      </div>
      <strong>${stage.xpRequiredForNextLevel == null ? "max V1" : `${escapeHtml(stage.xpRequiredForNextLevel)} XP`}</strong>
    </div>
  `).join("");
}

async function loadLisiereForageConfig() {
  try {
    const response = await fetch("./lisiere-forage-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    lisiereForageConfig = await response.json();
    renderLisiereForageConfig();
    el.lisiereForageStatus.textContent = "Configuration Lisière chargée depuis le JSON versionné.";
  } catch (error) {
    el.lisiereForageStatus.textContent = "Configuration Lisière illisible: " + error.message;
  }
}

function renderLisiereForageConfig() {
  const durations = Array.isArray(lisiereForageConfig.durations) ? lisiereForageConfig.durations : [];
  const intensities = Array.isArray(lisiereForageConfig.intensities) ? lisiereForageConfig.intensities : [];
  const biomes = Array.isArray(lisiereForageConfig.biomes) ? lisiereForageConfig.biomes : [];
  const rows = [];
  rows.push('<div class="stage-row"><div><strong>Temps</strong><span>Multiplicateur test x' + escapeHtml(lisiereForageConfig.forageTimeScale) + ' · ' + durations.map((item) => escapeHtml(item.label) + ' => ' + escapeHtml(item.realMinutes) + ' min').join(' · ') + '</span></div><strong>durées</strong></div>');
  rows.push('<div class="stage-row"><div><strong>Intensités</strong><span>' + intensities.map((item) => escapeHtml(item.label) + ' x' + escapeHtml(item.rewardMultiplier) + ' risque ' + escapeHtml(item.riskModifierPercent) + '%').join(' · ') + '</span></div><strong>coûts</strong></div>');
  const xpByDuration = lisiereForageConfig.xpGainByDuration || {};
  const xpByIntensity = lisiereForageConfig.intensityXpMultiplier || {};
  rows.push('<div class="stage-row"><div><strong>XP mission</strong><span>Base par durée: ' + Object.entries(xpByDuration).map(([key, value]) => escapeHtml(key) + ' +' + escapeHtml(value)).join(' · ') + ' | intensité: ' + Object.entries(xpByIntensity).map(([key, value]) => escapeHtml(key) + ' x' + escapeHtml(value)).join(' · ') + '</span></div><strong>progression</strong></div>');
  biomes.forEach((biome) => {
    const organic = biome.rewards && biome.rewards.Organique ? biome.rewards.Organique : 0;
    const mineral = biome.rewards && biome.rewards["Minéral"] ? biome.rewards["Minéral"] : 0;
    rows.push('<div class="stage-row"><div><strong>' + escapeHtml(biome.label) + '</strong><span>Risque ' + escapeHtml(biome.baseRiskPercent) + '% · Organique ' + escapeHtml(organic) + ' · Minéral ' + escapeHtml(mineral) + '</span></div><strong>biome</strong></div>');
  });
  el.lisiereForageList.innerHTML = rows.join('');
}

function exportLisiereForageConfig() {
  const blob = new Blob([JSON.stringify(lisiereForageConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "lisiere-forage-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

function exportCampHeartConfig() {
  const blob = new Blob([JSON.stringify(campHeartConfig, null, 2)], {
    type: "application/json",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "camp-heart-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

async function handleAuthClick() {
  if (auth.currentUser) {
    await signOut(auth);
    return;
  }

  await signInWithPopup(auth, provider);
}

onAuthStateChanged(auth, (user) => {
  if (!user) {
    currentDashboardRole = "";
    el.authState.textContent = "Non connecte";
    el.authDetail.textContent = "Acces reserve admin/dev";
    el.authButton.textContent = "Connexion";
    clearStats();
    return;
  }

  el.authState.textContent = user.displayName || user.email || "Compte Firebase";
  el.authButton.textContent = "Deconnexion";
  getDashboardRole(user)
    .then((role) => {
      currentDashboardRole = role;
      el.authDetail.textContent = role ? `${user.email || user.uid} - ${role}` : user.email || user.uid;
      loadStats(role);
    })
    .catch((error) => {
      currentDashboardRole = "";
      clearStats();
      el.authDetail.textContent = user.email || user.uid;
      setNotice("Role illisible", readableFirebaseError(error), true);
    });
});

el.authButton.addEventListener("click", () => {
  handleAuthClick().catch((error) => {
    setNotice("Auth impossible", readableFirebaseError(error), true);
  });
});

el.refreshButton.addEventListener("click", () => {
  loadStats(currentDashboardRole);
});

el.resetPtipoteStatsButton.addEventListener("click", () => {
  loadPtipoteStatsConfig({ reset: true });
});

el.exportPtipoteStatsButton.addEventListener("click", () => {
  exportPtipoteStatsConfig();
});

el.exportCampHeartButton.addEventListener("click", () => {
  exportCampHeartConfig();
});

el.exportLisiereForageButton.addEventListener("click", () => {
  exportLisiereForageConfig();
});

setupDashboardTabs();
loadPtipoteStatsConfig();
loadCampHeartConfig();
loadLisiereForageConfig();
