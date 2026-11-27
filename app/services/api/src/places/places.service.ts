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
  { id: 'seed-juja-town', name: 'Juja Town', address: 'Juja Town, Kiambu County', lat: -1.1017, lng: 37.0144 },
  { id: 'seed-jkuat', name: 'JKUAT', address: 'Jomo Kenyatta University of Agriculture and Technology, Juja', lat: -1.0973, lng: 37.0118 },
  { id: 'seed-juja-mall', name: 'Juja City Mall', address: 'Juja City Mall, Juja', lat: -1.1058, lng: 37.0140 },
  { id: 'seed-gachororo', name: 'Gachororo', address: 'Gachororo, Juja', lat: -1.1122, lng: 37.0207 },
  { id: 'seed-kenyatta-road', name: 'Kenyatta Road', address: 'Kenyatta Road, Juja', lat: -1.1010, lng: 37.0080 },
  { id: 'seed-ruiru', name: 'Ruiru', address: 'Ruiru, Kiambu County', lat: -1.1460, lng: 36.9600 },
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
    const raw = query.trim();
    const q = raw.toLowerCase();
    if (q.length < 2) return [];
    const cached = this.cache.get(q);
    if (cached && cached.at > Date.now() - 3_600_000) return cached.places;

    const scoredSeed = SEED.map((place, index) => ({
      place,
      score: scorePlace(place, q) + Math.max(0, 20 - index),
    }))
      .filter((entry) => entry.score > 0)
      .sort((a, b) => b.score - a.score)
      .map((entry) => entry.place);

    let remote: PlaceResult[] = [];
    try {
      remote = await this.nominatim(raw);
    } catch {
      remote = [];
    }

    const seen = new Set<string>();
    const places: PlaceResult[] = [];
    for (const place of [...remote, ...scoredSeed]) {
      const key = `${place.name.toLowerCase()}|${place.lat.toFixed(4)}|${place.lng.toFixed(4)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      places.push(place);
    }
    // Keep Juja-area results ahead of distant matches unless the name/address match is much stronger.
    places.sort((a, b) =>
      (scorePlace(b, q) + proximityBonus(b)) - (scorePlace(a, q) + proximityBonus(a)),
    );
    places.splice(8);
    this.cache.set(q, { at: Date.now(), places });
    if (this.cache.size > 500) this.cache.delete(this.cache.keys().next().value as string);
    return places;
  }

  /** Reverse geocode the rider's current position for a human pickup label. */
  async reverse(lat: number, lng: number): Promise<PlaceResult> {
    try {
      const base = (this.config.get<string>('places.nominatimUrl') ?? '').replace('/search', '/reverse');
      const url = new URL(base);
      url.searchParams.set('format', 'jsonv2');
      url.searchParams.set('lat', String(lat));
      url.searchParams.set('lon', String(lng));
      url.searchParams.set('zoom', '18');
      url.searchParams.set('addressdetails', '1');
      url.searchParams.set('accept-language', 'en');
      const response = await fetch(url, {
        headers: { 'user-agent': this.config.get<string>('places.userAgent')!, accept: 'application/json' },
        signal: AbortSignal.timeout(4_000),
      });
      if (!response.ok) throw new Error(`nominatim_reverse_http_${response.status}`);
      const row: any = await response.json();
      const display = String(row.display_name ?? '').trim();
      if (display) {
        return {
          id: `current-${lat.toFixed(5)}-${lng.toFixed(5)}`,
          name: display.split(',')[0]?.trim() || 'Current location',
          address: display,
          lat,
          lng,
        };
      }
    } catch {
      // fall through to a coordinate label
    }
    return {
      id: `current-${lat.toFixed(5)}-${lng.toFixed(5)}`,
      name: 'Current location',
      address: `${lat.toFixed(5)}, ${lng.toFixed(5)}`,
      lat,
      lng,
    };
  }

  private async nominatim(query: string): Promise<PlaceResult[]> {
    const base = this.config.get<string>('places.nominatimUrl')!;
    const userAgent = this.config.get<string>('places.userAgent')!;
    const url = new URL(base);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('q', query);
    url.searchParams.set('countrycodes', 'ke');
    url.searchParams.set('limit', '8');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('dedupe', '1');
    url.searchParams.set('accept-language', 'en');
    url.searchParams.set('bounded', '0');
    url.searchParams.set('viewbox', '36.90,-1.00,37.20,-1.30');
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


function scorePlace(place: PlaceResult, q: string): number {
  const name = place.name.toLowerCase();
  const address = place.address.toLowerCase();
  const words = q.split(/\s+/).filter(Boolean);
  if (name === q) return 100;
  if (name.startsWith(q)) return 90;
  if (words.every((word) => name.split(/\s+/).some((part) => part.startsWith(word)))) return 80;
  if (name.includes(q)) return 70;
  if (address.includes(q)) return 50;
  if (words.every((word) => address.includes(word))) return 30;
  return 0;
}


const JUJA_CENTER = { lat: -1.1017, lng: 37.0144 };

function proximityBonus(place: PlaceResult): number {
  const latM = (place.lat - JUJA_CENTER.lat) * 111_000;
  const lngM = (place.lng - JUJA_CENTER.lng) * 111_000 * Math.cos(JUJA_CENTER.lat * Math.PI / 180);
  const km = Math.sqrt(latM * latM + lngM * lngM) / 1000;
  if (km <= 8) return 45;
  if (km <= 20) return 25;
  if (km <= 40) return 10;
  return 0;
}
