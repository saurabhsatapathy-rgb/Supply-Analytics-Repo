CREATE OR REPLACE TABLE analytics_adhoc.bs_orion_tier_mapping AS
WITH parsed AS (
  SELECT
    campaign_id,
    run_date,
    run_ts,
    prev_burn_state,
    from_json(campaign_context, 'STRUCT<
      burn: STRUCT<
        actual_cdgmv_pct: DOUBLE,
        agreed_cdgmv_pct: DOUBLE,
        cumulative_gmv: DOUBLE,
        cumulative_rdgmv: DOUBLE,
        cumulative_sdgmv: DOUBLE,
        lower_cdgmv_tol: DOUBLE,
        total_burn: DOUBLE,
        upper_cdgmv_tol: DOUBLE
      >,
      stores: ARRAY<STRUCT<
        store_id: STRING,
        pack_selections: ARRAY<STRUCT<
          emit_segment: STRING,
          pack_id: STRING,
          segment: STRING,
          slot: STRING,
          store_seg: STRING
        >>
      >>
    >') AS ctx
  FROM dev.data_science_dev.orion_rule_engine_campaign_state
  WHERE campaign_context IS NOT NULL
    AND run_date >= '2026-07-09'
),
exploded AS (
  SELECT
    campaign_id,
    run_date,
    run_ts,
    prev_burn_state,
    store.store_id,
    ps.pack_id,
    ps.segment,
    ps.store_seg,
    ps.slot,
    ps.emit_segment,
    ctx.burn.actual_cdgmv_pct,
    ctx.burn.agreed_cdgmv_pct,
    ctx.burn.cumulative_gmv,
    ctx.burn.cumulative_rdgmv,
    ctx.burn.cumulative_sdgmv,
    ctx.burn.lower_cdgmv_tol,
    ctx.burn.total_burn,
    ctx.burn.upper_cdgmv_tol
  FROM parsed
  LATERAL VIEW explode(ctx.stores) AS store
  LATERAL VIEW explode(store.pack_selections) AS ps
),
latest AS (
  SELECT *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY campaign_id, run_date, store_id, segment, store_seg, pack_id, slot, emit_segment
        ORDER BY run_ts DESC
      ) AS rn
    FROM exploded
  )
  WHERE rn = 1
)
SELECT
  campaign_id,
  run_date,
  run_ts,
  prev_burn_state,
  store_id,
  pack_id,
  segment,
  store_seg,
  slot,
  emit_segment,
  actual_cdgmv_pct,
  agreed_cdgmv_pct,
  cumulative_gmv,
  cumulative_rdgmv,
  cumulative_sdgmv,
  lower_cdgmv_tol,
  total_burn,
  upper_cdgmv_tol
FROM latest
ORDER BY campaign_id, run_date, store_id, segment, slot;

--=============================================================================================


WITH customer_tiers AS (
    SELECT
        customer_id,
        tier,
        CASE
            WHEN tier IN ('P1A','P1B','P1C','P1D') THEN 'S1_orion'
            WHEN tier = 'P1_P'                     THEN 'S2_orion'
            WHEN tier = 'P2'                       THEN 'S3_orion'
            WHEN tier = 'P2_P'                     THEN 'S4_orion'
            WHEN tier = 'P3'                       THEN 'S5_orion'
            WHEN tier = 'P3_P'                     THEN 'S6_orion'
            ELSE 'Orion_unclassified_1'
        END AS customer_segment,
        CASE
            WHEN tier IN ('P1A','P1B','P1C','P1D','P1_P') THEN 'P1'
            WHEN tier IN ('P2','P2_P')                    THEN 'P2'
            WHEN tier IN ('P3','P3_P')                    THEN 'P3'
            ELSE 'Unclassified'
        END AS p_group
    FROM prod.analytics_prod.ANALYTICS_PUBLIC_CUSTOMER_TIERS_V2
    WHERE dt = '2026-08-01'
)


select a.run_date,
a.store_id, tier, mode, segment, a.variant,
count(distinct  original_cart_id) as cart_count,
count(distinct case when cart_state='PLACE_ORDER' then original_cart_id end) as placed_Cart_count

from
(select
distinct
run_date, store_id, segment, variant,
split(pack_id,'_')[0] as tier,
CASE 
    WHEN split(pack_id, '_')[1] = 'O' THEN '5_O'
    WHEN split(pack_id, '_')[1] = 'A' THEN '4_A'
    WHEN split(pack_id, '_')[1] = 'M' THEN '3_M'
    WHEN split(pack_id, '_')[1] = 'C' THEN '2_C'
    WHEN split(pack_id, '_')[1] = 'P' THEN '1_P'
    ELSE split(pack_id, '_')[1]
END AS mode
from analytics_adhoc.bs_orion_tier_mapping
where run_date between current_Date -7 and current_date - 1
) a
left join
(SELECT dt,
restaurant_id as store_id,
original_cart_id,
b.customer_id,
cart_state,
 COALESCE(ct.customer_segment, 'Orion_unclassified_1') as customer_segment
 from prod.analytics_prod.analytics_public_pockethero_cart_fact_v2_filtered_14th_to_26th_aug b
left join customer_tiers ct on b.customer_id = ct.customer_id) b 
on a.store_id = b.store_id and a.segment = b.customer_segment and a.run_date = b.dt

    group by all
