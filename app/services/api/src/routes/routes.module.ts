import { Global, Module } from '@nestjs/common';
import { AuthModule } from '../identity/auth.module';
import { RoutesController } from './routes.controller';
import { RoutesService } from './routes.service';

@Global()
@Module({
  imports: [AuthModule],
  controllers: [RoutesController],
  providers: [RoutesService],
  exports: [RoutesService],
})
export class RoutesModule {}
