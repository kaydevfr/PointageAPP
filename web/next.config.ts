import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // L'accueil mène au planning ; le proxy renvoie vers /connexion si besoin.
  async redirects() {
    return [{ source: "/", destination: "/planning", permanent: false }];
  },
  cacheComponents: true,
  partialPrefetching: true,
  turbopack: {
    // Le dépôt a aussi un package.json à la racine (outils de test Supabase).
    root: process.cwd(),
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
