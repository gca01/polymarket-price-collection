-- Alternative Migration: Delete old price records with incorrect condition_id
--
-- This is the SIMPLE option - just deletes all records with non-hex condition_ids
-- Use this if you don't need the historical data and want a clean slate
--
-- CAUTION: This will delete data! Make sure you're okay with losing historical prices.

-- ============================================================
-- PREVIEW: See what will be deleted
-- ============================================================
SELECT
  'market_prices' as table_name,
  COUNT(*) as records_to_delete,
  MIN(timestamp) as oldest_record,
  MAX(timestamp) as newest_record
FROM market_prices
WHERE condition_id NOT LIKE '0x%'

UNION ALL

SELECT
  'market_price_extremes' as table_name,
  COUNT(*) as records_to_delete,
  MIN(first_recorded) as oldest_record,
  MAX(last_updated) as newest_record
FROM market_price_extremes
WHERE condition_id NOT LIKE '0x%';

-- ============================================================
-- STEP 1: Delete from market_price_extremes (has foreign key dependency)
-- ============================================================
DELETE FROM market_price_extremes
WHERE condition_id NOT LIKE '0x%';

-- ============================================================
-- STEP 2: Delete from market_prices
-- ============================================================
DELETE FROM market_prices
WHERE condition_id NOT LIKE '0x%';

-- ============================================================
-- VERIFICATION: Confirm all remaining records have valid hex format
-- ============================================================
SELECT
  CASE
    WHEN condition_id LIKE '0x%' THEN 'Valid (hex format)'
    ELSE 'Invalid (numeric format)'
  END as format_type,
  COUNT(*) as record_count
FROM market_prices
GROUP BY
  CASE
    WHEN condition_id LIKE '0x%' THEN 'Valid (hex format)'
    ELSE 'Invalid (numeric format)'
  END;

-- Should return only "Valid (hex format)" rows
