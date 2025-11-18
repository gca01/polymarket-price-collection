# Migration Guide: Fixing condition_id Format

## Background

Previously, the price collector was storing the internal game ID (e.g., `"82104"`) in the `condition_id` field instead of the blockchain conditionId (e.g., `"0xb21f2a16078a8fa010cf7d7ff57782166c61f2069f3c98b6392eb6ab180a4bd4"`).

This has been fixed in the code, but existing records in the database still have the wrong format.

## You Have Two Options

### Option 1: Backfill (Preserve Historical Data) ✅ Recommended if you need history

**Use this if:** You have valuable historical price data and want to keep it

**Steps:**

1. **Preview the changes first:**
   ```bash
   psql $DATABASE_URL -f migrations/002_backfill_condition_ids.sql --single-transaction
   ```
   Review the preview query output to verify the mapping looks correct

2. **Run the full migration:**
   ```bash
   psql $DATABASE_URL -f migrations/002_backfill_condition_ids.sql
   ```

**What it does:**
- Maps each `token_id` to its correct `conditionId` by joining with the games table
- Updates both `market_prices` and `market_price_extremes` tables
- Only touches records with non-hex condition_ids (leaves correct ones alone)
- Preserves all your historical price data

**Verification:**
```sql
-- Check that all records now have hex format
SELECT
  CASE WHEN condition_id LIKE '0x%' THEN 'Valid' ELSE 'Invalid' END as status,
  COUNT(*) as count
FROM market_prices
GROUP BY 1;
```

---

### Option 2: Delete Old Data (Clean Slate) 🧹 Recommended if data is recent

**Use this if:**
- You've only been collecting data for a short time (< 1 week)
- The historical data isn't critical
- You want a simple, clean approach

**Steps:**

1. **Preview what will be deleted:**
   ```bash
   psql $DATABASE_URL -c "
   SELECT COUNT(*) as records_to_delete, MIN(timestamp) as oldest, MAX(timestamp) as newest
   FROM market_prices WHERE condition_id NOT LIKE '0x%';
   "
   ```

2. **Delete the old records:**
   ```bash
   psql $DATABASE_URL -f migrations/002_delete_old_prices_ALTERNATIVE.sql
   ```

**What it does:**
- Deletes all price records with non-hex condition_ids
- Simple and fast
- No risk of mapping errors

---

## Comparison Table

| Factor | Backfill | Delete |
|--------|----------|--------|
| **Complexity** | Moderate | Very Simple |
| **Risk** | Low (verify preview first) | None (fresh start) |
| **Historical Data** | Preserved | Lost |
| **Time to Run** | ~10-30 seconds | ~1 second |
| **Best For** | Production systems with valuable data | Development or new systems |

---

## After Migration

Both options result in:
- ✅ All future price collections use correct conditionId format
- ✅ Frontend queries work correctly with `conditionId`
- ✅ No invalid data in the database

---

## Recommendation

**If you started collecting prices recently (last few days):**
→ Use **Option 2 (Delete)** - it's simpler and you're not losing much data

**If you have weeks/months of historical data:**
→ Use **Option 1 (Backfill)** - preserve your valuable historical trends

---

## Questions?

- **How do I know which option to use?**
  Check your oldest price record: `SELECT MIN(timestamp) FROM market_prices;`
  If it's less than a week old, delete is fine.

- **Can I test the backfill first?**
  Yes! Run the preview query from `002_backfill_condition_ids.sql` to see what would change.

- **What if some records can't be mapped?**
  The backfill script only updates records where it can find a matching token_id in the games table. Records that can't be mapped are left unchanged (you can delete them manually later).

- **Is this safe to run on production?**
  Yes, but always:
  1. Test on a backup first if possible
  2. Run during low-traffic times
  3. Review the preview queries before executing
