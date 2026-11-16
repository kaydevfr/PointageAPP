import type { MetadataRoute } from "next";

// Application installable sur l'écran d'accueil du téléphone.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Pointage — Les Nettoyeurs",
    short_name: "Pointage",
    lang: "fr",
    start_url: "/planning",
    display: "standalone",
    background_color: "#f8fafc",
    theme_color: "#1d4ed8",
    icons: [{ src: "/icon.svg", sizes: "any", type: "image/svg+xml" }],
  };
}
