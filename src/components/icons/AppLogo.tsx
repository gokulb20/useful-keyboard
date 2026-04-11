import React from "react";

const AppLogo = ({
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
      viewBox="0 0 320 64"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M12 14v26a20 20 0 0 0 40 0V14"
        stroke="currentColor"
        strokeWidth="8"
        strokeLinecap="round"
      />
      <text
        x="68"
        y="44"
        fontFamily="Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif"
        fontWeight="600"
        fontSize="28"
        fill="currentColor"
      >
        Useful Keyboard
      </text>
    </svg>
  );
};

export default AppLogo;
