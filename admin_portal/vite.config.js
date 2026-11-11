import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

const file = new URL('../config/supabase.json', import.meta.url);
const config = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};

export default defineConfig(({ mode }) => {
  const embedded = mode === 'flutter';
  return {
    base: embedded ? './' : '/',
    define: {
      __SUPABASE_URL__: JSON.stringify(embedded ? '' : process.env.VITE_SUPABASE_URL ?? config.SUPABASE_URL ?? ''),
      __SUPABASE_KEY__: JSON.stringify(embedded ? '' : process.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? config.SUPABASE_PUBLISHABLE_KEY ?? ''),
    },
    ...(embedded && {
      build: {
        outDir: fileURLToPath(new URL('../web/admin', import.meta.url)),
        emptyOutDir: false,
        rollupOptions: { output: { entryFileNames: 'portal.js', assetFileNames: '[name][extname]' } },
      },
    }),
  };
});
