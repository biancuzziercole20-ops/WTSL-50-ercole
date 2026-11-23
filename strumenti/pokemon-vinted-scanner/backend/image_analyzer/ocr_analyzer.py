"""
Analisi immagini (punto 4 della spec).

Usa pytesseract (wrapper di Tesseract OCR) per estrarre testo dalle
immagini dell'annuncio, quando disponibili e leggibili. Se Tesseract non è
installato sul sistema, o l'immagine non è raggiungibile/analizzabile, il
modulo NON inventa dati: restituisce confidence 0 e imposta
"Identificazione incerta", come richiesto esplicitamente dalla spec.

In modalità DEMO le immagini sono URL/percorsi fittizi: l'OCR reale viene
saltato e viene simulato un risultato coerente con i dati del listing
demo stesso (ancora nessuna invenzione: i "dati simulati" sono etichettati
come tali e usati solo per popolare la dashboard di test).
"""
import io
import logging
from typing import List, Optional

from backend.database.models import CardIdentification
from backend.card_identifier.parser import identify_card_from_text

logger = logging.getLogger("image_analyzer")

try:
    import pytesseract
    from PIL import Image
    import requests
    TESSERACT_AVAILABLE = True
except ImportError:
    TESSERACT_AVAILABLE = False


def _ocr_image_bytes(image_bytes: bytes) -> Optional[str]:
    if not TESSERACT_AVAILABLE:
        return None
    try:
        img = Image.open(io.BytesIO(image_bytes))
        return pytesseract.image_to_string(img)
    except Exception as e:  # Tesseract non installato sul sistema, o binario mancante
        logger.warning(f"OCR non disponibile: {e}")
        return None


def _fetch_image(url: str) -> Optional[bytes]:
    if not TESSERACT_AVAILABLE:
        return None
    try:
        resp = requests.get(url, timeout=5)
        if resp.status_code == 200:
            return resp.content
    except Exception as e:
        logger.warning(f"Impossibile scaricare l'immagine {url}: {e}")
    return None


def analyze_images(images: List[str], demo_mode: bool = False, demo_hint_text: str = "") -> CardIdentification:
    """
    Ritorna una CardIdentification arricchita dall'analisi immagine.
    Se non è possibile analizzare nulla, ritorna confidence 0 e
    uncertain=True senza inventare dati (requisito esplicito).
    """
    if not images:
        ident = CardIdentification()
        ident.image_confidence = 0.0
        ident.uncertain = True
        ident.notes.append("Nessuna immagine disponibile: Identificazione incerta")
        return ident

    if demo_mode:
        # In demo simuliamo un OCR "riuscito" rileggendo il testo noto del
        # listing demo, con una confidence leggermente ridotta per
        # simulare l'incertezza reale dell'OCR su immagini di bassa qualità.
        ident = identify_card_from_text(demo_hint_text, "")
        ident.image_confidence = max(0.0, ident.text_confidence - 8.0)
        ident.notes.append("[DEMO] OCR simulato sulla base del testo annuncio")
        return ident

    ocr_texts = []
    for url in images[:5]:  # limite di sicurezza: max 5 immagini per annuncio
        raw = _fetch_image(url)
        if raw:
            text = _ocr_image_bytes(raw)
            if text:
                ocr_texts.append(text)

    if not ocr_texts:
        ident = CardIdentification()
        ident.image_confidence = 0.0
        ident.uncertain = True
        ident.notes.append(
            "OCR non disponibile o immagini illeggibili: Identificazione incerta"
        )
        return ident

    combined_text = " ".join(ocr_texts)
    ident = identify_card_from_text(combined_text, "")
    ident.image_confidence = ident.text_confidence
    return ident
