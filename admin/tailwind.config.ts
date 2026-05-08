import type { Config } from 'tailwindcss';

const config: Config = {
  darkMode: ['class'],
  content: [
    './app/**/*.{ts,tsx}',
    './components/**/*.{ts,tsx}',
    './lib/**/*.{ts,tsx}',
  ],
  theme: {
    container: {
      center: true,
      padding: '1rem',
      screens: { '2xl': '1400px' },
    },
    extend: {
      colors: {
        // Mirror the iOS palette from Voltspot/Resources/Assets.xcassets
        // so screenshots from app + admin look like one product.
        bg: 'hsl(var(--bg))',
        surface: 'hsl(var(--surface))',
        surface2: 'hsl(var(--surface-2))',
        fg: 'hsl(var(--fg))',
        fg2: 'hsl(var(--fg-2))',
        fg3: 'hsl(var(--fg-3))',
        rule: 'hsl(var(--rule))',
        accent: 'hsl(var(--accent))',
        'accent-tint': 'hsl(var(--accent-tint))',
        success: 'hsl(var(--success))',
        warning: 'hsl(var(--warning))',
        danger: 'hsl(var(--danger))',
        muted: 'hsl(var(--muted))',
      },
      borderRadius: {
        lg: '12px',
        md: '8px',
        sm: '4px',
      },
      fontFamily: {
        sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
    },
  },
  plugins: [],
};

export default config;
