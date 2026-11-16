// Action JavaScript WeWeb : « Géolocaliser »
// Renvoie { lat, lng, accuracy } ou null. Ne lève JAMAIS d'erreur :
// refus, délai dépassé ou position indisponible → null, et le pointage
// est quand même envoyé (il sera « non vérifié » pour l'admin).

return await new Promise((resolve) => {
  if (!("geolocation" in navigator)) return resolve(null);

  // Filet de sécurité si le navigateur n'appelle jamais le rappel.
  const filet = setTimeout(() => resolve(null), 11000);

  navigator.geolocation.getCurrentPosition(
    (p) => {
      clearTimeout(filet);
      resolve({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy });
    },
    () => {
      clearTimeout(filet);
      resolve(null);
    },
    { enableHighAccuracy: true, maximumAge: 0, timeout: 10000 },
  );
});
