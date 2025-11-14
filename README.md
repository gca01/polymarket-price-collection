# Polymarket Price Collector

Automated price data collection for Polymarket prediction markets. Runs every 5 minutes via GitHub Actions to collect and store historical price data for backtesting and analytics.

## Purpose

This collector:

- Fetches current prices for all active Polymarket markets every 5 minutes
- Stores time-series data in PostgreSQL for historical analysis
- Runs on GitHub Actions

## Architecture

`GitHub Actions (every 5 min) -> Polymarket CLOB API -> PostgreSQL Database`

## Prerequisites

1. PostgreSQL database
2. A `games` table in your database with active market (game) entries
3. GitHub account

## Setup Instructions

### Step 1: Run Database Migration

In your existing PostgreSQL database, run the migration:

```bash
psql $DATABASE_URL -f migrations/001_add_price_tracking.sql
```

This creates:

- `market_prices` table (time-series price data)
- `market_price_extremes` table (analytics/extremes)
- Automatic trigger to update extremes on new prices

### Step 2: Add Database Secret to GitHub

1. Go to your repo on GitHub
2. **Settings** -> **Secrets and variables** -> **Actions** -> **New repository secret**
3. Name: `DATABASE_URL`
4. Value: Your PostgreSQL connection string
5. Click **Add secret**

### Step 3: Push Code and Enable Actions

```bash
git add .
git commit -m "Initial commit: Polymarket price collector"
git push origin main
```

After pushing:

1. Go to the **Actions** tab in your GitHub repo
2. You should see the workflow appear
3. It will run immediately on first push
4. Then it will run automatically every 5 minutes

### Step 4: Verify It's Working

**Option A: Check GitHub Actions**

1. Go to **Actions** tab
2. Click on the latest workflow run
3. You should see logs like:
   ```
   Success: Found 10 active games to track
   Success: Successfully stored 20 prices
   ```

**Option B: Check Database**

```sql
-- See latest prices collected
SELECT
  condition_id,
  outcome,
  price,
  timestamp
FROM market_prices
ORDER BY timestamp DESC
LIMIT 10;

-- Check price extremes
SELECT
  condition_id,
  outcome,
  lowest_price,
  highest_price,
  current_price
FROM market_price_extremes;
```

## Configuration

### Adjust Collection Frequency

Edit `.github/workflows/collect-prices.yml`:

```yaml
schedule:
  - cron: "*/5 * * * *" # Every 5 minutes (minimum for GitHub)
  # - cron: '*/15 * * * *'  # Every 15 minutes
  # - cron: '0 * * * *'     # Every hour
```

**Note**: GitHub Actions minimum interval is 5 minutes.

### Rate Limiting

The collector respects Polymarket's rate limits:

- Max 90 requests per minute (stays under 100/min limit)
- Automatic retry with 30s backoff on 429 errors
- ~667ms delay between requests

## Data Schema

### `market_prices` Table

| Column         | Type      | Description                          |
| -------------- | --------- | ------------------------------------ |
| `condition_id` | VARCHAR   | Game/market ID (links to `games.id`) |
| `token_id`     | VARCHAR   | Outcome token ID                     |
| `outcome`      | VARCHAR   | Outcome name (e.g., "Lakers", "Yes") |
| `price`        | DECIMAL   | Price 0-1 range (0.65 = 65%)         |
| `timestamp`    | TIMESTAMP | When price was recorded              |
| `source`       | VARCHAR   | 'rest', 'websocket', 'backfill'      |

### `market_price_extremes` Table

| Column                    | Type      | Description             |
| ------------------------- | --------- | ----------------------- |
| `condition_id`            | VARCHAR   | Game/market ID          |
| `token_id`                | VARCHAR   | Outcome token ID        |
| `outcome`                 | VARCHAR   | Outcome name            |
| `lowest_price`            | DECIMAL   | Lowest price ever seen  |
| `lowest_price_timestamp`  | TIMESTAMP | When lowest occurred    |
| `highest_price`           | DECIMAL   | Highest price ever seen |
| `highest_price_timestamp` | TIMESTAMP | When highest occurred   |
| `current_price`           | DECIMAL   | Most recent price       |

## Testing Locally

```bash
# Install dependencies
npm install

# Create .env file
cp .env.example .env
# Edit .env and add your DATABASE_URL

# Run collector once
npm run collect
```

## Troubleshooting

### "No active games found"

Your `games` table is empty or has no upcoming games. Populate your games table with active games.

### "Connection failed"

Check that `DATABASE_URL` secret is set correctly in GitHub Settings -> Secrets.

### "Rate limited"

The collector automatically retries after 30s. If persistent, reduce collection frequency.

### Workflow not running

1. Check **Actions** tab is enabled (Settings -> Actions -> Allow all actions)
2. Ensure repository is public (for free tier)
3. Check workflow file is in `.github/workflows/`

## License

MIT

## Contributing

This is a simple data collector. Feel free to fork and customize for your needs!
