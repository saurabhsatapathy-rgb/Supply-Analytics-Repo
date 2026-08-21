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




WITH rid_list AS (
    SELECT distinct _c0 as restaurant_id from prod.analytics_adhoc.orion_rid --a
),

customer_tiers AS (
    SELECT
        customer_id,
        dt,
        CASE
            WHEN tier IN ('P1A','P1B','P1C','P1D') THEN 'S1_orion'
            WHEN tier = 'P1_P'                     THEN 'S2_orion'
            WHEN tier = 'P2'                       THEN 'S3_orion'
            WHEN tier = 'P2_P'                     THEN 'S4_orion'
            WHEN tier = 'P3'                       THEN 'S5_orion'
            WHEN tier = 'P3_P'                     THEN 'S6_orion'
            ELSE 'Orion_unclassified_1'
        END AS customer_segment
    FROM prod.analytics_prod.ANALYTICS_PUBLIC_CUSTOMER_TIERS_V2
    WHERE dt = '2026-08-01'
),

carts AS (
select *, 
case when coupon_discount > 0 then 1 else 0 end as coupon_disc_flag,
case when fvo_discount_total > 0 then 1 else 0 end as fvo_disc_flag,
case when cart_value between 0 and 100 then 'a_0_100'
when cart_value between 100 and 200 then 'b_100_200'
when cart_value between 200 and 300 then 'c_200_300'
when cart_value between  300 and 400 then 'd_300_400'
when cart_value between 400 and 500 then 'e_400_500'
when cart_value between 500 and 700 then 'f_500_700'
when cart_value > 700 then '700+' end as cart_total_bucket

from
    (SELECT
        c.dt,
        c.original_cart_id,
        c.cart_state,
        c.customer_id AS customer_id,
        c.restaurant_id AS restaurant_id,
        case when HOUR(time_stamp) between  11 and 15 then 'lunch'
            when HOUR(time_stamp) between  16 and 22 then 'snacks_dinner'
            else 'latenight_breakfast' end as slot,
        sum(ITEM_TOTAL) as cart_value,
        sum(coupon_discount_total) as coupon_discount,
        sum(fp_store_discount) + sum(fp_swiggy_discount) as fvo_discount_total
    FROM prod.analytics_prod.analytics_public_pockethero_cart_fact_v2_filtered_14th_to_19th_v2 c
    WHERE c.dt >= '2026-08-15'
      AND c.dt <=  '2026-08-19'
      AND c.restaurant_id IN (SELECT restaurant_id FROM rid_list)
      group by all
      )
),

-- completed orders in the 90-day lookback window, same RID universe
prior_orders AS (
    SELECT DISTINCT
        customer_id,
        restaurant_id,
        dt AS order_dt
    FROM fact.dp_order_fact
    WHERE dt >= DATEADD(day, -90, DATE '2026-08-15')
      AND dt <=  DATE '2026-08-19'
      AND ignore_order_flag = 0
      AND COALESCE(toing_order_flag, 0) = 0
      AND post_status = 'Completed'
      AND restaurant_id IN (SELECT restaurant_id FROM rid_list)
),

-- one row per cart: did this customer order from THIS rx in the prior 90 days?
cart_rtr AS (
    SELECT
        c.dt,
        c.original_cart_id,
        MAX(CASE WHEN po.customer_id IS NOT NULL THEN 1 ELSE 0 END) AS rtr_flag
    FROM carts c
    LEFT JOIN prior_orders po
        ON  po.customer_id   = c.customer_id
        AND po.restaurant_id = c.restaurant_id
        AND po.order_dt      <  c.dt
        AND po.order_dt      >= DATEADD(day, -90, c.dt)
    GROUP BY 1, 2
)

select 
a.restaurant_id,
b.pack_id, 
split(b.pack_id,'_')[0] as tier, 
split(b.pack_id,'_')[1] as st, 
a.segment,
a.rtr_ntr,
a.slot, 
cart_total_bucket,
count(distinct original_cart_id) as cart_count,
count(distinct case when cart_state = 'PLACE_ORDER' then original_cart_id end) as order_cart,
count(distinct case when coupon_disc_flag = 1 then original_cart_id end) as coupon_disc_cart,
count(distinct case when coupon_disc_flag = 1 and cart_state = 'PLACE_ORDER' then original_cart_id end) as coupon_disc_order_cart,
count(distinct case when fvo_disc_flag = 1 then original_cart_id end) as fvo_disc_cart,
count(distinct case when fvo_disc_flag = 1 and cart_state = 'PLACE_ORDER' then original_cart_id end) as fvo_disc_order_cart,
sum(case when coupon_disc_flag = 1 then coupon_discount end) as coupon_disc_value,
sum(case when coupon_disc_flag = 1 then cart_value end) as coupon_cart_value

from 
(SELECT
a.*,
COALESCE(ct.customer_segment, 'Orion_unclassified_1') AS segment,
CASE WHEN r.rtr_flag = 1 THEN 'RTR' ELSE 'NTR' END AS rtr_ntr
FROM carts a
LEFT JOIN customer_tiers ct ON  a.customer_id = ct.customer_id AND ct.dt = DATE_TRUNC('month', a.dt)
JOIN cart_rtr r
    ON  r.dt = a.dt
    AND r.original_cart_id = a.original_cart_id
GROUP BY ALL) a
join analytics_adhoc.bs_orion_tier_mapping b on a.dt = b.run_date and a.restaurant_id = b.store_id and a.segment = b.segment and a.rtr_ntr = b.store_seg and a.slot = b.slot
group by all;
