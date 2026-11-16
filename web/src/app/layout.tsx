import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Pointage — Les Nettoyeurs",
  description: "Pointage des arrivées et départs sur les sites.",
  applicationName: "Pointage",
  appleWebApp: { capable: true, title: "Pointage", statusBarStyle: "default" },
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#1d4ed8",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="fr" className="h-full antialiased">
      <body className="flex min-h-full flex-col bg-slate-50 text-slate-900">{children}</body>
    </html>
  );
}
