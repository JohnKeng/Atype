import React from "react";

// Atype wordmark: voice-waveform mark + "Atype". The file and component keep
// their upstream (Handy) names so `git subtree pull` stays conflict-free for
// every component that imports it.
const HandyTextLogo = ({
  width,
  height,
  className,
}: {
  width?: number;
  height?: number;
  className?: string;
}) => {
  return (
    <svg
      width={width}
      height={height}
      className={className}
      viewBox="0 0 560 160"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Atype"
    >
      <g className="logo-primary">
        <rect x="8" y="64" width="18" height="32" rx="9" />
        <rect x="38" y="40" width="18" height="80" rx="9" />
        <rect x="68" y="16" width="18" height="128" rx="9" />
        <rect x="98" y="40" width="18" height="80" rx="9" />
        <rect x="128" y="64" width="18" height="32" rx="9" />
      </g>
      <text
        x="172"
        y="118"
        className="fill-text"
        textLength="372"
        lengthAdjust="spacingAndGlyphs"
        style={{
          fontFamily:
            "'SF Pro Rounded', -apple-system, BlinkMacSystemFont, system-ui, sans-serif",
          fontSize: 120,
          fontWeight: 800,
          letterSpacing: "-2px",
        }}
      >
        {/* eslint-disable-next-line i18next/no-literal-string */}
        Atype
      </text>
    </svg>
  );
};

export default HandyTextLogo;
