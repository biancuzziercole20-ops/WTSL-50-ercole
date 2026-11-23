const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://localhost:8000";

async function request(path, options = {}) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!res.ok) {
    throw new Error(`API error ${res.status} su ${path}`);
  }
  return res.json();
}

export const api = {
  getStatus: () => request("/api/status"),
  getOpportunities: () => request("/api/opportunities"),
  getListings: () => request("/api/listings"),
  getHistory: (pokemonName) =>
    request(`/api/history?pokemon_name=${encodeURIComponent(pokemonName)}`),
  getLogs: () => request("/api/logs"),
  getConfig: () => request("/api/config"),
  updateConfig: (payload) =>
    request("/api/config", { method: "POST", body: JSON.stringify(payload) }),
  startScan: () => request("/api/scan/start", { method: "POST" }),
  stopScan: () => request("/api/scan/stop", { method: "POST" }),
};
