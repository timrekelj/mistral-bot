-- Extensions used by the runtime. pg_net/pg_cron drive the kick loop and sweeper.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists vector with schema extensions;
create extension if not exists pgcrypto with schema extensions;

grant usage on schema cron to postgres;

-- Internal helpers live in `private`, which is never exposed through the Data API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
