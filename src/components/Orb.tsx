export function Orb({ small = false }: { small?: boolean }) {
  return (
    <span className={`ritm-orb${small ? ' ritm-orb-small' : ''}`} aria-hidden="true">
      <span />
    </span>
  );
}
