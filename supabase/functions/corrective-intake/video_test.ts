import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import test from 'node:test';
import { validateVideo } from './video.ts';

function numbers(...values: number[]) {
  const data = Buffer.alloc(values.length * 4);
  values.forEach((value, index) => data.writeUInt32BE(value, index * 4));
  return data;
}

function box(tag: string, ...parts: Buffer[]) {
  return Buffer.concat([numbers(8 + parts.reduce((n, part) => n + part.length, 0)), Buffer.from(tag), ...parts]);
}

function fixture(movieTicks: number, sampleTicks = movieTicks, handler = 'vide') {
  const timing = numbers(0, 0, 0, 1000, movieTicks);
  return Buffer.concat([
    box('ftyp', Buffer.from('isom')),
    box('moov', box('mvhd', timing), box('trak', box('mdia',
      box('mdhd', timing),
      box('hdlr', numbers(0, 0), Buffer.from(handler)),
      box('minf', box('stbl', box('stts', numbers(0, 1, 1, sampleTicks)))),
    ))),
    box('mdat', Buffer.from([1])),
  ]);
}

test('allows up to exactly 30 seconds', () => {
  assert.equal(validateVideo(fixture(29999)), undefined);
  assert.equal(validateVideo(fixture(30000)), undefined);
});

test('rejects long container and sample timelines', () => {
  assert.match(validateVideo(fixture(30001))!, /30 seconds/);
  assert.match(validateVideo(fixture(20000, 31000))!, /30 seconds/);
});

test('rejects truncated, audio-only and fragmented clips', () => {
  assert.match(validateVideo(fixture(10000).subarray(0, -1))!, /readable duration/);
  assert.match(validateVideo(fixture(10000, 10000, 'soun'))!, /readable duration/);
  assert.match(validateVideo(Buffer.concat([fixture(10000), box('moof')]))!, /readable duration/);
});
