import { describe, expect, it } from "vitest";
import {
  MESSAGE_ECHEC,
  cleCarte,
  codePlausible,
  corpsPointer,
  emailPlausible,
  horaires,
  libelleBouton,
  messageErreur,
  nettoyerCode,
  normaliserEmail,
  tonMessage,
} from "./pointage";

const P = "00000000-0000-0000-0000-0000000000a1";
const C = "00000000-0000-0000-0000-0000000000c1";
const MAINTENANT = new Date("2026-11-16T06:58:00Z");

describe("corpsPointer", () => {
  it("envoie l'id du pointage quand il existe", () => {
    const corps = corpsPointer({ pointage_id: P, creneau_id: C }, { lat: 48.85, lng: 2.35, accuracy: 12 }, "tel-1", MAINTENANT);
    expect(corps).toEqual({
      pointageId: P,
      location: { lat: 48.85, lng: 2.35, accuracy: 12 },
      deviceTime: "2026-11-16T06:58:00.000Z",
      appareilId: "tel-1",
    });
  });

  it("envoie l'id du créneau quand le pointage n'est pas encore créé", () => {
    const corps = corpsPointer({ pointage_id: null, creneau_id: C }, null, null, MAINTENANT);
    expect(corps.creneauId).toBe(C);
    expect(corps.pointageId).toBeUndefined();
  });

  it("position refusée : on envoie quand même, avec location null", () => {
    expect(corpsPointer({ pointage_id: P, creneau_id: null }, null, "tel-1", MAINTENANT).location).toBeNull();
  });

  it("n'envoie jamais l'identité de l'agent (elle vient de la session)", () => {
    const corps = corpsPointer({ pointage_id: P, creneau_id: null }, null, null, MAINTENANT);
    expect(Object.keys(corps).some((k) => /profil|profile|user/i.test(k))).toBe(false);
  });
});

describe("affichage des cartes", () => {
  it("libellé du bouton selon le serveur, rien si null", () => {
    expect(libelleBouton("arrivee")).toBe("Pointer l'arrivée");
    expect(libelleBouton("depart")).toBe("Pointer le départ");
    expect(libelleBouton(null)).toBeNull();
  });

  it("horaires", () => {
    expect(horaires({ heure_debut: "07:00", heure_fin: "09:00", hors_planning: false })).toBe("07:00 – 09:00");
    expect(horaires({ heure_debut: null, heure_fin: null, hors_planning: true })).toBe("Hors planning");
  });

  it("ton du message", () => {
    expect(tonMessage("termine")).toBe("succes");
    expect(tonMessage("penser_depart")).toBe("attention");
    expect(tonMessage("manque")).toBe("neutre");
    expect(tonMessage("arrivee_pointee")).toBe("info");
    expect(tonMessage("a_pointer")).toBe("info");
  });

  it("clé de carte : pointage, sinon créneau", () => {
    expect(cleCarte({ pointage_id: P, creneau_id: C })).toBe(P);
    expect(cleCarte({ pointage_id: null, creneau_id: C })).toBe(C);
    expect(cleCarte({ pointage_id: null, creneau_id: null })).toBe("");
  });
});

describe("messageErreur", () => {
  it("reprend le message du serveur", () => {
    expect(messageErreur({ action: "limite", message: "Trop de tentatives. Réessayez dans une minute." }))
      .toBe("Trop de tentatives. Réessayez dans une minute.");
  });
  it("jamais de détail technique", () => {
    expect(messageErreur(null)).toBe(MESSAGE_ECHEC);
    expect(messageErreur({ message: "" })).toBe(MESSAGE_ECHEC);
    expect(messageErreur({ error: "stack trace" })).toBe(MESSAGE_ECHEC);
    expect(messageErreur("boom")).toBe(MESSAGE_ECHEC);
  });
});

describe("connexion", () => {
  it("email normalisé et vérifié", () => {
    expect(normaliserEmail("  Prenom.Nom@Exemple.FR ")).toBe("prenom.nom@exemple.fr");
    expect(emailPlausible("prenom.nom@exemple.fr")).toBe(true);
    expect(emailPlausible("prenom.nom")).toBe(false);
    expect(emailPlausible("a b@c.fr")).toBe(false);
  });
  it("code : chiffres seulement, 6 à 8", () => {
    expect(nettoyerCode(" 123 456 ")).toBe("123456");
    expect(nettoyerCode("12-34-56-78-90")).toBe("12345678");
    expect(codePlausible("123456")).toBe(true);
    expect(codePlausible("12345")).toBe(false);
  });
});
