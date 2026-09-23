import type { FastifyRequest } from 'fastify';
import type { Pool } from '../db/pool.js';
import { AppError } from '../lib/errors.js';
import { authenticate, type AuthContext } from './devices.js';

declare module 'fastify' {
  interface FastifyRequest {
    auth?: AuthContext;
  }
}

/** يتطلب Authorization: Bearer <token> صالحاً. */
export function requireAuth(pool: Pool) {
  return async (request: FastifyRequest) => {
    const header = request.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7).trim() : '';
    const auth = token ? await authenticate(pool, token) : null;
    if (!auth) throw new AppError(401, 'unauthorized');
    request.auth = auth;
  };
}

export function authOf(request: FastifyRequest): AuthContext {
  if (!request.auth) throw new AppError(401, 'unauthorized');
  return request.auth;
}
