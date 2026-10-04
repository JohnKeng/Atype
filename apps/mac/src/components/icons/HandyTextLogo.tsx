import React from "react";
import appIcon from "@/assets/atype-icon.png";

// Product name, not UI copy: never translated.
const BRAND_NAME = "Atype";

// Atype logo: the app icon (src/assets/atype-icon.png, replaced together with
// the macOS icon by `bun run icon:set`) next to the name. The file and
// component keep their upstream (Handy) names so imports stay unchanged.
const HandyTextLogo = ({
  width = 120,
  className,
}: {
  width?: number;
  height?: number;
  className?: string;
}) => {
  const iconSize = Math.round(width * 0.32);
  const fontSize = Math.round(width * 0.22);
  return (
    <div
      className={`inline-flex items-center justify-center gap-2 select-none ${className ?? ""}`}
      style={{ width }}
    >
      <img
        src={appIcon}
        alt=""
        width={iconSize}
        height={iconSize}
        draggable={false}
        className="shrink-0"
      />
      <span
        className="font-extrabold tracking-tight text-text"
        style={{ fontSize, lineHeight: 1 }}
      >
        {BRAND_NAME}
      </span>
    </div>
  );
};

export default HandyTextLogo;
