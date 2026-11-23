import { useEffect, useState } from "react";
import Link from "next/link";
import { api } from "../lib/api";
import PriorityBadge from "../components/PriorityBadge";

const STATUS_LABELS = {
  SCANNING: { emoji: "🟢", text: "SCANNING" },
  STOPPED: { emoji: "⚪", text: "FERMO" },
  PAUSED_RATE_LIMIT: { emoji: "🟠", text: "IN PAUSA (rate limit rilevato)" },
  PAUSED_BLOCKED: { emoji: "🔴", text: "IN PAUSA (blocco rilevato)" },
};

function formatTime(iso) {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleTimeString("it-IT");
  } catch {
    return iso;
  }
}

export default function Home() {
  const [status, setStatus] = useState(null);
  const [opportunities, setOpportunities] = useState([]);
  const [error, setError] = useState(null);

  const refresh = async () => {
    try {
      const [s, opps] = await Promise.all([api.getStatus(), api.getOpportunities()]);
      setStatus(s);
      setOpportunities(opps.slice(0, 5));
      setError(null);
    } catch (e) {
      setError(
        "Impossibile contattare il backend. Verifica che sia in esecuzione su " +
          (process.env.NEXT_PUBLIC_API_BASE || "http://localhost:8000")
      );
    }
  };

  useEffect(() => {
    refresh();
    const interval = setInterval(refresh, 3000);
    return () => clearInterval(interval);
  }, []);

  const handleStart = async () => {
    await api.startScan();
    refresh();
  };
  const handleStop = async () => {
    await api.stopScan();
    refresh();
  };

  const statusInfo = status ? STATUS_LABELS[status.scanner_status] || STATUS_LABELS.STOPPED : null;

  return (
    <div>
      <h1>LIVE SCANNER</h1>

      {error && <div className="alert-error">{error}</div>}

      {status && (
        <>
          {status.demo_mode && (
            <div className="alert-info">
              Modalità <strong>DEMO/TEST</strong> attiva — dati simulati, nessuna richiesta di rete reale.
            </div>
          )}

          <div className="status-grid">
            <div className="card">
              <div className="card-label">Stato</div>
              <div className="card-value">
                {statusInfo.emoji} {statusInfo.text}
              </div>
            </div>
            <div className="card">
              <div className="card-label">Connettore attivo</div>
              <div className="card-value">{status.connector}</div>
            </div>
            <div className="card">
              <div className="card-label">Ultimo controllo</div>
              <div className="card-value">{formatTime(status.last_check_at)}</div>
            </div>
            <div className="card">
              <div className="card-label">Prossimo controllo</div>
              <div className="card-value">{formatTime(status.next_check_at)}</div>
            </div>
            <div className="card">
              <div className="card-label">Intervallo attuale</div>
              <div className="card-value">
                {status.current_interval}s
                {status.current_interval !== status.requested_interval && (
                  <div className="card-note">
                    (richiesti {status.requested_interval}s, adattato automaticamente)
                  </div>
                )}
              </div>
            </div>
            <div className="card">
              <div className="card-label">Annunci analizzati</div>
              <div className="card-value">{status.listings_analyzed.toLocaleString("it-IT")}</div>
            </div>
            <div className="card">
              <div className="card-label">Opportunità trovate</div>
              <div className="card-value">{status.opportunities_found.toLocaleString("it-IT")}</div>
            </div>
          </div>

          <div className="actions-row">
            <button className="btn btn-primary" onClick={handleStart}>
              ▶ Avvia scansione
            </button>
            <button className="btn btn-secondary" onClick={handleStop}>
              ⏸ Ferma scansione
            </button>
          </div>
        </>
      )}

      <h2>Ultime opportunità</h2>
      <table className="table">
        <thead>
          <tr>
            <th>Carta</th>
            <th>Prezzo</th>
            <th>Valore mercato</th>
            <th>Sconto</th>
            <th>Score</th>
            <th>Priorità</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {opportunities.map((o) => (
            <tr key={o.listing_id}>
              <td>{[o.pokemon_name, o.card_type, o.card_number].filter(Boolean).join(" ")}</td>
              <td>€{o.price}</td>
              <td>€{o.market_value}</td>
              <td>-{o.discount_percentage}%</td>
              <td>{o.deal_score}</td>
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
              <td colSpan={7} className="empty-row">
                Nessuna opportunità ancora rilevata.
              </td>
            </tr>
          )}
        </tbody>
      </table>
      <p>
        <Link href="/opportunities">Vedi tutte le opportunità →</Link>
      </p>
    </div>
  );
}
