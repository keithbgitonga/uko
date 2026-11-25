import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import { NotificationsService } from '../notifications/notifications.service';

export type DocumentType = 'licence' | 'insurance' | 'vehicle_photo';
const REQUIRED: DocumentType[] = ['licence', 'insurance'];

@Injectable()
export class DocumentsService implements OnModuleInit {
  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
    private readonly notifications: NotificationsService,
  ) {}

  onModuleInit(): void {
    void this.checkExpiry();
    const timer = setInterval(() => void this.checkExpiry(), 12 * 3600_000);
    timer.unref?.();
  }

  /** Notifies drivers when an approved document is expiring or expired. */
  async checkExpiry(): Promise<void> {
    try {
      const result = await this.db.pool.query(
        `SELECT * FROM driver_documents
         WHERE status='APPROVED' AND expires_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
           AND expires_at::date <= current_date + 14
           AND (expiry_notified_at IS NULL OR expiry_notified_at < now() - interval '7 days')`,
      );
      for (const row of result.rows) {
        const expires = new Date(`${row.expires_at}T00:00:00Z`).getTime();
        const daysLeft = Math.ceil((expires - Date.now()) / (24 * 3600_000));
        const expired = daysLeft < 0;
        await this.notifications.send(
          row.driver_id,
          expired ? 'Document expired' : 'Document expiring soon',
          expired
            ? `Your ${row.type.replace('_', ' ')} has expired. Upload a renewed copy to stay online.`
            : `Your ${row.type.replace('_', ' ')} expires in ${daysLeft} day(s). Upload a renewal.`,
          { documentId: row.id, type: row.type, daysLeft },
        );
        await this.db.pool.query('UPDATE driver_documents SET expiry_notified_at = now() WHERE id = $1', [row.id]);
      }
    } catch (err) {
      console.error(`document expiry check failed: ${err instanceof Error ? err.message : err}`);
    }
  }

  async upload(
    driverId: string,
    input: { type: DocumentType; documentNumber?: string; expiresAt?: string },
    file?: { originalname: string; path: string; size: number; mimetype: string },
  ) {
    if (!['licence', 'insurance', 'vehicle_photo'].includes(input.type)) {
      throw new BadRequestException({ code: 'DOCUMENT_TYPE_INVALID' });
    }
    const id = `doc_${randomUUID()}`;
    const result = await this.db.pool.query(
      `INSERT INTO driver_documents (id, driver_id, type, document_number, expires_at, file_name, file_path, file_size, mime_type)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [
        id,
        driverId,
        input.type,
        input.documentNumber ?? null,
        input.expiresAt ?? null,
        file?.originalname ?? null,
        file?.path ?? null,
        file?.size ?? null,
        file?.mimetype ?? null,
      ],
    );
    return toDocument(result.rows[0]);
  }

  async listForDriver(driverId: string) {
    const result = await this.db.pool.query('SELECT * FROM driver_documents WHERE driver_id = $1 ORDER BY created_at DESC', [driverId]);
    return result.rows.map(toDocument);
  }

  async listAll(status?: string) {
    const result = status
      ? await this.db.pool.query('SELECT * FROM driver_documents WHERE status = $1 ORDER BY created_at DESC LIMIT 200', [status])
      : await this.db.pool.query('SELECT * FROM driver_documents ORDER BY created_at DESC LIMIT 200');
    return result.rows.map(toDocument);
  }

  async review(id: string, reviewerId: string, decision: 'APPROVED' | 'REJECTED', reason?: string) {
    const result = await this.db.pool.query(
      `UPDATE driver_documents SET status=$1, reviewed_by=$2, reviewed_at=now(), rejection_reason=$3 WHERE id=$4 RETURNING *`,
      [decision, reviewerId, reason ?? null, id],
    );
    if (result.rowCount === 0) throw new NotFoundException({ code: 'DOCUMENT_NOT_FOUND' });
    return toDocument(result.rows[0]);
  }

  async canGoOnline(driverId: string): Promise<boolean> {
    const required = this.config.get<boolean>('documents.required') ?? false;
    if (!required) return true;
    const result = await this.db.pool.query(
      `SELECT type FROM driver_documents WHERE driver_id=$1 AND status='APPROVED'`,
      [driverId],
    );
    const approved = new Set(result.rows.map((r) => r.type));
    return REQUIRED.every((type) => approved.has(type));
  }

  async assertCanGoOnline(driverId: string): Promise<void> {
    if (!(await this.canGoOnline(driverId))) {
      throw new ForbiddenException({
        code: 'DOCUMENTS_PENDING',
        message: 'Your licence and insurance must be approved before you can go online.',
      });
    }
  }
}

function toDocument(row: any) {
  return {
    id: row.id,
    driverId: row.driver_id,
    type: row.type,
    status: row.status,
    ...(row.document_number ? { documentNumber: row.document_number } : {}),
    ...(row.expires_at ? { expiresAt: row.expires_at } : {}),
    ...(row.file_name ? { fileName: row.file_name, fileSize: row.file_size, mimeType: row.mime_type } : {}),
    ...(row.rejection_reason ? { rejectionReason: row.rejection_reason } : {}),
    reviewedAt: row.reviewed_at ? new Date(row.reviewed_at).toISOString() : null,
    createdAt: new Date(row.created_at).toISOString(),
  };
}
