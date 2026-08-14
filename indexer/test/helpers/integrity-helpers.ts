import { CheckResult } from '../../src/integrity/checks';

export function checkResultShape(r: CheckResult): void {
  expect(typeof r.id).toBe('string');
  expect(r.id.length).toBeGreaterThan(0);
  expect(typeof r.name).toBe('string');
  expect(typeof r.passed).toBe('boolean');
  expect(typeof r.details).toBe('string');
}
