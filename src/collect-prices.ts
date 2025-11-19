/**
 * Polymarket Price Collector
 * Fetches current prices for active markets and stores them in the database
 *
 * Optimization: Uses token IDs from Gamma API (clobTokenIds field) stored in database
 * instead of making extra CLOB API calls to /markets endpoint. This reduces API calls by ~33%.
 */

import {
  batchInsertPrices,
  close,
  getActiveGames,
} from './db';

const CLOB_BASE_URL = "https://clob.polymarket.com";

// Rate limiting: Max 90 requests per minute to stay under 100/min limit
const RATE_LIMIT_PER_MINUTE = 90;
const DELAY_BETWEEN_REQUESTS = Math.ceil(60000 / RATE_LIMIT_PER_MINUTE); // ~667ms

/**
 * Sleep for specified milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Fetch current price for a token from Polymarket CLOB API
 * Uses SELL side (ask price) - the price you'd pay to buy shares
 */
async function fetchTokenPrice(tokenId: string): Promise<number | null> {
  try {
    const url = `${CLOB_BASE_URL}/price?token_id=${tokenId}&side=SELL`;
    const response = await fetch(url);

    if (!response.ok) {
      if (response.status === 429) {
        console.warn(`[API] Rate limited, waiting 30 seconds...`);
        await sleep(30000);
        return fetchTokenPrice(tokenId); // Retry
      }
      console.error(
        `[API] Failed to fetch price for token ${tokenId}: ${response.status}`
      );
      return null;
    }

    const data = (await response.json()) as { price?: string; mid?: string };

    // Response format: { price: "0.65" } or { mid: "0.65" }
    const price = data.price || data.mid;

    if (price === undefined || price === null) {
      console.warn(`[API] No price data for token ${tokenId}`);
      return null;
    }

    return parseFloat(price);
  } catch (error) {
    console.error(`[API] Error fetching price for token ${tokenId}:`, error);
    return null;
  }
}

/**
 * Main collection function
 */
async function collectPrices(): Promise<void> {
  const startTime = Date.now();
  console.log(`\n${"=".repeat(60)}`);
  console.log(`[${new Date().toISOString()}] Starting price collection`);
  console.log(`${"=".repeat(60)}\n`);

  try {
    // Get all active games from database
    const games = await getActiveGames();
    console.log(`[INFO] Found ${games.length} active games to track`);

    if (games.length === 0) {
      console.log("[INFO] No active games found. Exiting.");
      return;
    }

    const priceRecords: Array<{
      conditionId: string;
      tokenId: string;
      outcome: string;
      price: number;
      timestamp: Date;
      source: string;
    }> = [];

    const timestamp = new Date();
    let requestCount = 0;
    let successCount = 0;
    let failureCount = 0;

    // Fetch prices for each market outcome
    for (const game of games) {
      console.log(`\n[GAME] ${game.title} (${game.id})`);

      for (const market of game.markets) {
        // Check if market has outcomes with token IDs (from Gamma API clobTokenIds)
        if (!market.outcomes || market.outcomes.length === 0) {
          console.log(`Warning: No outcomes for market ${market.marketSlug}`);
          continue;
        }

        // Fetch price for each outcome
        for (const outcome of market.outcomes) {
          // Skip outcomes without token IDs
          if (!outcome.tokenID) {
            console.log(`Warning: No token ID for outcome: ${outcome.title}`);
            continue;
          }

          // Rate limiting delay
          if (requestCount > 0 && requestCount % 10 === 0) {
            console.log(
              `Progress: ${requestCount} requests made, waiting to respect rate limits...`
            );
            await sleep(DELAY_BETWEEN_REQUESTS);
          }

          const price = await fetchTokenPrice(outcome.tokenID);
          requestCount++;

          if (price !== null) {
            priceRecords.push({
              conditionId: market.conditionId,
              tokenId: outcome.tokenID,
              outcome: outcome.title,
              price,
              timestamp,
              source: "rest",
            });
            successCount++;
            console.log(
              `Success ${outcome.title}: ${price}`
            );
          } else {
            failureCount++;
            console.log(`Failure ${outcome.title}: Failed to fetch price`);
          }

          // Small delay between requests
          await sleep(DELAY_BETWEEN_REQUESTS);
        }
      }
    }

    // Batch insert all collected prices
    if (priceRecords.length > 0) {
      console.log(`\n[DB] Inserting ${priceRecords.length} price records...`);
      await batchInsertPrices(priceRecords);
      console.log(`[DB] Successfully stored ${priceRecords.length} prices`);
    } else {
      console.log(`\n[WARN] No prices collected - nothing to insert`);
    }

    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`\n${"=".repeat(60)}`);
    console.log(`[SUMMARY] Collection completed in ${duration}s`);
    console.log(`Games processed: ${games.length}`);
    console.log(`API requests: ${requestCount}`);
    console.log(`Successful: ${successCount}`);
    console.log(`Failed: ${failureCount}`);
    console.log(`Prices stored: ${priceRecords.length}`);
    console.log(`${"=".repeat(60)}\n`);
  } catch (error) {
    console.error("\n[ERROR] Collection failed:", error);
    throw error;
  }
}

/**
 * Main entry point
 */
async function main(): Promise<void> {
  try {
    await collectPrices();
  } catch (error) {
    console.error("[FATAL] Unhandled error:", error);
    process.exit(1);
  } finally {
    await close();
  }
}

// Export for use by scheduler
export { collectPrices };

// Run if executed directly
if (require.main === module) {
  main();
}
