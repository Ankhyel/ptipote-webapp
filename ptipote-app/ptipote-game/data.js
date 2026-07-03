window.PTIPOTE_DATA = {
  refuge: {
    background: "./image_game/Ilot.jpg"
  },
  buildings: [
    { id: "home", name: "Maison", icon: "⌂", summary: "Repos, repas, chambres.", x: 45, y: 47, w: 24, h: 15 },
    { id: "kernel", name: "Kernel", icon: "◇", summary: "Scan, messages systeme, plans futurs.", x: 48, y: 19, w: 30, h: 15 },
    { id: "forest", name: "Lisiere", icon: "♧", summary: "Recolte courte de ressources.", x: 7, y: 57, w: 27, h: 15 },
    { id: "workshop", name: "Atelier", icon: "⚙", summary: "Craft simple de Repas.", x: 64, y: 60, w: 27, h: 13 },
    { id: "kitchen", name: "Cuisine", icon: "◌", summary: "Repas et soins plus tard.", x: 72, y: 43, w: 20, h: 12 },
    { id: "market", name: "Marche", icon: "$", summary: "Vente automatique d'un stock.", x: 8, y: 43, w: 22, h: 12 }
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
    "Choisir Kelo dans le Kernel.",
    "Assigner Kelo a la Lisiere.",
    "Attendre la recolte puis recuperer les gains.",
    "Craft un Repas a l'Atelier.",
    "Soigner Kelo a la Maison.",
    "Faire progresser Kelo avec l'XP.",
    "Boucle proto validee : Kelo a recolte, mange et progresse."
  ]
};
