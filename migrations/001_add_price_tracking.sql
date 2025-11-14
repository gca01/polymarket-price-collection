-- Migration: Add price tracking tables for historical market data
-- Run this migration in your existing PostgreSQL database

-- Create market_prices table for time-series price data
CREATE TABLE IF NOT EXISTS market_prices (
  id BIGSERIAL PRIMARY KEY,

  -- Market identification
  condition_id VARCHAR(255) NOT NULL,      -- Links to games.id
  token_id VARCHAR(255) NOT NULL,          -- CLOB token ID (outcome asset)
  outcome VARCHAR(255),                     -- e.g., "Yes", "No", team name

  -- Price data
  price DECIMAL(18, 8) NOT NULL,           -- Price at this timestamp (0-1 range)

  -- Timestamp
  timestamp TIMESTAMP NOT NULL,             -- When this price was recorded

  -- Metadata
  source VARCHAR(50) DEFAULT 'rest',       -- 'rest', 'websocket', or 'backfill'
  created_at TIMESTAMP DEFAULT NOW(),

  -- Ensure no duplicate prices for same market/token/time
  UNIQUE(condition_id, token_id, timestamp)
);

-- Indexes for fast time-series queries
CREATE INDEX IF NOT EXISTS idx_market_prices_condition ON market_prices(condition_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_market_prices_token ON market_prices(token_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_market_prices_timestamp ON market_prices(timestamp DESC);

-- Composite index for common queries (get price history for a specific market outcome)
CREATE INDEX IF NOT EXISTS idx_market_prices_lookup ON market_prices(condition_id, outcome, timestamp DESC);

-- Create market_price_extremes table for quick analytics
CREATE TABLE IF NOT EXISTS market_price_extremes (
  id SERIAL PRIMARY KEY,
  condition_id VARCHAR(255) NOT NULL,
  token_id VARCHAR(255) NOT NULL,
  outcome VARCHAR(255),

  -- Extreme prices (for backtesting strategies)
  lowest_price DECIMAL(18, 8),
  lowest_price_timestamp TIMESTAMP,
  highest_price DECIMAL(18, 8),
  highest_price_timestamp TIMESTAMP,

  -- Current price (latest known)
  current_price DECIMAL(18, 8),
  current_price_timestamp TIMESTAMP,

  -- Time range
  first_recorded TIMESTAMP,
  last_updated TIMESTAMP DEFAULT NOW(),

  UNIQUE(condition_id, token_id)
);

-- Indexes for extremes table
CREATE INDEX IF NOT EXISTS idx_extremes_condition ON market_price_extremes(condition_id);
CREATE INDEX IF NOT EXISTS idx_extremes_token ON market_price_extremes(token_id);

-- Grant permissions to app_user (adjust if using different user)
GRANT ALL PRIVILEGES ON TABLE market_prices TO app_user;
GRANT ALL PRIVILEGES ON TABLE market_price_extremes TO app_user;
GRANT USAGE, SELECT ON SEQUENCE market_prices_id_seq TO app_user;
GRANT USAGE, SELECT ON SEQUENCE market_price_extremes_id_seq TO app_user;

-- Function to automatically update price extremes when new prices are inserted
CREATE OR REPLACE FUNCTION update_price_extremes()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO market_price_extremes (
    condition_id,
    token_id,
    outcome,
    lowest_price,
    lowest_price_timestamp,
    highest_price,
    highest_price_timestamp,
    current_price,
    current_price_timestamp,
    first_recorded,
    last_updated
  )
  VALUES (
    NEW.condition_id,
    NEW.token_id,
    NEW.outcome,
    NEW.price,
    NEW.timestamp,
    NEW.price,
    NEW.timestamp,
    NEW.price,
    NEW.timestamp,
    NEW.timestamp,
    NOW()
  )
  ON CONFLICT (condition_id, token_id)
  DO UPDATE SET
    lowest_price = CASE
      WHEN NEW.price < market_price_extremes.lowest_price THEN NEW.price
      ELSE market_price_extremes.lowest_price
    END,
    lowest_price_timestamp = CASE
      WHEN NEW.price < market_price_extremes.lowest_price THEN NEW.timestamp
      ELSE market_price_extremes.lowest_price_timestamp
    END,
    highest_price = CASE
      WHEN NEW.price > market_price_extremes.highest_price THEN NEW.price
      ELSE market_price_extremes.highest_price
    END,
    highest_price_timestamp = CASE
      WHEN NEW.price > market_price_extremes.highest_price THEN NEW.timestamp
      ELSE market_price_extremes.highest_price_timestamp
    END,
    current_price = NEW.price,
    current_price_timestamp = NEW.timestamp,
    last_updated = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-update extremes on new price inserts
DROP TRIGGER IF EXISTS trigger_update_price_extremes ON market_prices;
CREATE TRIGGER trigger_update_price_extremes
  AFTER INSERT ON market_prices
  FOR EACH ROW
  EXECUTE FUNCTION update_price_extremes();

-- Add helpful comments
COMMENT ON TABLE market_prices IS 'Time-series data for Polymarket outcome prices';
COMMENT ON TABLE market_price_extremes IS 'Aggregated price extremes';
COMMENT ON COLUMN market_prices.price IS 'Price in 0-1 range (e.g., 0.65 = 65% probability)';
COMMENT ON COLUMN market_price_extremes.lowest_price IS 'Lowest price ever recorded for this outcome (best buy opportunity)';
COMMENT ON COLUMN market_price_extremes.highest_price IS 'Highest price ever recorded for this outcome (best sell opportunity)';
