import { useState } from "react";
import { api } from "../lib/api";

export default function History() {
  const [query, setQuery] = useState("");
  const [records, setRecords] = useState([]);
  const [error, setError] = useState(null);
  const [searched, setSearched] = useState(false);

  const handleSearch = async (e) => {
    e.preventDefault();
    if (!query.trim()) return;
    try {
      const data = await api.getHistory(query.trim());
      setRecords(data);
      setError(null);
      setSearched(true);
    } catch (e2) {
      setError("Errore durante la ricerca dello storico.");
    }
  };

  const prices = records.map((r) => r.price);
  const marketValues = records.map((r) => r.market_value).filter((v) => v != null);
  const latestMarket = marketValues[0];

  return (
    <div>
      <h1>Storico Prezzi</h1>
      <form onSubmit={handleSearch} className="search-form">
        <input
          type="text"
          placeholder="Nome Pokémon (es. Umbreon, Charizard...)"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <button type="submit" className="btn btn-primary">
          Cerca
        </button>
      </form>

      {error && <div className="alert-error">{error}</div>}

      {searched && (
        <>
          {latestMarket != null && (
            <div className="card" style={{ marginBottom: "1rem" }}>
              <div className="card-label">Valore di mercato più recente stimato</div>
              <div className="card-value">€{latestMarket}</div>
            </div>
          )}

          <h2>Ultimi annunci trovati per "{query}"</h2>
          <table className="table">
            <thead>
              <tr>
                <th>Data rilevazione</th>
                <th>Prezzo annuncio</th>
                <th>Valore mercato stimato</th>
              </tr>
            </thead>
            <tbody>
              {records.map((r) => (
                <tr key={r.id}>
                  <td>{new Date(r.recorded_at).toLocaleString("it-IT")}</td>
                  <td>€{r.price}</td>
                  <td>{r.market_value != null ? `€${r.market_value}` : "—"}</td>
                </tr>
              ))}
              {records.length === 0 && (
                <tr>
                  <td colSpan={3} className="empty-row">
                    Nessuno storico trovato per questa carta.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </>
      )}
    </div>
  );
}
