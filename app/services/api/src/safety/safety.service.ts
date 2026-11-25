import { BadRequestException, Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { AnalyticsService } from '../observability/analytics.service';
import { PersistenceService } from '../persistence/persistence.service';

export interface EmergencyContact {
  id: string;
  riderId: string;
  name: string;
  phone: string;
  relationship?: string;
  createdAt: string;
}

export type IncidentState = 'OPEN' | 'ACKED' | 'RESOLVED' | 'CANCELLED';

export interface SafetyIncident {
  id: string;
  riderId: string;
  rideId?: string;
  type: 'SOS';
  state: IncidentState;
  lat?: number;
  lng?: number;
  note?: string;
  contacts: { name: string; phone: string }[];
  events: { at: string; state: string; note?: string }[];
  createdAt: string;
}

const OPS_ACK_AFTER_MS = 5000;

/**
 * Safety store for the MVP: emergency contacts and SOS incidents with a
 * simulated private-response acknowledgement (ops on-call + private responder;
 * the pilot does not dial 999). Postgres repositories land in the DB sprint.
 */
@Injectable()
export class SafetyService implements OnModuleInit {
  private contacts = new Map<string, EmergencyContact[]>();
  private incidents = new Map<string, SafetyIncident>();

  constructor(
    private readonly persistence: PersistenceService,
    private readonly analytics: AnalyticsService,
  ) {}

  async onModuleInit(): Promise<void> {
    const contacts = await this.persistence.load<EmergencyContact>('safety_contact');
    for (const contact of contacts.values()) {
      const list = this.contacts.get(contact.riderId) ?? [];
      list.push(contact);
      this.contacts.set(contact.riderId, list);
    }
    this.incidents = await this.persistence.load<SafetyIncident>('safety_incident');
  }

  listContacts(riderId: string): EmergencyContact[] {
    return this.contacts.get(riderId) ?? [];
  }

  addContact(riderId: string, name: string, phone: string, relationship?: string): EmergencyContact {
    const contact: EmergencyContact = {
      id: `ec_${randomUUID()}`,
      riderId,
      name,
      phone,
      relationship,
      createdAt: new Date().toISOString(),
    };
    const list = this.contacts.get(riderId) ?? [];
    list.push(contact);
    this.contacts.set(riderId, list);
    this.persistence.persist('safety_contact', contact.id, contact);
    return contact;
  }

  removeContact(riderId: string, id: string): { removed: boolean } {
    const list = this.contacts.get(riderId) ?? [];
    const next = list.filter((c) => c.id !== id);
    this.contacts.set(riderId, next);
    this.persistence.remove('safety_contact', id);
    return { removed: next.length !== list.length };
  }

  triggerSos(
    riderId: string,
    input: { rideId?: string; lat?: number; lng?: number; note?: string },
  ): SafetyIncident {
    if (!input.lat && !input.lng && !input.note) {
      // Still allowed: the SOS is tied to the rider account/trip.
    }
    const now = new Date().toISOString();
    const incident: SafetyIncident = {
      id: `sos_${randomUUID()}`,
      riderId,
      rideId: input.rideId,
      type: 'SOS',
      state: 'OPEN',
      lat: input.lat,
      lng: input.lng,
      note: input.note,
      contacts: this.listContacts(riderId).map((c) => ({ name: c.name, phone: c.phone })),
      events: [{ at: now, state: 'OPEN', note: 'SOS received; Uko? ops on-call notified' }],
      createdAt: now,
    };
    this.incidents.set(incident.id, incident);
    this.persistence.persist('safety_incident', incident.id, incident);
    this.analytics.record(riderId, 'sos_triggered', { incidentId: incident.id, hasNote: !!input.note });
    return incident;
  }

  getIncident(riderId: string, id: string): SafetyIncident {
    const incident = this.incidents.get(id);
    if (!incident || incident.riderId !== riderId) throw new NotFoundException({ code: 'INCIDENT_NOT_FOUND' });
    return this.advance(incident);
  }

  listIncidents(riderId: string): SafetyIncident[] {
    return [...this.incidents.values()]
      .filter((i) => i.riderId === riderId)
      .map((i) => this.advance(i))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  allIncidents(): SafetyIncident[] {
    return [...this.incidents.values()]
      .map((i) => this.advance(i))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  resolveIncident(id: string): SafetyIncident {
    const incident = this.incidents.get(id);
    if (!incident) throw new NotFoundException({ code: 'INCIDENT_NOT_FOUND' });
    if (['RESOLVED', 'CANCELLED'].includes(incident.state)) return incident;
    incident.state = 'RESOLVED';
    incident.events.push({ at: new Date().toISOString(), state: 'RESOLVED', note: 'Resolved by dispatch' });
    this.persistence.persist('safety_incident', incident.id, incident);
    return incident;
  }

  cancelIncident(riderId: string, id: string): SafetyIncident {
    const incident = this.getIncident(riderId, id);
    if (['RESOLVED', 'CANCELLED'].includes(incident.state)) {
      throw new BadRequestException({ code: 'INCIDENT_NOT_ACTIVE' });
    }
    incident.state = 'CANCELLED';
    incident.events.push({
      at: new Date().toISOString(),
      state: 'CANCELLED',
      note: 'Rider marked this as a false alarm',
    });
    this.persistence.persist('safety_incident', incident.id, incident);
    return incident;
  }

  /** Simulated private-response acknowledgement for the walking skeleton. */
  private advance(incident: SafetyIncident): SafetyIncident {
    if (incident.state !== 'OPEN') return incident;
    if (Date.now() - new Date(incident.createdAt).getTime() >= OPS_ACK_AFTER_MS) {
      incident.state = 'ACKED';
      incident.events.push({
        at: new Date().toISOString(),
        state: 'ACKED',
        note: 'Ops on-call acknowledged; private responder notified',
      });
      this.persistence.persist('safety_incident', incident.id, incident);
    }
    return incident;
  }
}
