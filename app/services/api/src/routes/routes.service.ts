import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface RouteStep {
  instruction: string;
  distanceM: number;
  durationS: number;
  type: string;
  modifier: string;
  name: string;
}

export interface RoadRoute {
  points: [number, number][]; // [lat, lng]
  distanceKm: number;
  durationMin: number;
  source: 'osrm' | 'fallback';
  steps: RouteStep[];
}

@Injectable()
export class RoutesService {
  private readonly cache = new Map<string, { at: number; route: RoadRoute }>();

  constructor(private readonly config: ConfigService) {}

  async route(pickupLat: number, pickupLng: number, dropoffLat: number, dropoffLng: number): Promise<RoadRoute> {
    const key = [pickupLat, pickupLng, dropoffLat, dropoffLng].map((v) => v.toFixed(4)).join(',');
    const cached = this.cache.get(key);
    if (cached && cached.at > Date.now() - 3_600_000) return cached.route;
    let route: RoadRoute;
    try {
      route = await this.osrm(pickupLat, pickupLng, dropoffLat, dropoffLng);
    } catch {
      route = this.fallback(pickupLat, pickupLng, dropoffLat, dropoffLng);
    }
    this.cache.set(key, { at: Date.now(), route });
    if (this.cache.size > 500) this.cache.delete(this.cache.keys().next().value as string);
    return route;
  }

  private async osrm(pickupLat: number, pickupLng: number, dropoffLat: number, dropoffLng: number): Promise<RoadRoute> {
    const base = (this.config.get<string>('routing.osrmUrl') ?? '').replace(/\/$/, '');
    const userAgent = this.config.get<string>('routing.userAgent') ?? 'Uko/0.1';
    const coords = `${pickupLng},${pickupLat};${dropoffLng},${dropoffLat}`;
    const url = `${base}/${coords}?overview=full&geometries=geojson&alternatives=false&steps=true`;
    const response = await fetch(url, {
      headers: { 'user-agent': userAgent, accept: 'application/json' },
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) throw new Error(`osrm_http_${response.status}`);
    const body: any = await response.json();
    const best = body?.routes?.[0];
    const coordsOut: number[][] | undefined = best?.geometry?.coordinates;
    if (body?.code !== 'Ok' || !Array.isArray(coordsOut) || coordsOut.length < 2) {
      throw new Error('osrm_no_route');
    }
    return {
      points: coordsOut.map(([lng, lat]) => [lat, lng] as [number, number]),
      distanceKm: Math.round((best.distance / 1000) * 10) / 10,
      durationMin: Math.max(1, Math.round(best.duration / 60)),
      source: 'osrm',
      steps: this.steps(best),
    };
  }

  private steps(route: any): RouteStep[] {
    const raw = route?.legs?.[0]?.steps;
    if (!Array.isArray(raw)) return [];
    return raw.slice(0, 40).map((step: any) => {
      const type = String(step.maneuver?.type ?? 'continue');
      const modifier = String(step.maneuver?.modifier ?? '');
      const name = String(step.name ?? '');
      return {
        instruction: this.instruction(type, modifier, name),
        distanceM: Math.round(Number(step.distance) || 0),
        durationS: Math.round(Number(step.duration) || 0),
        type,
        modifier,
        name,
      };
    });
  }

  private instruction(type: string, modifier: string, name: string): string {
    const road = name ? ` onto ${name}` : '';
    if (type === 'depart') return name ? `Head out on ${name}` : 'Head to the pickup';
    if (type === 'arrive') return 'Arrive at your destination';
    if (type === 'merge') return `Merge${modifier ? ' ' + modifier : ''}${road}`;
    if (type === 'fork') return `Keep ${modifier || 'straight'}${road}`;
    if (type === 'roundabout' || type === 'rotary') return `Take the roundabout${road}`;
    if (type === 'new name' || type === 'continue') return name ? `Continue on ${name}` : 'Continue straight';
    if (type === 'end of road') return `At the end of the road, turn ${modifier || 'ahead'}${road}`;
    return `Turn ${modifier || 'ahead'}${road}`;
  }

  private fallback(pickupLat: number, pickupLng: number, dropoffLat: number, dropoffLng: number): RoadRoute {
    const dLat = ((dropoffLat - pickupLat) * Math.PI) / 180;
    const dLng = ((dropoffLng - pickupLng) * Math.PI) / 180;
    const lat1 = (pickupLat * Math.PI) / 180;
    const lat2 = (dropoffLat * Math.PI) / 180;
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
    const distanceKm = Math.max(0.1, Math.round(6371 * 2 * Math.asin(Math.sqrt(h)) * 10) / 10);
    return {
      points: [[pickupLat, pickupLng], [dropoffLat, dropoffLng]],
      distanceKm,
      durationMin: Math.max(1, Math.round((distanceKm / 22) * 60)),
      source: 'fallback',
      steps: [],
    };
  }
}
