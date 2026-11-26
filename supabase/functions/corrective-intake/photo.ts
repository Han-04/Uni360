export function validatePhoto(bytes: Uint8Array, extension: string): string | undefined {
  const signature = extension === 'jpg'
    ? [0xff, 0xd8, 0xff]
    : extension === 'png'
    ? [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    : [0x52, 0x49, 0x46, 0x46];
  const matches = signature.every((value, index) => bytes[index] === value)
    && (extension !== 'webp' || String.fromCharCode(...bytes.subarray(8, 12)) === 'WEBP');
  return matches ? undefined : 'Use a JPEG, PNG or WebP photograph.';
}
