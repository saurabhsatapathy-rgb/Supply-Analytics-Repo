-- new one fixed 
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
    AND run_date >= '2026-08-01'
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


WITH customer_tiers AS (
     SELECT
        a.customer_id,
        dt,
        CASE
            when b.customer_id is not null then 'S7_orion'
            WHEN tier IN ('P1A','P1B','P1C','P1D') THEN 'S1_orion'
            WHEN tier = 'P1_P'                     THEN 'S2_orion'
            WHEN tier = 'P2'                       THEN 'S3_orion'
            WHEN tier = 'P2_P'                     THEN 'S4_orion'
            WHEN tier = 'P3'                       THEN 'S5_orion'
            WHEN tier = 'P3_P'                     THEN 'S6_orion'
            ELSE 'Orion_unclassified_1'
        END AS customer_segment
    FROM prod.analytics_prod.ANALYTICS_PUBLIC_CUSTOMER_TIERS_V2 a
    left join (SELECT
    distinct customer_id
FROM dev.data_science_prod.orion_customer_pstar_segment_test
WHERE segment IN ('S7_orion') AND dt = (SELECT MAX(dt)
FROM dev.data_science_prod.orion_customer_pstar_segment_test)
) b on a.CUSTOMER_ID = b.customer_id
    WHERE dt = '2026-08-01'
)






select run_date,
a.store_id, tier, mode, segment,
sum(cdgmv) as cdgmv,
sum(rdgmv) rdgmv,
sum(sdgmv) as sdgmv,
sum(gmv) as gmv,
sum(completed_orders) as completed_orders,
sum(discounted_orders) as discounted_orders
from
(select
distinct
run_date, store_id, segment, 
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
where run_date between '2026-08-07' and '2026-08-11'
) a
left join
(select dt, 
    store_id, 
    COALESCE(customer_segment, 'Orion_unclassified_1') AS customer_segment,
    count(distinct order_id) as completed_orders,
    count(distinct case when cdgmv>0 then order_id end) as discounted_orders,
    sum(gmv) as gmv,
    sum(cdgmv) as cdgmv,
    sum(rdgmv) as rdgmv,
    sum(sdgmv) as sdgmv
    from
    (SELECT a.dt,
    a.restaurant_id AS store_id,
    a.order_id,
    b.gmv_total as gmv,
    COALESCE(ct.customer_segment, 'Orion_unclassified_1') AS customer_segment,
    -- sum(coalesce(a.total_offer_discount,0)) as cdgmv,
    SUM(COALESCE(a.store_discount, 0))  AS rdgmv,
    SUM(COALESCE(a.swiggy_discount, 0)) AS sdgmv,
    SUM(COALESCE(a.store_discount, 0))+ SUM(COALESCE(a.swiggy_discount, 0)) as cdgmv
    FROM prod.analytics_prod.cp_order_offer a
    join fact.dp_order_fact b on a.order_id = b.order_id and a.dt = b.dt
     left join customer_tiers ct on b.customer_id = ct.customer_id
    where to_date(a.dt) >= to_date('2026-08-07')
    and to_date(a.dt) <= to_date('2026-08-11')
    and a.order_status = 'completed'
    and (b.toing_order_flag = '0' or b.toing_order_flag is null)
    and b.ignore_order_flag = 0
    and city_code <> '10000'
    GROUP BY all) group by all) b on a.store_id = b.store_id and a.segment = b.customer_segment and a.run_date = b.dt

    group by all
    HAVING  sum(gmv) >0;
 

