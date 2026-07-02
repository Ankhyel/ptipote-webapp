window.PTIPOTE_DATA = {
  buildings: [
    { id: "home", name: "Maison", icon: "⌂", summary: "Repos, repas, chambres." },
    { id: "bio", name: "Bio-ordinateur", icon: "◇", summary: "Selection et donnees du P'TIPOTE." },
    { id: "forest", name: "Lisiere", icon: "♧", summary: "Recolte courte de ressources." },
    { id: "workshop", name: "Atelier", icon: "⚙", summary: "Craft simple de Repas." },
    { id: "tower", name: "Tour", icon: "▲", summary: "Genere une securite stable." },
    { id: "market", name: "Marche", icon: "$", summary: "Vente automatique d'un stock." }
  ],
  ptipotes: [
    {
      uid: "PTI-Z0-001",
      name: "Kelo",
      type: "Mousse",
      species: "Myca",
      level: 1,
      xp: 0,
      actionPoints: 3,
      wellbeing: 62,
      rest: 54
    }
  ],
  resources: {
    debris: 0,
    organic: 0,
    meals: 0,
    security: 0,
    credits: 0
  },
  objectives: [
    "Choisir Kelo dans le Bio-ordinateur.",
    "Assigner Kelo a la Lisiere.",
    "Attendre la recolte puis recuperer les gains.",
    "Craft un Repas a l'Atelier.",
    "Soigner Kelo a la Maison.",
    "Faire progresser Kelo avec l'XP.",
    "Boucle proto validee : Kelo a recolte, mange et progresse."
  ]
};
