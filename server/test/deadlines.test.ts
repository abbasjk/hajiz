import { describe, expect, it } from 'vitest';
import { computeSlots } from '../src/booking/availability.js';
import { deadlineTier, responseDeadline } from '../src/booking/deadlines.js';
import { local } from './fixtures.js';

const normal = { same_day_under_6h: 15, same_day: 30, tomorrow: 60, within_week: 240, week_or_more: 720 };

describe('deadlineTier', () => {
  const now = local('2026-10-05', '08:00');

  it.each([
    ['2026-10-05', '12:00', 'same_day_under_6h'],
    ['2026-10-05', '14:00', 'same_day'],
    ['2026-10-06', '10:00', 'tomorrow'],
    ['2026-10-09', '10:00', 'within_week'],
    ['2026-10-12', '10:00', 'week_or_more'],
  ])('%s %s → %s', (date, time, tier) => {
    expect(deadlineTier(now, local(date, time))).toBe(tier);
  });

  it('counts days by the Baghdad calendar, not UTC', () => {
    // 22:00 في بغداد = 19:00 UTC؛ موعد 04:00 بعد منتصف الليل هو "غداً" رغم أنه بعد 6 ساعات فقط
    expect(deadlineTier(local('2026-10-05', '22:00'), local('2026-10-06', '04:00'))).toBe('tomorrow');
  });
});

describe('responseDeadline', () => {
  it('adds the tier minutes to now', () => {
    const now = local('2026-10-05', '08:00');
    expect(responseDeadline(now, local('2026-10-06', '10:00'), normal)).toEqual(local('2026-10-05', '09:00'));
  });

  it('never passes the appointment time', () => {
    const now = local('2026-10-05', '08:00');
    const startsAt = local('2026-10-05', '08:10');
    expect(responseDeadline(now, startsAt, normal)).toEqual(startsAt);
  });
});

describe('computeSlots', () => {
  const period = { start: local('2026-10-05', '09:00'), end: local('2026-10-05', '10:30') };

  it('steps every 15 minutes and keeps only starts that fit the duration', () => {
    const slots = computeSlots([period], [], 30, 15, new Date(0));
    expect(slots.map((s) => s.toISOString())).toEqual(
      ['09:00', '09:15', '09:30', '09:45', '10:00'].map((t) => local('2026-10-05', t).toISOString()),
    );
  });

  it('skips starts that overlap a busy interval', () => {
    const busy = [{ start: local('2026-10-05', '09:30'), end: local('2026-10-05', '10:00') }];
    const slots = computeSlots([period], busy, 30, 15, new Date(0));
    expect(slots).toEqual([local('2026-10-05', '09:00'), local('2026-10-05', '10:00')]);
  });

  it('drops starts before the earliest allowed time', () => {
    const slots = computeSlots([period], [], 30, 15, local('2026-10-05', '09:40'));
    expect(slots).toEqual([local('2026-10-05', '09:45'), local('2026-10-05', '10:00')]);
  });

  it('aligns an odd opening time to the next quarter hour', () => {
    const odd = { start: local('2026-10-05', '09:10'), end: local('2026-10-05', '10:00') };
    expect(computeSlots([odd], [], 30, 15, new Date(0))[0]).toEqual(local('2026-10-05', '09:15'));
  });
});
