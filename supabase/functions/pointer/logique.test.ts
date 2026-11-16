import { assertEquals } from "@std/assert";
import { analyserRequete, extraireIp, statutHttp } from "./logique.ts";

const ID = "00000000-0000-0000-0000-0000000000c1";
const META = { ip: "203.0.113.7", userAgent: "Mozilla/5.0 (iPhone)" };

Deno.test("carte avec pointageId et position complète", () => {
  const r = analyserRequete({
    pointageId: ID,
    location: { lat: 48.8566, lng: 2.3522, accuracy: 12 },
    deviceTime: "2026-11-16T07:58:00+01:00",
    appareilId: "a1b2c3d4-e5f6",
  }, META);
  assertEquals(r, {
    ok: true,
    pointageId: ID,
    creneauId: null,
    preuves: {
      lat: 48.8566,
      lng: 2.3522,
      precision_m: 12,
      device_at: "2026-11-16T07:58:00+01:00",
      appareil_id: "a1b2c3d4-e5f6",
      user_agent: "Mozilla/5.0 (iPhone)",
      ip: "203.0.113.7",
    },
  });
});

Deno.test("carte avec creneauId (pointage pas encore généré)", () => {
  const r = analyserRequete({ creneauId: ID }, META);
  assertEquals(r.ok && r.creneauId, ID);
});

Deno.test("permission de localisation refusée : le pointage passe quand même", () => {
  const r = analyserRequete({ pointageId: ID, location: null }, META);
  assertEquals(r.ok, true);
  assertEquals(r.ok && "lat" in r.preuves, false);
});

Deno.test("position malformée : omise, sans bloquer", () => {
  const r = analyserRequete({ pointageId: ID, location: { lat: "48,8", lng: NaN } }, META);
  assertEquals(r.ok, true);
  assertEquals(r.ok && r.preuves.lat, undefined);
});

Deno.test("précision absente ou négative : omise (la base lèvera LOW_ACCURACY)", () => {
  const r = analyserRequete({ pointageId: ID, location: { lat: 48.8, lng: 2.3, accuracy: -1 } }, META);
  assertEquals(r.ok && r.preuves.precision_m, undefined);
  assertEquals(r.ok && r.preuves.lat, 48.8);
});

Deno.test("identifiant d'appareil suspect : ignoré", () => {
  const r = analyserRequete({ pointageId: ID, appareilId: "<script>" }, META);
  assertEquals(r.ok && r.preuves.appareil_id, undefined);
});

Deno.test("heure du téléphone trop longue : ignorée", () => {
  const r = analyserRequete({ pointageId: ID, deviceTime: "x".repeat(100) }, META);
  assertEquals(r.ok && r.preuves.device_at, undefined);
});

Deno.test("ni pointageId ni creneauId : refusé", () => {
  assertEquals(analyserRequete({}, META), {
    ok: false,
    statut: 400,
    message: "Créneau introuvable. Actualisez la page.",
  });
});

Deno.test("les deux à la fois : refusé", () => {
  assertEquals(analyserRequete({ pointageId: ID, creneauId: ID }, META).ok, false);
});

Deno.test("identifiant qui n'est pas un UUID : refusé", () => {
  assertEquals(analyserRequete({ pointageId: "1 or 1=1" }, META).ok, false);
});

Deno.test("corps vide ou non-objet : refusé", () => {
  assertEquals(analyserRequete(null, META).ok, false);
  assertEquals(analyserRequete([ID], META).ok, false);
  assertEquals(analyserRequete("pointer", META).ok, false);
});

Deno.test("l'identité de l'agent ne vient jamais du corps", () => {
  const r = analyserRequete({ pointageId: ID, profileId: "autre", p_profile_id: "autre" }, META);
  assertEquals(r.ok && Object.keys(r.preuves).some((k) => k.includes("profile")), false);
});

Deno.test("IP : première adresse de x-forwarded-for", () => {
  assertEquals(extraireIp(new Headers({ "x-forwarded-for": "203.0.113.7, 10.0.0.1" })), "203.0.113.7");
  assertEquals(extraireIp(new Headers({ "x-real-ip": "198.51.100.2" })), "198.51.100.2");
  assertEquals(extraireIp(new Headers()), null);
});

Deno.test("codes HTTP", () => {
  assertEquals(statutHttp("arrivee"), 200);
  assertEquals(statutHttp("depart"), 200);
  assertEquals(statutHttp("deja_pointe"), 200);
  assertEquals(statutHttp("termine"), 200);
  assertEquals(statutHttp("refuse"), 403);
  assertEquals(statutHttp("limite"), 429);
  assertEquals(statutHttp("erreur"), 400);
});
