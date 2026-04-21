-- Drop the SIWA-era schema and rebuild for anonymous device pairing.

drop table if exists api_keys cascade;
drop table if exists devices cascade;
drop table if exists users cascade;

create table devices (
    id             uuid primary key default gen_random_uuid(),
    apns_token     text not null unique,
    bundle_id      text not null,
    environment    text not null,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    last_pushed_at timestamptz,
    is_active      boolean not null default true
);

create table api_keys (
    id            uuid primary key default gen_random_uuid(),
    device_id     uuid not null references devices(id) on delete cascade,
    key_hash      text not null,
    key_prefix    text not null,
    label         text,
    created_at    timestamptz not null default now(),
    last_used_at  timestamptz,
    revoked_at    timestamptz
);
create index api_keys_hash_idx on api_keys(key_hash) where revoked_at is null;

create table pair_codes (
    code         text primary key,
    apns_token   text not null,
    bundle_id    text not null,
    environment  text not null,
    created_at   timestamptz not null default now(),
    expires_at   timestamptz not null,
    claimed      boolean not null default false,
    device_id    uuid references devices(id) on delete set null,
    api_key_id   uuid references api_keys(id) on delete set null
);
create index pair_codes_expires_idx on pair_codes(expires_at);
