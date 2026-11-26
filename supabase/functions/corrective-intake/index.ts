import { createClient } from 'npm:@supabase/supabase-js@2.119.0';
import { validatePhoto } from './photo.ts';
import { validateVideo } from './video.ts';
import { analysePhoto } from './vision.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: object, status = 200) => Response.json(body, { status, headers: cors });
const uuid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const pathPattern = new RegExp(`^(${uuid})/(${uuid})/report/${uuid}\\.(jpg|png|webp|mp4|mov)$`);
const bucket = 'corrective-evidence';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);
  const token = request.headers.get('Authorization')?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token) return json({ error: 'Sign in to attach evidence.' }, 401);
  const input = await request.json().catch(() => null);
  const path = typeof input?.path === 'string' ? input.path : '';
  const match = pathPattern.exec(path);
  if (!match) return json({ error: 'Invalid report attachment.' }, 400);
  const [, owner, , extension] = match;
  const video = extension === 'mp4' || extension === 'mov';
  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } });
  try {
    const { data: identity } = await client.auth.getUser(token);
    if (identity.user?.id !== owner) return json({ error: 'This attachment is unavailable.' }, 403);
    // Clients with the old opt-in screen still skip analysis if they omit the provider.
    if (!video && input.photo_analysis_provider !== 'openrouter') {
      return json({ kind: 'photo', vision_status: 'skipped' });
    }
    const { data: claim, error: claimError } = await client.rpc('corrective_media_receipt', {
      object_path: path, media_owner: owner,
    });
    if (claimError) throw claimError;
    if (claim?.state === 'complete') return json(claim.result);
    if (claim?.state === 'busy') return json({ error: 'Evidence is being checked. Try again shortly.' }, 409);
    if (claim?.state === 'limited') return json({ error: 'Too many evidence checks. Try again later.' }, 429);
    if (claim?.state !== 'claimed') return json({ error: 'This attachment is unavailable.' }, 403);

    const { data: blob, error: downloadError } = await client.storage.from(bucket).download(path);
    if (downloadError || !blob || blob.size === 0 || blob.size > 10 * 1024 * 1024) throw Error();
    const bytes = new Uint8Array(await blob.arrayBuffer());
    const invalid = video ? validateVideo(bytes) : validatePhoto(bytes, extension);
    const result = invalid ? { error: invalid } : video ? { kind: 'video' } : await analysePhoto(bytes, extension, {
      apiKey: Deno.env.get('Uni360_OPENROUTER'),
    });
    const { error: saveError } = await client.rpc('corrective_media_receipt', {
      object_path: path, media_owner: owner, result,
    });
    if (saveError) throw saveError;
    return json(result);
  } catch {
    return json({ error: 'Could not check this attachment. Try again.' }, 503);
  }
});
