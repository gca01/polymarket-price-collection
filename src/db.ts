/**
 * Database connection for price collector
 * Lightweight version - just what we need for inserting prices
 */

import {
  Pool,
  QueryResult,
  QueryResultRow,
} from 'pg';

// Create connection pool
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  // GitHub Actions runs are short-lived, use minimal connections
  max: 2,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
});

/**
 * Execute a SQL query
 */
export async function query<T extends QueryResultRow = any>(
  text: string,
  params?: any[]
): Promise<QueryResult<T>> {
  const start = Date.now();
  try {
    const result = await pool.query<T>(text, params);
    const duration = Date.now() - start;
    console.log(`[DB] Query executed in ${duration}ms`);
    return result;
  } catch (error) {
    console.error("[DB] Query error:", error);
    throw error;
  }
}

/**
 * Insert a price record
 */
export async function insertPrice(data: {
  conditionId: string;
  tokenId: string;
  outcome: string;
  price: number;
  timestamp: Date;
  source?: string;
}): Promise<void> {
  await query(
    `INSERT INTO market_prices (condition_id, token_id, outcome, price, timestamp, source)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (condition_id, token_id, timestamp) DO NOTHING`,
    [
      data.conditionId,
      data.tokenId,
      data.outcome,
      data.price,
      data.timestamp,
      data.source || "rest",
    ]
  );
}

/**
 * Batch insert multiple price records (more efficient)
 */
export async function batchInsertPrices(
  prices: Array<{
    conditionId: string;
    tokenId: string;
    outcome: string;
    price: number;
    timestamp: Date;
    source?: string;
  }>
): Promise<void> {
  if (prices.length === 0) return;

  // Build values array for bulk insert
  const values: any[] = [];
  const placeholders: string[] = [];

  prices.forEach((price, index) => {
    const baseIndex = index * 6;
    placeholders.push(
      `($${baseIndex + 1}, $${baseIndex + 2}, $${baseIndex + 3}, $${
        baseIndex + 4
      }, $${baseIndex + 5}, $${baseIndex + 6})`
    );
    values.push(
      price.conditionId,
      price.tokenId,
      price.outcome,
      price.price,
      price.timestamp,
      price.source || "rest"
    );
  });

  await query(
    `INSERT INTO market_prices (condition_id, token_id, outcome, price, timestamp, source)
     VALUES ${placeholders.join(", ")}
     ON CONFLICT (condition_id, token_id, timestamp) DO NOTHING`,
    values
  );

  console.log(`[DB] Batch inserted ${prices.length} price records`);
}

/**
 * Get active games that need price tracking
 * Only returns games that are:
 * 1. Starting within the next 48 hours, OR
 * 2. Already started but not yet ended (live games)
 * This prevents collecting prices for games that are weeks away
 */
export async function getActiveGames(): Promise<
  Array<{
    id: string;
    title: string;
    markets: Array<{
      marketSlug: string;
      outcomes: Array<{
        outcome: string;
        tokenID: string;
      }>;
    }>;
  }>
> {
  const result = await query<{
    id: string;
    title: string;
    markets: any;
  }>(
    `SELECT id, title, markets
      FROM games
      WHERE closed = false
        AND end_date > NOW()
        AND (
        -- Games that have already started but not ended (live games)
        (start_date <= NOW() AND end_date > NOW())
        OR
        -- Games starting within the next 48 hours
        (start_date > NOW() AND start_date < NOW() + INTERVAL '48 hours')
      )
    ORDER BY start_date ASC`
  );

  return result.rows.map((row: any) => ({
    id: row.id,
    title: row.title,
    markets: row.markets || [],
  }));
}

/**
 * Close database connection (call when script finishes)
 */
export async function close(): Promise<void> {
  await pool.end();
  console.log("[DB] Connection pool closed");
}
