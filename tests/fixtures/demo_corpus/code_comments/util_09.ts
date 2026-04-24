// quick helper. no framework — keep it copy-pasteable.
export function clamp01(x: number): number {
  if (x < 0) return 0;
  if (x > 1) return 1;
  return x;
}
