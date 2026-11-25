import { Injectable } from '@nestjs/common';

export interface LiveDriverLocation {
  driverId: string;
  lat: number;
  lng: number;
  updatedAt: string;
}

@Injectable()
export class LocationService {
  private readonly locations = new Map<string, LiveDriverLocation>();

  set(driverId: string, lat: number, lng: number): LiveDriverLocation {
    const location = { driverId, lat, lng, updatedAt: new Date().toISOString() };
    this.locations.set(driverId, location);
    return location;
  }

  get(driverId?: string): LiveDriverLocation | null {
    if (!driverId) return null;
    return this.locations.get(driverId) ?? null;
  }
}
