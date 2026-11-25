import {
  BadRequestException, Body, Controller, Get, Headers, Post, UploadedFile, UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { diskStorage } from 'multer';
import { extname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { AuthService, DevUser } from '../identity/auth.service';
import { DocumentsService, DocumentType } from './documents.service';

const UPLOAD_DIR = join(process.cwd(), 'uploads', 'driver-documents');

@ApiTags('driver-documents')
@ApiBearerAuth()
@Controller('driver/documents')
export class DocumentsController {
  constructor(private readonly documents: DocumentsService, private readonly auth: AuthService) {}

  @Get()
  async list(@Headers('authorization') authHeader?: string) {
    return { documents: await this.documents.listForDriver((await this.requireUser(authHeader)).id) };
  }

  @Post()
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: UPLOAD_DIR,
        filename: (_req, file, cb) => cb(null, `${randomUUID()}${extname(file.originalname) || '.bin'}`),
      }),
      limits: { fileSize: 5 * 1024 * 1024 },
      fileFilter: (_req, file, cb) => {
        const ok = /^(image\/(jpeg|png|webp)|application\/pdf|application\/octet-stream|text\/plain)$/.test(file.mimetype);
        cb(ok ? null : new BadRequestException({ code: 'DOCUMENT_FILE_TYPE' }), ok);
      },
    }),
  )
  async upload(
    @Headers('authorization') authHeader: string | undefined,
    @Body() body: { type?: DocumentType; documentNumber?: string; expiresAt?: string },
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!body?.type) throw new BadRequestException({ code: 'DOCUMENT_TYPE_REQUIRED' });
    const user = await this.requireUser(authHeader);
    return {
      document: await this.documents.upload(
        user.id,
        { type: body.type as DocumentType, documentNumber: body.documentNumber, expiresAt: body.expiresAt },
        file,
      ),
    };
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) throw new BadRequestException({ code: 'ACCESS_MISSING' });
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
