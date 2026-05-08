import type { NextConfig } from 'next';

/// Firebase Hosting serves static files only. Next runs as a static
/// export (`out/`) — every page must be client-renderable. Server
/// components are still allowed but they pre-render at build time
/// rather than at request time. All Firestore reads happen in
/// browser-side hooks, which is why the dashboard doesn't need
/// Cloud Functions or Cloud Run for v1.
const nextConfig: NextConfig = {
  output: 'export',
  trailingSlash: true,
  // Static export disables the built-in <Image /> optimiser, so opt
  // into the unoptimised loader to silence the warning. Marker tiles
  // come from OpenStreetMap directly so we don't need server-side
  // image processing here.
  images: {
    unoptimized: true,
  },
  reactStrictMode: true,
};

export default nextConfig;
