/**
 * Dynamic Price Collection Scheduler
 *
 * Intelligently adjusts collection frequency based on game timing:
 * - High frequency (2 min): When games start within 10 min OR active games exist
 * - Low frequency (10 min): Normal operation when no games are imminent
 */

import { shouldUseHighFrequency, close } from './db';
import { collectPrices } from './collect-prices';

/**
 * Sleep for specified milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Format milliseconds to human-readable duration
 */
function formatDuration(ms: number): string {
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.floor((ms % 60000) / 1000);
  return `${minutes}m ${seconds}s`;
}

/**
 * Main scheduler loop
 */
async function scheduler(): Promise<void> {
  console.log(`\n${"=".repeat(70)}`);
  console.log(`POLYMARKET PRICE COLLECTION SCHEDULER`);
  console.log(`Dynamic intervals: 2 min (active) | 10 min (idle)`);
  console.log(`${"=".repeat(70)}\n`);

  let runCount = 0;

  while (true) {
    runCount++;
    const cycleStart = Date.now();

    console.log(`\n${"─".repeat(70)}`);
    console.log(`[${new Date().toISOString()}] Cycle #${runCount} starting`);
    console.log(`${"─".repeat(70)}`);

    try {
      // Check if we need high-frequency collection
      const frequencyCheck = await shouldUseHighFrequency();

      console.log(`\n[SCHEDULER] Frequency check:`);
      console.log(`  Mode: ${frequencyCheck.highFrequency ? 'HIGH (2 min)' : 'LOW (10 min)'}`);
      console.log(`  Reason: ${frequencyCheck.reason}`);
      if (frequencyCheck.nextGameStart) {
        console.log(`  Next game: ${frequencyCheck.nextGameStart.toISOString()}`);
      }

      // Run the price collection
      console.log(`\n[SCHEDULER] Starting price collection...`);
      await collectPrices();

      // Determine next interval
      const intervalMs = frequencyCheck.highFrequency
        ? 2 * 60 * 1000  // 2 minutes
        : 10 * 60 * 1000; // 10 minutes

      const cycleDuration = Date.now() - cycleStart;
      const sleepTime = Math.max(0, intervalMs - cycleDuration);

      console.log(`\n[SCHEDULER] Cycle completed in ${formatDuration(cycleDuration)}`);
      console.log(`[SCHEDULER] Next collection in ${formatDuration(sleepTime)}`);
      console.log(`${"─".repeat(70)}\n`);

      // Wait before next collection
      if (sleepTime > 0) {
        await sleep(sleepTime);
      }

    } catch (error) {
      console.error(`\n[ERROR] Scheduler cycle failed:`, error);
      console.error(`[SCHEDULER] Waiting 1 minute before retry...\n`);
      await sleep(60000); // Wait 1 minute on error
    }
  }
}

/**
 * Graceful shutdown handler
 */
async function shutdown(signal: string): Promise<void> {
  console.log(`\n[SHUTDOWN] Received ${signal}, cleaning up...`);
  await close();
  process.exit(0);
}

// Handle shutdown signals
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Handle uncaught errors
process.on('uncaughtException', (error) => {
  console.error('[FATAL] Uncaught exception:', error);
  close().finally(() => process.exit(1));
});

process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] Unhandled rejection:', reason);
  close().finally(() => process.exit(1));
});

// Start the scheduler
if (require.main === module) {
  scheduler().catch((error) => {
    console.error('[FATAL] Scheduler failed to start:', error);
    close().finally(() => process.exit(1));
  });
}
