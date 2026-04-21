import { readdir, readFile } from 'node:fs/promises'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { neon } from '@neondatabase/serverless'

/**
 * Minimal migration runner — applies any .sql file in migrations/ that hasn't
 * been applied yet. Good enough for our tiny schema; swap to drizzle's bundled
 * runner later if we outgrow this.
 */

const __dirname = dirname(fileURLToPath(import.meta.url))
const migrationsDir = join(__dirname, '../../migrations')

async function main() {
    const databaseUrl = process.env.DATABASE_URL
    if (!databaseUrl) throw new Error('DATABASE_URL is not set')

    const sql = neon(databaseUrl)

    await sql`
        create table if not exists schema_migrations (
            name text primary key,
            applied_at timestamptz not null default now()
        )
    `

    const rows = (await sql`select name from schema_migrations`) as Array<{ name: string }>
    const applied = new Set(rows.map((r) => r.name))

    const files = (await readdir(migrationsDir))
        .filter((f) => f.endsWith('.sql'))
        .sort()

    for (const file of files) {
        if (applied.has(file)) continue
        const contents = await readFile(join(migrationsDir, file), 'utf8')
        process.stdout.write(`→ applying ${file}… `)
        // Split on statement boundaries so each one is executed separately by the
        // serverless driver, which doesn't support multi-statement strings.
        const statements = contents
            .split(/;\s*$/m)
            .map((s) => s.trim())
            .filter((s) => s.length > 0)
        for (const stmt of statements) {
            // neon() returns a tagged-template function; call it with a single
            // element array to execute raw SQL strings.
            // eslint-disable-next-line no-await-in-loop
            await sql([stmt] as unknown as TemplateStringsArray)
        }
        await sql`insert into schema_migrations (name) values (${file})`
        console.log('done.')
    }
    console.log('✓ up to date')
}

main().catch((err) => {
    console.error(err)
    process.exit(1)
})
