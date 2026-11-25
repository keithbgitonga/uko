import { Body, Controller, Delete, Get, Headers, Param, Post, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService, DevUser } from '../identity/auth.service';
import { AddContactDto, TriggerSosDto } from './dto/safety.dto';
import { SafetyService } from './safety.service';

@ApiTags('safety')
@ApiBearerAuth()
@Controller('safety')
export class SafetyController {
  constructor(private readonly safety: SafetyService, private readonly auth: AuthService) {}

  @Get('contacts')
  async listContacts(@Headers('authorization') authHeader?: string) {
    return { contacts: this.safety.listContacts((await this.requireUser(authHeader)).id) };
  }

  @Post('contacts')
  async addContact(@Headers('authorization') authHeader: string | undefined, @Body() dto: AddContactDto) {
    return { contact: this.safety.addContact((await this.requireUser(authHeader)).id, dto.name, dto.phone, dto.relationship) };
  }

  @Delete('contacts/:id')
  async removeContact(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    return this.safety.removeContact((await this.requireUser(authHeader)).id, id);
  }

  @Post('sos')
  async triggerSos(@Headers('authorization') authHeader: string | undefined, @Body() dto: TriggerSosDto) {
    return { incident: this.safety.triggerSos((await this.requireUser(authHeader)).id, dto) };
  }

  @Get('incidents')
  async listIncidents(@Headers('authorization') authHeader?: string) {
    return { incidents: this.safety.listIncidents((await this.requireUser(authHeader)).id) };
  }

  @Get('incidents/:id')
  async getIncident(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    return { incident: this.safety.getIncident((await this.requireUser(authHeader)).id, id) };
  }

  @Post('incidents/:id/cancel')
  async cancelIncident(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    return { incident: this.safety.cancelIncident((await this.requireUser(authHeader)).id, id) };
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
