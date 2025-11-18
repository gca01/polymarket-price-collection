-- Migration: Fix remaining non-hex condition_ids in market_price_extremes
--
-- PROBLEM: 86 records still have non-hex condition_ids that couldn't be matched
-- CAUSE: These token_ids no longer exist in the games table (closed/removed games)
--
-- SOLUTION: Try to get correct condition_id from market_prices table,
--           or delete if completely orphaned

-- ============================================================
-- INVESTIGATION: Check if these records exist in market_prices
-- ============================================================
WITH orphaned_extremes AS (
  SELECT
    condition_id as old_condition_id,
    token_id,
    outcome
  FROM market_price_extremes
  WHERE condition_id NOT LIKE '0x%'
),
matching_prices AS (
  SELECT DISTINCT
    mp.condition_id as correct_condition_id,
    mp.token_id,
    mp.outcome
  FROM market_prices mp
  WHERE mp.condition_id LIKE '0x%'  -- Only look at correct hex format
    AND mp.token_id IN (SELECT token_id FROM orphaned_extremes)
)
SELECT
  oe.old_condition_id,
  oe.token_id,
  oe.outcome as extreme_outcome,
  mp.correct_condition_id,
  mp.outcome as price_outcome,
  CASE
    WHEN mp.correct_condition_id IS NOT NULL THEN 'Can fix from market_prices'
    ELSE 'Orphaned - should delete'
  END as status
FROM orphaned_extremes oe
LEFT JOIN matching_prices mp ON oe.token_id = mp.token_id
ORDER BY status, oe.token_id;

-- Count by status
WITH orphaned_extremes AS (
  SELECT
    condition_id as old_condition_id,
    token_id,
    outcome
  FROM market_price_extremes
  WHERE condition_id NOT LIKE '0x%'
),
matching_prices AS (
  SELECT DISTINCT
    mp.condition_id as correct_condition_id,
    mp.token_id
  FROM market_prices mp
  WHERE mp.condition_id LIKE '0x%'
    AND mp.token_id IN (SELECT token_id FROM orphaned_extremes)
)
SELECT
  CASE
    WHEN mp.correct_condition_id IS NOT NULL THEN 'Can fix from market_prices'
    ELSE 'Orphaned - should delete'
  END as status,
  COUNT(*) as count
FROM orphaned_extremes oe
LEFT JOIN matching_prices mp ON oe.token_id = mp.token_id
GROUP BY
  CASE
    WHEN mp.correct_condition_id IS NOT NULL THEN 'Can fix from market_prices'
    ELSE 'Orphaned - should delete'
  END;

-- ============================================================
-- FIX STEP 1: Update from market_prices where possible
-- ============================================================
WITH correct_mappings AS (
  SELECT DISTINCT
    mp.condition_id as correct_condition_id,
    mp.token_id,
    mp.outcome
  FROM market_prices mp
  WHERE mp.condition_id LIKE '0x%'
    AND mp.token_id IN (
      SELECT token_id FROM market_price_extremes WHERE condition_id NOT LIKE '0x%'
    )
)
UPDATE market_price_extremes mpe
SET
  condition_id = cm.correct_condition_id,
  outcome = COALESCE(mpe.outcome, cm.outcome)  -- Also fix NULL outcomes if needed
FROM correct_mappings cm
WHERE mpe.token_id = cm.token_id
  AND mpe.condition_id NOT LIKE '0x%'
  -- Avoid duplicates: only update if hex version doesn't already exist
  AND NOT EXISTS (
    SELECT 1 FROM market_price_extremes existing
    WHERE existing.condition_id = cm.correct_condition_id
      AND existing.token_id = cm.token_id
      AND existing.condition_id LIKE '0x%'
  );

-- ============================================================
-- FIX STEP 2: Delete truly orphaned records
-- ============================================================
-- Delete records that couldn't be fixed (no matching data anywhere)
DELETE FROM market_price_extremes
WHERE condition_id NOT LIKE '0x%'
  AND token_id NOT IN (
    SELECT DISTINCT token_id
    FROM market_prices
    WHERE condition_id LIKE '0x%'
  );

-- ============================================================
-- VERIFICATION: Check remaining non-hex records
-- ============================================================
SELECT
  'Remaining non-hex condition_ids' as status,
  COUNT(*) as count
FROM market_price_extremes
WHERE condition_id NOT LIKE '0x%';

-- Should be 0 if successful
