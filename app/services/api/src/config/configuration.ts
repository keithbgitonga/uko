export default () => ({
  env: process.env.NODE_ENV ?? 'development',
  port: Number(process.env.PORT ?? 3000),
  databaseUrl: process.env.DATABASE_URL,
  databaseSsl: process.env.DATABASE_SSL === 'true' || (process.env.DATABASE_URL ?? '').includes('sslmode=require'),
  authStore: process.env.AUTH_STORE ?? (process.env.DATABASE_URL ? 'postgres' : 'memory'),
  persistenceStore:
    process.env.PERSISTENCE_STORE ?? (process.env.DATABASE_URL ? 'postgres' : 'memory'),
  jwt: {
    accessSecret: process.env.JWT_ACCESS_SECRET ?? 'dev-access-secret-change-me',
    refreshSecret: process.env.JWT_REFRESH_SECRET ?? 'dev-refresh-secret-change-me',
    accessTtl: Number(process.env.ACCESS_TOKEN_TTL ?? 900),
    refreshTtl: Number(process.env.REFRESH_TOKEN_TTL ?? 2592000),
  },
  alerts: {
    webhookUrl: process.env.ALERT_WEBHOOK_URL ?? '',
  },
  documents: {
    required: (process.env.DOCUMENTS_REQUIRED ?? 'false').toLowerCase() === 'true',
  },
  push: {
    provider: process.env.PUSH_PROVIDER ?? 'dev',
    baseUrl: process.env.PUSH_BASE_URL ?? 'https://fcm.googleapis.com',
    serverKey: process.env.FCM_SERVER_KEY ?? process.env.PUSH_SERVER_KEY ?? '',
    projectId: process.env.FCM_PROJECT_ID ?? '',
    clientEmail: process.env.FCM_CLIENT_EMAIL ?? '',
    privateKey: (process.env.FCM_PRIVATE_KEY ?? '').replace(/\\n/g, '\n'),
    oauthUrl: process.env.FCM_OAUTH_URL ?? 'https://oauth2.googleapis.com/token',
  },
  mpesa: {
    provider: process.env.MPESA_PROVIDER ?? 'mock',
    baseUrl: process.env.DARAJA_BASE_URL ?? 'https://sandbox.safaricom.co.ke',
    consumerKey: process.env.DARAJA_CONSUMER_KEY ?? '',
    consumerSecret: process.env.DARAJA_CONSUMER_SECRET ?? '',
    passkey: process.env.DARAJA_PASSKEY ?? '',
    shortcode: process.env.DARAJA_SHORTCODE ?? '',
    callbackUrl: process.env.DARAJA_CALLBACK_URL ?? '',
    callbackSecret: process.env.DARAJA_CALLBACK_SECRET ?? '',
  },
  sms: {
    provider: process.env.SMS_PROVIDER ?? 'dev',
    baseUrl: process.env.SMS_BASE_URL ?? 'https://api.africastalking.com',
    username: process.env.AT_USERNAME ?? '',
    apiKey: process.env.AT_API_KEY ?? '',
    senderId: process.env.AT_SENDER_ID ?? '',
  },
  routing: {
    osrmUrl: process.env.OSRM_URL ?? 'https://router.project-osrm.org/route/v1/driving',
    userAgent: process.env.ROUTING_USER_AGENT ?? 'Uko/0.1 (pilot; ops@uko.example)',
  },
  places: {
    nominatimUrl: process.env.NOMINATIM_URL ?? 'https://nominatim.openstreetmap.org/search',
    userAgent: process.env.PLACES_USER_AGENT ?? 'Uko/0.1 (pilot; ops@uko.example)',
  },
  dispatchPhones: (process.env.DISPATCH_PHONES ?? '')
    .split(',')
    .map((phone) => phone.trim())
    .filter(Boolean),
  rateLimit: {
    otpPerPhoneHour: Number(process.env.OTP_RATE_PER_PHONE_HOUR ?? 3),
    otpPerIpHour: Number(process.env.OTP_RATE_PER_IP_HOUR ?? 10),
    verifyPerPhone10Min: Number(process.env.OTP_VERIFY_PER_PHONE10MIN ?? 10),
  },
  otp: {
    ttlSeconds: Number(process.env.OTP_TTL_SECONDS ?? 300),
    maxAttempts: Number(process.env.OTP_MAX_ATTEMPTS ?? 5),
    exposeDevOtp: process.env.EXPOSE_DEV_OTP !== 'false',
  },
});
