// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import sitemap from "@astrojs/sitemap";

// Static build → dist/, deployed to Vercel at the apex of its own subdomain.
// The site lives at the domain root, so `base` is "/" (Astro's default) and every
// internal link/asset resolves straight off the root via import.meta.env.BASE_URL.
// `site` is also what the sitemap integration uses to build absolute URLs; robots.txt
// (public/) points crawlers at the generated sitemap-index.xml.
export default defineConfig({
  site: "https://houdini.salomao.org",
  integrations: [sitemap()],
  vite: {
    plugins: [tailwindcss()],
  },
});
