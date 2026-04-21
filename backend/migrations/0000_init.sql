create extension if not exists "pgcrypto";

create table users (
    id          uuid primary key default gen_random_uuid(),
    apple_sub   text unique not null,
    created_at  timestamptz not null default now(),
    deleted_at  timestamptz
);

create table devices (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null references users(id) on delete cascade,
    apns_token      text not null,
    bundle_id       text not null,
    environment     text not null,
    updated_at      timestamptz not null default now(),
    last_pushed_at  timestamptz,
    is_active       boolean not null default true
);
create unique index devices_user_token_idx on devices(user_id, apns_token);
create index devices_active_user_idx on devices(user_id, is_active);

create table api_keys (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references users(id) on delete cascade,
    key_hash      text not null,
    key_prefix    text not null,
    label         text,
    created_at    timestamptz not null default now(),
    last_used_at  timestamptz,
    revoked_at    timestamptz
);
create index api_keys_hash_idx on api_keys(key_hash) where revoked_at is null;
