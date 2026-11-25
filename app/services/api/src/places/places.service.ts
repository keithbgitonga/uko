import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface PlaceResult {
  id: string;
  name: string;
  address: string;
  lat: number;
  lng: number;
}

// Small offline seed so the bench and demos still work without Nominatim.
const SEED: PlaceResult[] = [
  { id: 'seed-kenyatta', name: 'Kenyatta Avenue', address: 'Kenyatta Avenue, Nairobi', lat: -1.2841, lng: 36.8233 },
  { id: 'seed-westlands', name: 'Westlands', address: 'Westlands, Nairobi', lat: -1.2657, lng: 36.8075 },
  { id: 'seed-cbd', name: 'Nairobi CBD', address: 'Central Business District, Nairobi', lat: -1.2864, lng: 36.8172 },
  { id: 'seed-kileleshwa', name: 'Kileleshwa', address: 'Kileleshwa, Nairobi', lat: -1.2783, lng: 36.7826 },
  { id: 'seed-kilimani', name: 'Kilimani', address: 'Kilimani, Nairobi', lat: -1.2921, lng: 36.7867 },
  { id: 'seed-upperhill', name: 'Upper Hill', address: 'Upper Hill, Nairobi', lat: -1.2987, lng: 36.8145 },
  { id: 'seed-lavington', name: 'Lavington', address: 'Lavington, Nairobi', lat: -1.2692, lng: 36.7710 },
  { id: 'seed-parklands', name: 'Parklands', address: 'Parklands, Nairobi', lat: -1.2620, lng: 36.8170 },
  { id: 'seed-karen', name: 'Karen', address: 'Karen, Nairobi', lat: -1.3350, lng: 36.7060 },
  { id: 'seed-yaya', name: 'Yaya Centre', address: 'Yaya Centre, Kilimani, Nairobi', lat: -1.2929, lng: 36.7854 },
  { id: 'seed-sarit', name: 'Sarit Centre', address: 'Sarit Centre, Westlands, Nairobi', lat: -1.2621, lng: 36.8028 },
  { id: 'seed-village', name: 'Village Market', address: 'Village Market, Gigiri, Nairobi', lat: -1.2286, lng: 36.8045 },
  { id: 'seed-hub', name: 'The Hub Karen', address: 'The Hub Karen, Nairobi', lat: -1.3205, lng: 36.7073 },
  { id: 'seed-jkia', name: 'JKIA', address: 'Jomo Kenyatta International Airport, Nairobi', lat: -1.3192, lng: 36.9278 },
  { id: 'seed-wilson', name: 'Wilson Airport', address: 'Wilson Airport, Nairobi', lat: -1.3217, lng: 36.8148 },
  { id: 'seed-hospital', name: 'Nairobi Hospital', address: 'Nairobi Hospital, Upper Hill', lat: -1.2984, lng: 36.8170 },
  { id: 'seed-rongai', name: 'Rongai', address: 'Kajiado/Rongai', lat: -1.3960, lng: 36.7500 },
  { id: 'seed-thika', name: 'Thika Road', address: 'Thika Road, Nairobi', lat: -1.2210, lng: 36.8700 },
];

@Injectable()
export class PlacesService {
  private readonly cache = new Map<string, { at: number; places: PlaceResult[] }>();

  constructor(private readonly config: ConfigService) {}

  async search(query: string): Promise<PlaceResult[]> {
    const q = query.trim().toLowerCase();
    if (q.length < 2) return [];
    const cached = this.cache.get(q);
    if (cached && cached.at > Date.now() - 3_600_000) return cached.places;

    const fallback = SEED.filter(
      (p) => p.name.toLowerCase().includes(q) || p.address.toLowerCase().includes(q),
    ).slice(0, 6);

    let remote: PlaceResult[] = [];
    try {
      remote = await this.nominatim(query.trim());
    } catch {
      remote = [];
    }
    const seen = new Set<string>();
    const places: PlaceResult[] = [];
    for (const place of [...remote, ...fallback]) {
      const key = `${place.name}|${place.lat.toFixed(4)}|${place.lng.toFixed(4)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      places.push(place);
      if (places.length >= 6) break;
    }
    if (places.length === 0) places.push(...fallback);
    this.cache.set(q, { at: Date.now(), places });
    if (this.cache.size > 500) this.cache.delete(this.cache.keys().next().value as string);
    return places;
  }

  private async nominatim(query: string): Promise<PlaceResult[]> {
    const base = this.config.get<string>('places.nominatimUrl')!;
    const userAgent = this.config.get<string>('places.userAgent')!;
    const url = new URL(base);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('q', query);
    url.searchParams.set('countrycodes', 'ke');
    url.searchParams.set('limit', '6');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('viewbox', '36.60,-1.10,37.10,-1.55');
    const response = await fetch(url, {
      headers: { 'user-agent': userAgent, accept: 'application/json' },
      signal: AbortSignal.timeout(4_000),
    });
    if (!response.ok) throw new Error(`nominatim_http_${response.status}`);
    const rows: any[] = await response.json();
    return rows
      .filter((r) => Number.isFinite(Number(r.lat)) && Number.isFinite(Number(r.lon)))
      .map((r) => {
        const display = String(r.display_name ?? '');
        const name = display.split(',')[0]?.trim() || 'Place';
        return {
          id: `osm-${r.osm_type ?? 'node'}-${r.osm_id ?? display}`,
          name,
          address: display,
          lat: Number(r.lat),
          lng: Number(r.lon),
        };
      });
  }
}
