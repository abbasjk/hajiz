import type { Queryable } from './db.js';

/** شرائح مهلة الرد بالدقائق حسب قرب الموعد. */
export interface DeadlineTable {
  same_day_under_6h: number;
  same_day: number;
  tomorrow: number;
  within_week: number;
  week_or_more: number;
}

export type DeadlineMode = 'fast' | 'normal' | 'flexible';

export interface EngineSettings {
  shopDeadlineModes: Record<DeadlineMode, DeadlineTable>;
  customerDeadline: DeadlineTable;
  minLeadMinutes: number;
  slotStepMinutes: number;
  autoCompleteAfterMinutes: number;
  maxPendingPerCustomer: number;
  noShowPenalty: { count: number; window_days: number };
}

export async function loadSettings(db: Queryable): Promise<EngineSettings> {
  const { rows } = await db.query<{ key: string; value: unknown }>('SELECT key, value FROM settings');
  const s = new Map(rows.map((r) => [r.key, r.value]));
  const get = <T>(key: string): T => {
    if (!s.has(key)) throw new Error(`Missing setting: ${key}`);
    return s.get(key) as T;
  };
  return {
    shopDeadlineModes: get('shop_deadline_modes'),
    customerDeadline: get('customer_deadline'),
    minLeadMinutes: get('min_lead_minutes'),
    slotStepMinutes: get('slot_step_minutes'),
    autoCompleteAfterMinutes: get('auto_complete_after_minutes'),
    maxPendingPerCustomer: get('max_pending_requests_per_customer'),
    noShowPenalty: get('no_show_penalty'),
  };
}
