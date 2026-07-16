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
let kernelConfig = {};
let lisiereForageConfig = {};
let securityTowerConfig = {};
let fablabConfig = {};
let recyclerConfig = {};
let craftConfig = {};

const PTIPOTE_STATS_STORAGE_KEY = "ptipote_stats_config_v1";
const CRAFT_STORAGE_KEY = "craft_config_v1";
const PTIPOTE_STATS_FIELDS = [
  "maxVitality",
  "vitalityRecoveryPerMinute",
  "alcoveVitalityRecoveryPerMinute",
  "naturalVitalityRecoveryMinutes",
  "happyVitalityRecoveryPerMinute",
  "minVitalityBeforeAutoRest",
  "minimumMissionVitality",
  "maxRest",
  "sleepRestRecoveryPerMinute",
  "awakeRestLossMinutes",
  "missionRestLossRatio",
  "wellRestedThreshold",
  "restedThreshold",
  "tiredThreshold",
  "exhaustedThreshold",
  "wellRestedXpBonus",
  "wellRestedRewardBonus",
  "tiredXpPenalty",
  "tiredRewardPenalty",
  "indigestionXpPenalty",
  "maxHunger",
  "maxOverfedHunger",
  "baseHunger",
  "hungerDecayMinutes",
  "missionHungerCostRatio",
  "wellFedHungerThreshold",
  "wellFedVitalityRecoveryBonus",
  "indigestionHungerThreshold",
  "indigestionVitalityRecoveryPenalty",
  "happyVitalityThreshold",
  "happyHungerThreshold",
  "cuddleCooldownMinutes",
  "cuddleCareDurationMinutes",
  "vitalityBubbleThreshold",
  "hungerBubbleThreshold",
  "cuddleBubbleWarningMinutes",
  "needBubbleMinIntervalMinutes",
  "needBubbleMaxIntervalMinutes",
  "needBubbleDisplayDurationSeconds",
  "happyNeedsRequired",
  "okayNeedsRequired",
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
  "kernelStatus",
  "kernelConfigList",
  "exportKernelButton",
  "kernelProgressEditor",
  "exportKernelProgressButton",
  "campHeartStatus",
  "campHeartStageList",
  "exportCampHeartButton",
  "lisiereForageStatus",
  "lisiereForageList",
  "exportLisiereForageButton",
  "securityTowerStatus",
  "securityTowerConfigList",
  "exportSecurityTowerButton",
  "fablabStatus",
  "fablabConfigList",
  "exportFablabButton",
  "recyclerStatus",
  "recyclerConfigList",
  "exportRecyclerButton",
  "craftStatus",
  "craftRecipeList",
  "craftRecipeForm",
  "exportCraftButton",
  "campGeneratorEditor",
  "workshopEditor",
  "marketEditor",
  "towerOperationsEditor",
  "buildingArchitectureEditor",
  "housingEditor",
  "exportCampGeneratorButton",
  "exportWorkshopButton",
  "exportTowerOperationsButton",
  "exportMarketButton",
  "exportBuildingArchitectureButton",
  "exportHousingButton",
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

async function loadKernelConfig() {
  try {
    const response = await fetch("./kernel-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    kernelConfig = await response.json();
    renderKernelConfig();
    el.kernelStatus.textContent = "Configuration Camp / Kernel chargée depuis le JSON versionné.";
  } catch (error) {
    el.kernelStatus.textContent = `Configuration Kernel illisible: ${error.message}`;
  }
}

function renderKernelConfig() {
  const capacity = kernelConfig.populationCapacityByCampHeartLevel || {};
  const missions = Array.isArray(kernelConfig.missions) ? kernelConfig.missions : [];
  const plans = Array.isArray(kernelConfig.plans) ? kernelConfig.plans : [];
  const rows = [
    ["Population départ", kernelConfig.startingPopulation],
    ["Bien-être départ", `${kernelConfig.startingWellbeing}%`],
    ["Bio-batteries départ", kernelConfig.startingBioBatteries],
    ["Demandes secondaires max", kernelConfig.maxRefugeRequests],
    ["Couleurs HUD", `rouge < ${kernelConfig.wellbeingRedThreshold} · orange < ${kernelConfig.wellbeingOrangeThreshold} · vert au-delà`],
    ["Capacité population", Object.entries(capacity).map(([level, value]) => `Cœur ${level}: ${value}`).join(" · ")],
  ];
  const missionRows = missions.map((mission) => [
    `Mission: ${mission.title}`,
    `${mission.type} · ${mission.conditionType} ${mission.requiredAmount} · +${mission.populationReward} habitant(s) · +${mission.bioBatteryReward || 0} bio-batterie(s)`,
  ]);
  const planRows = plans.map((plan) => [
    `Plan: ${plan.title}`,
    `Cœur requis ${plan.requiredCampHeartLevel} · ${plan.description}`,
  ]);
  el.kernelConfigList.innerHTML = [...rows, ...missionRows, ...planRows].map(([label, value]) => `
    <div class="stage-row">
      <div><strong>${escapeHtml(label)}</strong><span>${escapeHtml(value)}</span></div>
      <strong>Kernel</strong>
    </div>
  `).join("");
}

function exportKernelConfig() {
  const blob = new Blob([JSON.stringify(kernelConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "kernel-config.json";
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
  rows.push('<div class="stage-row"><div><strong>Formule danger</strong><span>Minimum ' + escapeHtml(lisiereForageConfig.minimumMissionRisk) + '% · réduction sécurité x' + escapeHtml(lisiereForageConfig.securityRiskReductionFactor) + '</span></div><strong>sécurité</strong></div>');
  biomes.forEach((biome) => {
    const organic = biome.rewards && biome.rewards.Organique ? biome.rewards.Organique : 0;
    const mineral = biome.rewards && biome.rewards["Minéral"] ? biome.rewards["Minéral"] : 0;
    const hazards = Array.isArray(biome.hazards) ? biome.hazards.join(', ') : '';
    rows.push('<div class="stage-row"><div><strong>' + escapeHtml(biome.label) + '</strong><span>Risque ' + escapeHtml(biome.baseRiskPercent) + '% · Organique ' + escapeHtml(organic) + ' · Minéral ' + escapeHtml(mineral) + ' · dangers ' + escapeHtml(hazards) + '</span></div><strong>biome</strong></div>');
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

async function loadSecurityTowerConfig() {
  try {
    const response = await fetch("./security-tower-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    securityTowerConfig = await response.json();
    renderSecurityTowerConfig();
    el.securityTowerStatus.textContent = "Configuration Tour chargée depuis le JSON versionné.";
  } catch (error) {
    el.securityTowerStatus.textContent = "Configuration Tour illisible: " + error.message;
  }
}

function renderSecurityTowerConfig() {
  const slots = securityTowerConfig.slotsByLevel || {};
  const labels = Array.isArray(securityTowerConfig.dangerLabels) ? securityTowerConfig.dangerLabels : [];
  const rows = [
    ["Coût Organique", securityTowerConfig.constructionCostOrganic],
    ["Coût Minéral", securityTowerConfig.constructionCostMineral],
    ["Cœur requis", securityTowerConfig.requiredCampHeartLevel],
    ["Sécurité max", securityTowerConfig.maxSecurity],
    ["Sécurité initiale", securityTowerConfig.initialSecurity],
    ["Gain sécurité / tick", securityTowerConfig.securityGainPerTick],
    ["Durée tick", `${securityTowerConfig.tickMinutes} min`],
    ["Coût Vitalité / tick", securityTowerConfig.vitalityCostPerTick],
    ["Décroissance sécurité", securityTowerConfig.securityDecayPerTick],
    ["Recharge manuelle", `+${securityTowerConfig.manualRechargeSecurityGain} sécurité`],
    ["Cooldown recharge", `${securityTowerConfig.manualRechargeCooldownMinutes} min`],
    ["Risque minimum", `${securityTowerConfig.minimumMissionRisk}%`],
    ["Coefficient réduction", securityTowerConfig.securityRiskReductionFactor],
    ["Slots", Object.entries(slots).map(([level, count]) => `niv. ${level}: ${count}`).join(" · ")],
    ["Labels danger", labels.map((item) => `${item.label} ${item.min}-${item.max}%`).join(" · ")],
  ];
  el.securityTowerConfigList.innerHTML = rows.map(([label, value]) => `
    <div class="stage-row">
      <div><strong>${escapeHtml(label)}</strong><span>${escapeHtml(value)}</span></div>
      <strong>Tour</strong>
    </div>
  `).join("");
}

function exportSecurityTowerConfig() {
  const blob = new Blob([JSON.stringify(securityTowerConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "security-tower-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

async function loadFablabConfig() {
  try {
    const response = await fetch("./fablab-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    fablabConfig = await response.json();
    renderFablabConfig();
    el.fablabStatus.textContent = "Configuration Fablab chargée depuis le JSON versionné.";
  } catch (error) {
    el.fablabStatus.textContent = "Configuration Fablab illisible: " + error.message;
  }
}

function renderFablabConfig() {
  const rows = [
    ["Construction Organique niv. 1", fablabConfig.constructionCostLevel1Organic],
    ["Construction Minéral niv. 1", fablabConfig.constructionCostLevel1Mineral],
    ["Capacité stock de base", fablabConfig.baseGlobalStockCapacity],
    ["Bonus stock par niveau", fablabConfig.stockCapacityBonusPerFablabLevel],
    ["Niveau max Fablab", fablabConfig.fablabMaxLevel],
    ["Niveau max Cuisine", fablabConfig.cuisineMaxLevel],
    ["Niveau max Atelier", fablabConfig.atelierMaxLevel],
    ["Niveau max Recycleur", fablabConfig.recyclerMaxLevel],
    ["Amélioration Cuisine", `${fablabConfig.cuisineUpgradeOrganic} Organique · ${fablabConfig.cuisineUpgradeMineral} Minéral`],
    ["Amélioration Atelier", `${fablabConfig.atelierUpgradeOrganic} Organique · ${fablabConfig.atelierUpgradeMineral} Minéral`],
    ["Amélioration Recycleur", `${fablabConfig.recyclerUpgradeOrganic} Organique · ${fablabConfig.recyclerUpgradeMineral} Minéral`],
    ["Durée amélioration unité", `${fablabConfig.unitUpgradeDurationMinutes} min`],
    ["Cuisine active niveau", fablabConfig.cuisineUnlockLevel],
    ["Atelier requis Cœur", fablabConfig.atelierUnlockCampHeartLevel],
    ["Recycleur requis Cœur", fablabConfig.recyclerUnlockCampHeartLevel],
  ];
  el.fablabConfigList.innerHTML = rows.map(([label, value]) => `
    <div class="stage-row">
      <div><strong>${escapeHtml(label)}</strong><span>${escapeHtml(value)}</span></div>
      <strong>V1</strong>
    </div>
  `).join("");
}

async function loadRecyclerConfig() {
  try {
    const response = await fetch("./waste-recycler-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    recyclerConfig = await response.json();
    const rows = [
      ["Cycle déchets refuge", `${recyclerConfig.wasteGenerationCycleMinutes} min`],
      ["Population par Déchet", recyclerConfig.populationPerWasteUnit],
      ["Bâtiments par Déchet", recyclerConfig.buildingsPerWasteUnit],
      ["Déchets Lisière", `${recyclerConfig.wasteRewardMinimumPercent}–${recyclerConfig.wasteRewardMaximumPercent}%`],
      ["Cœur requis", recyclerConfig.recyclerUnlockCampHeartLevel],
      ["Niveau initial / maximum", `${recyclerConfig.initialRecyclerLevel} / ${recyclerConfig.recyclerMaxLevel}`],
      ["Cuve de base", recyclerConfig.baseWasteTankCapacity],
      ["Coût niveau 1", `${recyclerConfig.baseWasteRequired} Déchets → ${recyclerConfig.outputResourcesPerCycle} ressources`],
      ["Énergie / Bio-batterie", recyclerConfig.energyUnitsPerBioBattery],
      ["Coût par cycle", recyclerConfig.energyCostPerCycle],
      ["Stock sortie / attente", `${recyclerConfig.outputStorageCapacity} / ${recyclerConfig.pendingWasteCapacity}`],
      ["Temps par niveau", JSON.stringify(recyclerConfig.cycleMinutesByLevel)],
    ];
    el.recyclerConfigList.innerHTML = rows.map(([label, value]) => `
      <div class="stage-row"><div><strong>${escapeHtml(label)}</strong><span>${escapeHtml(value)}</span></div><strong>V1</strong></div>
    `).join("");
    el.recyclerStatus.textContent = "Configuration Déchets / Recycleur chargée depuis le JSON versionné.";
  } catch (error) {
    el.recyclerStatus.textContent = "Configuration Recycleur illisible: " + error.message;
  }
}

function exportRecyclerConfig() {
  const blob = new Blob([JSON.stringify(recyclerConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "waste-recycler-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

async function loadCraftConfig({ reset = false } = {}) {
  try {
    const response = await fetch("./craft-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    const baseConfig = await response.json();
    const savedConfig = reset ? null : JSON.parse(localStorage.getItem(CRAFT_STORAGE_KEY) || "null");
    craftConfig = { ...baseConfig, ...(savedConfig || {}) };
    if (reset) localStorage.removeItem(CRAFT_STORAGE_KEY);
    renderCraftConfig();
    el.craftStatus.textContent = "Recettes chargées. Les ajouts restent locaux jusqu'a export JSON.";
  } catch (error) {
    el.craftStatus.textContent = "Configuration Craft illisible: " + error.message;
  }
}

function renderCraftConfig() {
  const recipes = Array.isArray(craftConfig.recipes) ? craftConfig.recipes : [];
  el.craftRecipeList.innerHTML = recipes.map((recipe) => {
    const ingredients = Array.isArray(recipe.ingredients)
      ? recipe.ingredients.map((item) => `${escapeHtml(item.amount)} ${escapeHtml(item.resource)}`).join(" + ")
      : "";
    const context = Array.isArray(recipe.contextIngredients) && recipe.contextIngredients.length
      ? ` + ${recipe.contextIngredients.map(escapeHtml).join(" + ")}`
      : "";
    const effects = recipe.isConsumable
      ? `${escapeHtml(recipe.foodType || "meal")} · consommable · faim +${escapeHtml(recipe.hungerRestore || 0)} · vitalité +${escapeHtml(recipe.vitalityRestore || 0)}`
      : "non consommable";
    return `
      <div class="stage-row">
        <div>
          <strong>${escapeHtml(recipe.displayName || recipe.resultItem)}</strong>
          <span>Cuisine niv. ${escapeHtml(recipe.cuisineLevel || 1)} · ${ingredients}${context} => ${escapeHtml(recipe.resultAmount || 1)} ${escapeHtml(recipe.resultItem)} · ${effects}</span>
        </div>
        <strong>${escapeHtml(recipe.id || "recette")}</strong>
      </div>
    `;
  }).join("");
}

function addCraftRecipe(event) {
  event.preventDefault();
  const form = new FormData(el.craftRecipeForm);
  const ingredients = [
    {
      resource: String(form.get("ingredientResource") || "Organique"),
      amount: Number(form.get("ingredientAmount") || 1),
    },
  ];
  const resource2 = String(form.get("ingredientResource2") || "");
  const amount2 = Number(form.get("ingredientAmount2") || 0);
  if (resource2 && amount2 > 0) {
    ingredients.push({ resource: resource2, amount: amount2 });
  }
  const displayName = String(form.get("displayName") || "Nouvelle recette").trim();
  const resultItem = String(form.get("resultItem") || displayName).trim();
  const recipe = {
    id: displayName.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || `recipe-${Date.now()}`,
    displayName,
    ingredients,
    contextIngredients: ["Eau"],
    cuisineLevel: Number(form.get("cuisineLevel") || 1),
    resultItem,
    resultAmount: Number(form.get("resultAmount") || 1),
    isConsumable: form.get("isConsumable") === "true",
    foodType: String(form.get("foodType") || "meal"),
    hungerRestore: Number(form.get("hungerRestore") || 0),
    vitalityRestore: Number(form.get("vitalityRestore") || 0),
  };
  craftConfig.recipes = Array.isArray(craftConfig.recipes) ? [...craftConfig.recipes, recipe] : [recipe];
  localStorage.setItem(CRAFT_STORAGE_KEY, JSON.stringify(craftConfig, null, 2));
  renderCraftConfig();
  el.craftStatus.textContent = "Recette ajoutée localement. Exporte le JSON pour versionner la configuration.";
}

function exportCraftConfig() {
  const blob = new Blob([JSON.stringify(craftConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "craft-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

function exportFablabConfig() {
  const blob = new Blob([JSON.stringify(fablabConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "fablab-config.json";
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

el.exportKernelButton.addEventListener("click", () => {
  exportKernelConfig();
});

el.exportCampHeartButton.addEventListener("click", () => {
  exportCampHeartConfig();
});

el.exportLisiereForageButton.addEventListener("click", () => {
  exportLisiereForageConfig();
});

el.exportSecurityTowerButton.addEventListener("click", () => {
  exportSecurityTowerConfig();
});

el.exportFablabButton.addEventListener("click", () => {
  exportFablabConfig();
});

el.exportCraftButton.addEventListener("click", () => {
  exportCraftConfig();
});

el.craftRecipeForm.addEventListener("submit", addCraftRecipe);

async function loadActiveBuildingConfigs() {
  const entries = [
    ["camp-generator-config.json", el.campGeneratorEditor],
    ["workshop-config.json", el.workshopEditor],
    ["market-config.json", el.marketEditor],
    ["tower-operations-config.json", el.towerOperationsEditor],
    ["building-architecture-config.json", el.buildingArchitectureEditor],
    ["housing-config.json", el.housingEditor],
  ];
  for (const [file, target] of entries) {
    const response = await fetch(`./${file}`, { cache: "no-store" });
    target.value = JSON.stringify(await response.json(), null, 2);
  }
}

async function loadKernelProgressConfig() {
  const response = await fetch("./kernel-progress-config.json", { cache: "no-store" });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  el.kernelProgressEditor.value = JSON.stringify(await response.json(), null, 2);
}

function exportEditor(editor, filename) {
  const parsed = JSON.parse(editor.value);
  downloadJson(filename, parsed);
}

function downloadJson(filename, value) {
  const blob = new Blob([JSON.stringify(value, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

el.exportCampGeneratorButton.addEventListener("click", () => exportEditor(el.campGeneratorEditor, "camp-generator-config.json"));
el.exportWorkshopButton.addEventListener("click", () => exportEditor(el.workshopEditor, "workshop-config.json"));
el.exportMarketButton.addEventListener("click", () => exportEditor(el.marketEditor, "market-config.json"));
el.exportBuildingArchitectureButton.addEventListener("click", () => exportEditor(el.buildingArchitectureEditor, "building-architecture-config.json"));
el.exportHousingButton.addEventListener("click", () => exportEditor(el.housingEditor, "housing-config.json"));
el.exportTowerOperationsButton.addEventListener("click", () => exportEditor(el.towerOperationsEditor, "tower-operations-config.json"));
el.exportRecyclerButton.addEventListener("click", () => exportRecyclerConfig());
el.exportKernelProgressButton.addEventListener("click", () => exportEditor(el.kernelProgressEditor, "kernel-progress-config.json"));

setupDashboardTabs();
loadPtipoteStatsConfig();
loadKernelConfig();
loadCampHeartConfig();
loadLisiereForageConfig();
loadSecurityTowerConfig();
loadFablabConfig();
loadRecyclerConfig();
loadCraftConfig();
loadActiveBuildingConfigs();
loadKernelProgressConfig().catch((error) => {
  el.kernelStatus.textContent = `Configuration progression Kernel illisible: ${error.message}`;
});
