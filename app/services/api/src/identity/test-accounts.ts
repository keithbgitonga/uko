export type TestRole = 'rider' | 'driver' | 'dispatch' | 'safety' | 'admin';

export interface TestAccount {
  role: TestRole;
  phone: string;
  name: string;
  description: string;
  app: 'rider' | 'driver' | 'dispatch';
}

/**
 * Easy pilot/demo accounts. Only usable when ALLOW_TEST_LOGINS=true.
 * Phones are fixed so the same account is reused across deploys.
 */
export const TEST_ACCOUNTS: TestAccount[] = [
  {
    role: 'rider',
    phone: '+254712345678',
    name: 'Test Rider',
    description: 'Book a Boda, see live ETA and trip history',
    app: 'rider',
  },
  {
    role: 'driver',
    phone: '+254700000001',
    name: 'Peter M. (Test Driver)',
    description: 'Go online, accept offers and run a trip',
    app: 'driver',
  },
  {
    role: 'dispatch',
    phone: '+254700000010',
    name: 'Test Dispatcher',
    description: 'Overview, rides, incidents, scheduled and audit',
    app: 'dispatch',
  },
  {
    role: 'safety',
    phone: '+254700000011',
    name: 'Test Safety Lead',
    description: 'SOS/incident response and rider safety checks',
    app: 'dispatch',
  },
  {
    role: 'admin',
    phone: '+254700000012',
    name: 'Test Admin',
    description: 'Documents, money/reconciliation and system health',
    app: 'dispatch',
  },
];

export const TEST_OPS_ROLES: TestRole[] = ['dispatch', 'safety', 'admin'];
