-- Investigation: Why do some records still have NULL outcomes after migration?
-- This script helps identify which records couldn't be matched

-- ============================================================
-- Check 1: Which token_ids have NULL outcomes?
-- ============================================================
SELECT
  'market_price_extremes with NULL outcomes' as description,
  condition_id,
  token_id,
  COUNT(*) as record_count
FROM market_price_extremes
WHERE outcome IS NULL
GROUP BY condition_id, token_id
ORDER BY record_count DESC;

-- ============================================================
-- Check 2: Are these token_ids in the games table?
-- ============================================================
WITH null_tokens AS (
  SELECT DISTINCT
    condition_id,
    token_id
  FROM market_price_extremes
  WHERE outcome IS NULL
),
games_tokens AS (
  SELECT
    m->>'conditionId' as condition_id,
    o->>'tokenID' as token_id,
    o->>'title' as outcome_name,
    g.title as game_title,
    g.closed as game_closed
  FROM games g,
    jsonb_array_elements(g.markets) m,
    jsonb_array_elements(m->'outcomes') o
)
SELECT
  nt.condition_id,
  nt.token_id,
  gt.outcome_name,
  gt.game_title,
  gt.game_closed,
  CASE
    WHEN gt.token_id IS NULL THEN 'NOT IN GAMES TABLE'
    WHEN gt.game_closed THEN 'GAME CLOSED'
    ELSE 'FOUND IN GAMES'
  END as status
FROM null_tokens nt
LEFT JOIN games_tokens gt
  ON nt.condition_id = gt.condition_id
  AND nt.token_id = gt.token_id
ORDER BY status, nt.condition_id;

-- ============================================================
-- Check 3: Sample of NULL records from market_prices
-- ============================================================
SELECT
  'Sample NULL outcomes in market_prices' as description,
  condition_id,
  token_id,
  price,
  timestamp
FROM market_prices
WHERE outcome IS NULL
ORDER BY timestamp DESC
LIMIT 10;
