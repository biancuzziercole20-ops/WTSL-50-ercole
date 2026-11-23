import { useEffect, useState } from "react";
import { api } from "../lib/api";
import PriorityBadge from "../components/PriorityBadge";

export default function Opportunities() {
  const [opportunities, setOpportunities] = useState([]);
  const [error, setError] = useState(null);

  const refresh = async () => {
    try {
      const opps = await api.getOpportunities();
      setOpportunities(opps);
      setError(null);
    } catch (e) {
      setError("Impossibile contattare il backend.");
    }
  };

  useEffect(() => {
    refresh();
    const interval = setInterval(refresh, 5000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div>
      <h1>Tabella opportunità</h1>
      {error && <div className="alert-error">{error}</div>}
      <table className="table">
        <thead>
          <tr>
            <th>Carta</th>
            <th>Set</th>
            <th>Prezzo</th>
            <th>Valore mercato</th>
            <th>Sconto</th>
            <th>Score</th>
            <th>Confidence</th>
            <th>Priorità</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {opportunities.map((o) => (
            <tr key={o.listing_id}>
              <td>{[o.pokemon_name, o.card_type, o.card_number].filter(Boolean).join(" ")}</td>
              <td>{o.set_name || "—"}</td>
              <td>€{o.price}</td>
              <td>€{o.market_value}</td>
              <td>-{o.discount_percentage}%</td>
              <td>{o.deal_score}</td>
              <td>{o.confidence}%</td>
              <td>
                <PriorityBadge priority={o.priority} />
              </td>
              <td>
                <a href={o.url} target="_blank" rel="noreferrer" className="btn-link">
                  APRI ANNUNCIO
                </a>
              </td>
            </tr>
          ))}
          {opportunities.length === 0 && (
            <tr>
              <td colSpan={9} className="empty-row">
                Nessuna opportunità ancora rilevata.
              </td>
            </tr>
          )}
        </tbody>
      </table>
      <p className="hint">
        Il programma non effettua mai acquisti automatici: apri l'annuncio per valutare e
        decidere manualmente.
      </p>
    </div>
  );
}
