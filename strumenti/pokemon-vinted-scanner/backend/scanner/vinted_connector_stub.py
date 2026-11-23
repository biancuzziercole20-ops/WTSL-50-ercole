"""
Placeholder per una fonte dati REALE e autorizzata su Vinted.

QUESTO CONNETTORE NON FA SCRAPING E NON CONTIENE ALCUNA LOGICA DI ACCESSO
NON AUTORIZZATO. È intenzionalmente disattivato.

Per attivarlo in futuro, quando/se disporrai di un metodo di accesso ai
dati Vinted lecito (una API ufficiale per sviluppatori, un accordo di
partnership, un feed dati concesso in licenza, o un tuo export manuale
conforme ai Termini di Servizio), dovrai:

1. Ottenere le credenziali/endpoint della fonte dati autorizzata.
2. Implementare fetch_listings() qui sotto usando quella fonte (es. una
   chiamata HTTP alla API ufficiale, con la tua API key), rispettando i
   rate limit che la fonte stessa dichiara.
3. Impostare APP_MODE=vinted_api nel file .env.
4. Aggiornare recommended_min_interval_seconds() con il valore minimo
   imposto dalla fonte dati (mai forzare un intervallo più aggressivo).

Finché questo non viene fatto, l'applicazione userà DemoConnector (test)
o ManualFeedConnector (dati inseriti manualmente/legalmente da te).
"""
from typing import List
from backend.scanner.base_connector import ConnectorBase, BlockedError
from backend.database.models import Listing


class VintedAPIConnector(ConnectorBase):
    name = "vinted_api (non implementato)"

    def fetch_listings(self, query: dict) -> List[Listing]:
        raise BlockedError(
            "VintedAPIConnector non è implementato: nessuna fonte dati Vinted "
            "autorizzata è stata configurata. Vedi le istruzioni nel docstring "
            "di questo file e nel README (sezione 'Passare alla modalità reale') "
            "per collegare una fonte dati lecita, oppure usa APP_MODE=demo o "
            "APP_MODE=manual_feed."
        )

    def supports_realtime(self) -> bool:
        return False

    def recommended_min_interval_seconds(self) -> int:
        # Valore prudenziale finché non è nota la policy della fonte reale.
        return 60
