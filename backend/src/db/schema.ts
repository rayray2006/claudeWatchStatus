import { sql } from 'drizzle-orm'
import {
    pgTable,
    uuid,
    text,
    timestamp,
    boolean,
    index,
} from 'drizzle-orm/pg-core'

export const devices = pgTable('devices', {
    id: uuid('id').primaryKey().defaultRandom(),
    apnsToken: text('apns_token').notNull().unique(),
    bundleId: text('bundle_id').notNull(),
    environment: text('environment').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
    lastPushedAt: timestamp('last_pushed_at', { withTimezone: true }),
    isActive: boolean('is_active').notNull().default(true),
})

export const apiKeys = pgTable(
    'api_keys',
    {
        id: uuid('id').primaryKey().defaultRandom(),
        deviceId: uuid('device_id')
            .notNull()
            .references(() => devices.id, { onDelete: 'cascade' }),
        keyHash: text('key_hash').notNull(),
        keyPrefix: text('key_prefix').notNull(),
        label: text('label'),
        createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
        lastUsedAt: timestamp('last_used_at', { withTimezone: true }),
        revokedAt: timestamp('revoked_at', { withTimezone: true }),
    },
    (t) => ({
        activeByHash: index('api_keys_hash_idx')
            .on(t.keyHash)
            .where(sql`${t.revokedAt} is null`),
    }),
)

export const pairCodes = pgTable(
    'pair_codes',
    {
        code: text('code').primaryKey(),
        apnsToken: text('apns_token').notNull(),
        bundleId: text('bundle_id').notNull(),
        environment: text('environment').notNull(),
        createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
        expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
        claimed: boolean('claimed').notNull().default(false),
        deviceId: uuid('device_id').references(() => devices.id, { onDelete: 'set null' }),
        apiKeyId: uuid('api_key_id').references(() => apiKeys.id, { onDelete: 'set null' }),
    },
    (t) => ({
        byExpires: index('pair_codes_expires_idx').on(t.expiresAt),
    }),
)

export type Device = typeof devices.$inferSelect
export type ApiKey = typeof apiKeys.$inferSelect
export type PairCode = typeof pairCodes.$inferSelect
