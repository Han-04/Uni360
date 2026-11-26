import assert from 'node:assert/strict';
import test from 'node:test';
import { analysePhoto } from './vision.ts';

const sample = Uint8Array.from([0xff, 0xd8, 0xff, 0x00]);
const candidate = (value: object) => Response.json({
  choices: [{ finish_reason: 'stop', message: { content: JSON.stringify(value) } }],
});

test('uses the description fallback when no OpenRouter key is configured', async () => {
  let calls = 0;
  const request = async () => { calls++; return candidate({ finding: 'sink_leak' }); };
  assert.equal((await analysePhoto(sample, 'jpg', { request })).vision_status, 'not_configured');
  assert.equal(calls, 0);
});

test('sends only the photo, pins free routing and uses Uni360 priorities', async () => {
  const request: typeof fetch = async (url, options) => {
    assert.equal(url, 'https://openrouter.ai/api/v1/chat/completions');
    assert.equal(new Headers(options?.headers).get('Authorization'), 'Bearer test-key');
    const body = JSON.parse(String(options?.body));
    assert.equal(body.model, 'nvidia/nemotron-3.5-super-vl:free');
    assert.equal(body.models, undefined);
    assert.deepEqual(body.provider.max_price, { prompt: 0, completion: 0, image: 0, request: 0 });
    assert.equal(body.messages.length, 1);
    assert.equal(body.messages[0].content.length, 2);
    assert.deepEqual(body.messages[0].content[1], {
      type: 'image_url',
      image_url: { url: 'data:image/jpeg;base64,/9j/AA==' },
    });
    return candidate({ finding: 'sink_leak', priority: 'Critical' });
  };
  assert.deepEqual(await analysePhoto(sample, 'jpg', { apiKey: 'test-key', request }), {
    kind: 'photo',
    vision_status: 'vision_fault',
    model: 'nvidia/nemotron-3.5-super-vl:free',
    category: 'Plumbing',
    priority: 'Medium',
    observation: 'Possible visible leak from sink plumbing.',
  });
});

test('requires context for water from a tap spout', async () => {
  const result = await analysePhoto(sample, 'jpg', {
    apiKey: 'test-key', request: async () => candidate({ finding: 'tap_water' }),
  });
  assert.equal(result.vision_status, 'unclear');
  assert.match(result.observation!, /continues after the tap is closed/);
});

test('uses fallback on quota errors and unrecognized findings', async () => {
  for (const response of [
    new Response(null, { status: 429 }),
    candidate({ finding: 'toString' }),
    candidate({ priority: 'Critical' }),
  ]) {
    const result = await analysePhoto(sample, 'png', {
      apiKey: 'test-key', request: async () => response,
    });
    assert.equal(result.vision_status, 'unavailable');
  }
});
