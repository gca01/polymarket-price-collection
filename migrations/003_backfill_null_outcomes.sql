-- Migration: Backfill NULL outcome values in price tables
--
-- PROBLEM: Some records have NULL in the outcome column
-- SOLUTION: Join with games table to map (condition_id + token_id) -> outcome name
--
-- PREREQUISITE: condition_id must already be fixed (should be hex format like 0x...)
-- BEFORE RUNNING: Review the preview queries below to verify the mapping is correct!

-- ============================================================
-- PREVIEW: Check what will be updated (run this first!)
-- ============================================================
WITH token_outcome_mapping AS (
  SELECT
    m->>'conditionId' as condition_id,
    o->>'tokenID' as token_id,
    o->>'title' as outcome_name,
    g.title as game_title
  FROM games g,
    jsonb_array_elements(g.markets) m,
    jsonb_array_elements(m->'outcomes') o
  WHERE m->>'conditionId' IS NOT NULL
    AND o->>'tokenID' IS NOT NULL
    AND o->>'title' IS NOT NULL
)
SELECT
  mp.condition_id,
  mp.token_id,
  mp.outcome as current_outcome,
  tom.outcome_name as new_outcome,
  tom.game_title,
  COUNT(*) as affected_records
FROM market_prices mp
JOIN token_outcome_mapping tom
  ON mp.condition_id = tom.condition_id
  AND mp.token_id = tom.token_id
WHERE mp.outcome IS NULL
GROUP BY mp.condition_id, mp.token_id, mp.outcome, tom.outcome_name, tom.game_title
ORDER BY affected_records DESC;

-- Preview count
SELECT
  'market_prices' as table_name,
  COUNT(*) as null_outcome_count
FROM market_prices
WHERE outcome IS NULL

UNION ALL

SELECT
  'market_price_extremes' as table_name,
  COUNT(*) as null_outcome_count
FROM market_price_extremes
WHERE outcome IS NULL;

-- ============================================================
-- STEP 1: Update market_prices table
-- ============================================================
WITH token_outcome_mapping AS (
  SELECT
    m->>'conditionId' as condition_id,
    o->>'tokenID' as token_id,
    o->>'title' as outcome_name
  FROM games g,
    jsonb_array_elements(g.markets) m,
    jsonb_array_elements(m->'outcomes') o
  WHERE m->>'conditionId' IS NOT NULL
    AND o->>'tokenID' IS NOT NULL
    AND o->>'title' IS NOT NULL
)
UPDATE market_prices mp
SET outcome = tom.outcome_name
FROM token_outcome_mapping tom
WHERE mp.condition_id = tom.condition_id
  AND mp.token_id = tom.token_id
  AND mp.outcome IS NULL
  AND tom.outcome_name IS NOT NULL;

-- ============================================================
-- STEP 2: Update market_price_extremes table
-- ============================================================
WITH token_outcome_mapping AS (
  SELECT
    m->>'conditionId' as condition_id,
    o->>'tokenID' as token_id,
    o->>'title' as outcome_name
  FROM games g,
    jsonb_array_elements(g.markets) m,
    jsonb_array_elements(m->'outcomes') o
  WHERE m->>'conditionId' IS NOT NULL
    AND o->>'tokenID' IS NOT NULL
    AND o->>'title' IS NOT NULL
)
UPDATE market_price_extremes mpe
SET outcome = tom.outcome_name
FROM token_outcome_mapping tom
WHERE mpe.condition_id = tom.condition_id
  AND mpe.token_id = tom.token_id
  AND mpe.outcome IS NULL
  AND tom.outcome_name IS NOT NULL;

-- ============================================================
-- VERIFICATION: Check results
-- ============================================================
-- Count NULL vs non-NULL outcomes
SELECT
  'market_prices' as table_name,
  CASE WHEN outcome IS NULL THEN 'NULL' ELSE 'Has Value' END as outcome_status,
  COUNT(*) as record_count
FROM market_prices
GROUP BY
  CASE WHEN outcome IS NULL THEN 'NULL' ELSE 'Has Value' END

UNION ALL

SELECT
  'market_price_extremes' as table_name,
  CASE WHEN outcome IS NULL THEN 'NULL' ELSE 'Has Value' END as outcome_status,
  COUNT(*) as record_count
FROM market_price_extremes
GROUP BY
  CASE WHEN outcome IS NULL THEN 'NULL' ELSE 'Has Value' END
ORDER BY table_name, outcome_status;

-- Show sample of updated records
SELECT
  condition_id,
  token_id,
  outcome,
  price,
  timestamp
FROM market_prices
WHERE outcome IS NOT NULL
ORDER BY timestamp DESC
LIMIT 10;

-- If any records still have NULL outcomes, show them for investigation
SELECT
  'Records with NULL outcomes after migration:' as status,
  COUNT(*) as count
FROM market_prices
WHERE outcome IS NULL

UNION ALL

SELECT
  'Records with NULL outcomes after migration:' as status,
  COUNT(*) as count
FROM market_price_extremes
WHERE outcome IS NULL;
