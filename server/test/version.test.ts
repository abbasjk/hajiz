import { describe, expect, it } from 'vitest';
import { compareVersions, isValidVersion } from '../src/lib/version.js';

describe('compareVersions', () => {
  it('orders versions numerically, not as text', () => {
    expect(compareVersions('1.10.0', '1.9.0')).toBeGreaterThan(0);
    expect(compareVersions('0.1.0', '0.2.0')).toBeLessThan(0);
    expect(compareVersions('1.0', '1.0.0')).toBe(0);
  });

  it('validates the version format', () => {
    expect(isValidVersion('1.2.3')).toBe(true);
    expect(isValidVersion('1.2.3-beta')).toBe(false);
    expect(isValidVersion('')).toBe(false);
  });
});
