import { describe, expect, it, vi } from "vitest";
import { appareilId, explicationVue, marquerExplicationVue, obtenirPosition } from "./appareil";

function stockageMemoire() {
  const m = new Map<string, string>();
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v) };
}

describe("appareilId", () => {
  it("est créé une fois puis réutilisé", () => {
    const s = stockageMemoire();
    const genere = vi.fn(() => "id-unique-123");
    expect(appareilId(s, genere)).toBe("id-unique-123");
    expect(appareilId(s, genere)).toBe("id-unique-123");
    expect(genere).toHaveBeenCalledTimes(1);
  });
  it("stockage indisponible (navigation privée) : null, sans erreur", () => {
    expect(appareilId(null)).toBeNull();
    const casse = { getItem: () => { throw new Error("SecurityError"); }, setItem: () => {} };
    expect(appareilId(casse)).toBeNull();
  });
});

describe("écran d'explication", () => {
  it("montré une seule fois", () => {
    const s = stockageMemoire();
    expect(explicationVue(s)).toBe(false);
    marquerExplicationVue(s);
    expect(explicationVue(s)).toBe(true);
  });
});

describe("obtenirPosition", () => {
  const coords = { latitude: 48.8566, longitude: 2.3522, accuracy: 15 };

  it("renvoie la position, en haute précision, sans cache, 10 s max", async () => {
    const geo = {
      getCurrentPosition: vi.fn((ok: PositionCallback) => ok({ coords } as GeolocationPosition)),
    } as unknown as Geolocation;
    await expect(obtenirPosition(geo)).resolves.toEqual({ lat: 48.8566, lng: 2.3522, accuracy: 15 });
    expect(geo.getCurrentPosition).toHaveBeenCalledWith(expect.any(Function), expect.any(Function), {
      enableHighAccuracy: true,
      maximumAge: 0,
      timeout: 10_000,
    });
  });

  it("permission refusée : null (le pointage passera quand même)", async () => {
    const geo = {
      getCurrentPosition: (_ok: PositionCallback, ko: PositionErrorCallback) =>
        ko({ code: 1, message: "denied" } as GeolocationPositionError),
    } as unknown as Geolocation;
    await expect(obtenirPosition(geo)).resolves.toBeNull();
  });

  it("navigateur sans géolocalisation : null", async () => {
    await expect(obtenirPosition(undefined)).resolves.toBeNull();
  });

  it("le navigateur ne répond jamais : null après le délai", async () => {
    vi.useFakeTimers();
    const geo = { getCurrentPosition: () => {} } as unknown as Geolocation;
    const p = obtenirPosition(geo, 10_000);
    vi.advanceTimersByTime(11_000);
    await expect(p).resolves.toBeNull();
    vi.useRealTimers();
  });

  it("erreur levée par le navigateur : null", async () => {
    const geo = { getCurrentPosition: () => { throw new Error("boom"); } } as unknown as Geolocation;
    await expect(obtenirPosition(geo)).resolves.toBeNull();
  });
});
