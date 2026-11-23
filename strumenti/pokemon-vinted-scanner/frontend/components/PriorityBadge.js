const CONFIG = {
  ECCELLENTE: { emoji: "🟢", className: "badge badge-excellent" },
  INTERESSANTE: { emoji: "🟡", className: "badge badge-good" },
  "DA VERIFICARE": { emoji: "🟠", className: "badge badge-check" },
  NORMALE: { emoji: "🔴", className: "badge badge-normal" },
};

export default function PriorityBadge({ priority }) {
  const cfg = CONFIG[priority] || CONFIG.NORMALE;
  return (
    <span className={cfg.className}>
      {cfg.emoji} {priority}
    </span>
  );
}
