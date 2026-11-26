// Read playback timing from a complete, non-fragmented ISO BMFF video.
export function validateVideo(bytes: Uint8Array): string | undefined {
  const invalid = 'Use a standard MP4 or MOV video with a readable duration.';
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  type Box = { tag: string; start: number; end: number };
  const tag = (at: number) => String.fromCharCode(...bytes.subarray(at, at + 4));
  function boxes(start: number, end: number): Box[] {
    const result: Box[] = [];
    while (start + 8 <= end) {
      const type = tag(start + 4);
      let size = view.getUint32(start);
      let header = 8;
      if (size === 1 && start + 16 <= end) {
        size = Number(view.getBigUint64(start + 8));
        header = 16;
      } else if (size === 0) size = end - start;
      if (size < header || size > end - start || result.length >= 4096) throw Error();
      result.push({ tag: type, start: start + header, end: start + size });
      start += size;
    }
    if (start !== end) throw Error();
    return result;
  }
  const children = (box: Box) => boxes(box.start, box.end);
  const child = (box: Box, type: string) => {
    const found = children(box).filter((entry) => entry.tag === type);
    if (found.length !== 1) throw Error();
    return found[0];
  };
  function timing(box: Box) {
    const version = view.getUint8(box.start);
    if (version !== 0 && version !== 1) throw Error();
    const offset = box.start + (version === 1 ? 20 : 12);
    if (offset + (version === 1 ? 12 : 8) > box.end) throw Error();
    const scale = view.getUint32(offset);
    const ticks = version === 1 ? Number(view.getBigUint64(offset + 4)) : view.getUint32(offset + 4);
    if (scale === 0 || !Number.isSafeInteger(ticks) || ticks === 0) throw Error();
    return { scale, seconds: ticks / scale };
  }

  try {
    const root = boxes(0, bytes.length);
    const movies = root.filter((box) => box.tag === 'moov');
    if (movies.length !== 1 || root.some((box) => box.tag === 'moof') ||
      !root.some((box) => box.tag === 'mdat' && box.end > box.start)) return invalid;
    const movie = movies[0];
    if (children(movie).some((box) => box.tag === 'mvex')) return invalid;
    let longest = timing(child(movie, 'mvhd')).seconds;
    let hasVideo = false;
    for (const track of children(movie).filter((box) => box.tag === 'trak')) {
      const media = child(track, 'mdia');
      const handler = child(media, 'hdlr');
      if (handler.start + 12 > handler.end) return invalid;
      hasVideo ||= tag(handler.start + 8) === 'vide';
      const { scale, seconds } = timing(child(media, 'mdhd'));
      const samples = child(child(child(media, 'minf'), 'stbl'), 'stts');
      if (samples.start + 8 > samples.end) return invalid;
      const count = view.getUint32(samples.start + 4);
      if (count === 0 || 8 + count * 8 !== samples.end - samples.start) return invalid;
      let ticks = 0;
      for (let offset = samples.start + 8; offset < samples.end; offset += 8) {
        ticks += view.getUint32(offset) * view.getUint32(offset + 4);
        if (ticks > 30 * scale) return 'Choose a video that is 30 seconds or shorter.';
      }
      if (ticks <= 0) return invalid;
      longest = Math.max(longest, seconds);
    }
    if (!hasVideo) return invalid;
    return longest > 30 ? 'Choose a video that is 30 seconds or shorter.' : undefined;
  } catch {
    return invalid;
  }
}
