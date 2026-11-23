import { useEffect, useState } from "react";
import { api } from "../lib/api";

const NUMERIC_FIELDS = [
  { key: "scan_interval", label: "Frequenza di scansione (secondi)" },
  { key: "min_discount", label: "Sconto minimo per notifica (%)" },
  { key: "min_market_value", label: "Valore di mercato minimo (€)" },
  { key: "max_listing_price", label: "Prezzo massimo annuncio (€)" },
  { key: "min_deal_score", label: "Deal Score minimo" },
];

const BOOL_FIELDS = [
  { key: "telegram_enabled", label: "Notifiche Telegram abilitate" },
  { key: "email_enabled", label: "Notifiche Email abilitate" },
  { key: "desktop_notification", label: "Notifiche desktop abilitate" },
  { key: "sound_notification", label: "Suono di notifica abilitato" },
];

export default function Settings() {
  const [config, setConfig] = useState(null);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    api.getConfig().then(setConfig).catch(() => setError("Impossibile caricare la configurazione."));
  }, []);

  if (!config) {
    return <div>{error ? <div className="alert-error">{error}</div> : "Caricamento..."}</div>;
  }

  const handleChange = (key, value) => setConfig({ ...config, [key]: value });

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const payload = {};
      for (const f of NUMERIC_FIELDS) payload[f.key] = Number(config[f.key]);
      for (const f of BOOL_FIELDS) payload[f.key] = Boolean(config[f.key]);
      payload.telegram_bot_token = config.telegram_bot_token;
      payload.telegram_chat_id = config.telegram_chat_id;
      const updated = await api.updateConfig(payload);
      setConfig(updated);
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (e2) {
      setError("Errore durante il salvataggio.");
    }
  };

  return (
    <div>
      <h1>Impostazioni</h1>
      <p className="hint">
        Modifica i parametri di scansione e notifica senza toccare il codice. Le modifiche
        vengono salvate nel database e applicate immediatamente.
      </p>
      {error && <div className="alert-error">{error}</div>}
      {saved && <div className="alert-success">Impostazioni salvate.</div>}

      <form onSubmit={handleSubmit} className="settings-form">
        <h2>Parametri di scansione</h2>
        {NUMERIC_FIELDS.map((f) => (
          <label key={f.key} className="form-row">
            <span>{f.label}</span>
            <input
              type="number"
              step="any"
              value={config[f.key]}
              onChange={(e) => handleChange(f.key, e.target.value)}
            />
          </label>
        ))}

        <h2>Notifiche</h2>
        {BOOL_FIELDS.map((f) => (
          <label key={f.key} className="form-row form-row-checkbox">
            <span>{f.label}</span>
            <input
              type="checkbox"
              checked={!!config[f.key]}
              onChange={(e) => handleChange(f.key, e.target.checked)}
            />
          </label>
        ))}

        <label className="form-row">
          <span>Telegram Bot Token</span>
          <input
            type="text"
            value={config.telegram_bot_token || ""}
            onChange={(e) => handleChange("telegram_bot_token", e.target.value)}
          />
        </label>
        <label className="form-row">
          <span>Telegram Chat ID</span>
          <input
            type="text"
            value={config.telegram_chat_id || ""}
            onChange={(e) => handleChange("telegram_chat_id", e.target.value)}
          />
        </label>

        <button type="submit" className="btn btn-primary">
          Salva impostazioni
        </button>
      </form>

      <div className="card" style={{ marginTop: "2rem" }}>
        <div className="card-label">Modalità applicazione attuale</div>
        <div className="card-value">{config.app_mode}</div>
        <div className="card-note">
          Cambia APP_MODE nel file .env del backend per passare tra demo, manual_feed e
          vinted_api (vedi README).
        </div>
      </div>
    </div>
  );
}
