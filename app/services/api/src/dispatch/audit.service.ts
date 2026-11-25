import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { randomUUID } from 'node:crypto';

export interface AuditActor {
  id: string;
  phone: string;
}

@Injectable()
export class AuditService {
  constructor(private readonly db: DatabaseService) {}

  record(actor: AuditActor, action: string, entity: string, entityId: string, detail: Record<string, unknown> = {}): void {
    const id = `au_${randomUUID()}`;
    void this.db.pool
      .query(
        `INSERT INTO audit_log (id, actor_id, actor_phone, action, entity, entity_id, detail)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [id, actor.id, actor.phone, action, entity, entityId, JSON.stringify(detail)],
      )
      .catch((err) => console.error(`audit write failed: ${err.message}`));
  }

  async list(limit = 50) {
    const result = await this.db.pool.query(
      'SELECT id, actor_phone, action, entity, entity_id, detail, created_at FROM audit_log ORDER BY created_at DESC LIMIT $1',
      [limit],
    );
    return result.rows.map((r) => ({
      id: r.id,
      actorPhone: r.actor_phone,
      action: r.action,
      entity: r.entity,
      entityId: r.entity_id,
      detail: r.detail,
      createdAt: new Date(r.created_at).toISOString(),
    }));
  }
}
