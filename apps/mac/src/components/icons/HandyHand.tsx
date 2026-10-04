// Atype: the sidebar "General" icon is the same voice waveform as the app
// icon. File and component keep their upstream names (see HandyTextLogo.tsx).
const HandyHand = ({
  width,
  height,
}: {
  width?: number | string;
  height?: number | string;
}) => (
  <svg
    width={width || 24}
    height={height || 24}
    viewBox="0 0 24 24"
    className="fill-text"
    xmlns="http://www.w3.org/2000/svg"
  >
    <rect x="2" y="9.5" width="2.6" height="5" rx="1.3" />
    <rect x="6.4" y="6.5" width="2.6" height="11" rx="1.3" />
    <rect x="10.7" y="3" width="2.6" height="18" rx="1.3" />
    <rect x="15" y="6.5" width="2.6" height="11" rx="1.3" />
    <rect x="19.4" y="9.5" width="2.6" height="5" rx="1.3" />
  </svg>
);

export default HandyHand;
