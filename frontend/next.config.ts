import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  poweredByHeader: false,
  devIndicators: false,
  // The browser smoke runner accesses this hostname on the private Compose network.
  allowedDevOrigins: ["frontend"],
};
export default nextConfig;
