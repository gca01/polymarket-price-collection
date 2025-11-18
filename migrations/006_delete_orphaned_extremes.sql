-- Migration: Delete orphaned non-hex condition_ids from market_price_extremes
--
-- PROBLEM: 86 records still have non-hex condition_ids
-- CAUSE: Correct hex versions already exist for these token_ids
-- SOLUTION: Simply delete the old non-hex records

-- ============================================================
-- VERIFICATION: Confirm correct versions exist
-- ============================================================
WITH orphaned_extremes AS (
  SELECT
    condition_id as old_condition_id,
    token_id
  FROM market_price_extremes
  WHERE condition_id NOT LIKE '0x%'
),
has_correct_version AS (
  SELECT
    oe.old_condition_id,
    oe.token_id,
    mp.condition_id as correct_condition_id,
    CASE
      WHEN mp.condition_id IS NOT NULL THEN 'Has correct version in market_prices'
      ELSE 'Orphaned'
    END as status
  FROM orphaned_extremes oe
  LEFT JOIN (
    SELECT DISTINCT condition_id, token_id
    FROM market_prices
    WHERE condition_id LIKE '0x%'
  ) mp ON oe.token_id = mp.token_id
)
SELECT
  status,
  COUNT(*) as count
FROM has_correct_version
GROUP BY status;

-- Show sample of records that will be deleted
SELECT
  'Records to be deleted' as description,
  condition_id,
  token_id,
  outcome,
  lowest_price,
  highest_price
FROM market_price_extremes
WHERE condition_id NOT LIKE '0x%'
LIMIT 10;

-- ============================================================
-- DELETE: Remove old non-hex records
-- ============================================================
-- These are safe to delete because:
-- 1. They're old/incorrect format
-- 2. The correct hex versions already exist (or data is in market_prices)
-- 3. market_price_extremes can be regenerated from market_prices if needed

DELETE FROM market_price_extremes
WHERE condition_id NOT LIKE '0x%';

-- ============================================================
-- VERIFICATION: Confirm all cleaned up
-- ============================================================
SELECT
  'Remaining non-hex condition_ids' as status,
  COUNT(*) as count
FROM market_price_extremes
WHERE condition_id NOT LIKE '0x%';

-- Should be 0

SELECT
  'Total records in market_price_extremes' as status,
  COUNT(*) as count
FROM market_price_extremes;
