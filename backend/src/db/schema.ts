import { sql } from 'drizzle-orm'
import {
    pgTable,
    uuid,
    text,
    timestamp,
    boolean,
    uniqueIndex,
    index,
} from 'drizzle-orm/pg-core'

export const users = pgTable('users', {
    id: uuid('id').primaryKey().defaultRandom(),
    appleSub: text('apple_sub').notNull().unique(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

export const devices = pgTable(
    'devices',
    {
        id: uuid('id').primaryKey().defaultRandom(),
        userId: uuid('user_id')
            .notNull()
            .references(() => users.id, { onDelete: 'cascade' }),
        apnsToken: text('apns_token').notNull(),
        bundleId: text('bundle_id').notNull(),
        environment: text('environment').notNull(), // 'sandbox' | 'production'
        updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
        lastPushedAt: timestamp('last_pushed_at', { withTimezone: true }),
        isActive: boolean('is_active').notNull().default(true),
    },
    (t) => ({
        userTokenUnique: uniqueIndex('devices_user_token_idx').on(t.userId, t.apnsToken),
        activeByUser: index('devices_active_user_idx').on(t.userId, t.isActive),
    }),
)

export const apiKeys = pgTable(
    'api_keys',
    {
        id: uuid('id').primaryKey().defaultRandom(),
        userId: uuid('user_id')
            .notNull()
            .references(() => users.id, { onDelete: 'cascade' }),
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

export type User = typeof users.$inferSelect
export type Device = typeof devices.$inferSelect
export type ApiKey = typeof apiKeys.$inferSelect
