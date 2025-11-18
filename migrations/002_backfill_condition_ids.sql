-- Migration: Backfill correct conditionId values for existing price records
--
-- PROBLEM: Old records have game.id (e.g., "82104") instead of blockchain conditionId (e.g., "0xb21f...")
-- SOLUTION: Join with games table to map token_id -> market -> conditionId
--
-- BEFORE RUNNING: Review the preview queries below to verify the mapping is correct!

-- ============================================================
-- PREVIEW: Check what will be updated (run this first!)
-- ============================================================
WITH token_to_condition AS (
  SELECT
    g.id as game_id,
    g.title as game_title,
    m->>'conditionId' as condition_id,
    o->>'tokenID' as token_id,
    o->>'outcome' as outcome_name
  FROM games g,
    jsonb_array_elements(g.markets) m,
    jsonb_array_elements(m->'outcomes') o
  WHERE m->>'conditionId' IS NOT NULL
    AND o->>'tokenID' IS NOT NULL
)
SELECT
  mp.condition_id as old_condition_id,
  tc.condition_id as new_condition_id,
  mp.token_id,
  mp.outcome,
  tc.game_title,
  COUNT(*) as affected_records
FROM market_prices mp
JOIN token_to_condition tc ON mp.token_id = tc.token_id
WHERE mp.condition_id NOT LIKE '0x%'  -- Only non-hex values
GROUP BY mp.condition_id, tc.condition_id, mp.token_id, mp.outcome, tc.game_title
ORDER BY affected_records DESC;

-- ============================================================
-- STEP 1: Update market_prices table
-- ============================================================
WITH token_to_condition AS (
  SELECT
    m->>'conditionId' as condition_id,
    o->>'tokenID' as token_id
  FROM games g,
    jsonb_array_elements(g.markets) m,
    jsonb_array_elements(m->'outcomes') o
  WHERE m->>'conditionId' IS NOT NULL
    AND o->>'tokenID' IS NOT NULL
)
UPDATE market_prices mp
SET condition_id = tc.condition_id
FROM token_to_condition tc
WHERE mp.token_id = tc.token_id
  AND mp.condition_id NOT LIKE '0x%'  -- Only update non-hex values
  AND tc.condition_id IS NOT NULL;

-- ============================================================
-- STEP 2: Update market_price_extremes table
-- ============================================================
WITH token_to_condition AS (
  SELECT
    m->>'conditionId' as condition_id,
    o->>'tokenID' as token_id
  FROM games g,
    jsonb_array_elements(g.markets) m,
    jsonb_array_elements(m->'outcomes') o
  WHERE m->>'conditionId' IS NOT NULL
    AND o->>'tokenID' IS NOT NULL
)
UPDATE market_price_extremes mpe
SET condition_id = tc.condition_id
FROM token_to_condition tc
WHERE mpe.token_id = tc.token_id
  AND mpe.condition_id NOT LIKE '0x%'  -- Only update non-hex values
  AND tc.condition_id IS NOT NULL;

-- ============================================================
-- VERIFICATION: Check results
-- ============================================================
-- Count records by condition_id format
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

-- Show sample of updated records
SELECT
  condition_id,
  token_id,
  outcome,
  price,
  timestamp
FROM market_prices
WHERE condition_id LIKE '0x%'
ORDER BY timestamp DESC
LIMIT 10;
