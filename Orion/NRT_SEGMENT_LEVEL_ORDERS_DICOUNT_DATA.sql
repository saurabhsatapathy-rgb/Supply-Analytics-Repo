create or replace temporary view active_rid_list as
with dt as

(select distinct dt dt_con 
from transformer.uoms_food_orders
where dt in ('2026-08-21','2026-08-28') --==PLEASE CHANGE THE DATE HERE=====
) 

 select a.dt_con as as_of_dt,
        campaign_id,
        store_ids as array_store_id, 
        store_id_val as store_id,
        array_size(store_ids) as rid_cnt,
        absolute_rdgmv_budget,
        absolute_sdgmv_budget,
        updated_by,
        from_unixtime(updated_at) as updated_at,
        to_date(from_unixtime(updated_at)) as updated_dt,
        from_unixtime(created_at) as created_at,
        created_dt,
        start_dt,
        end_dt,
        rdgmv_target_value,
        sdgmv_target_value,
        rdgmv_target_LT,
        sdgmv_target_LT,
        rdgmv_target_UT,
        sdgmv_target_UT,
        campaign_status,
        consent_status,
        smart_discount_enabled
 from
 (select a.dt_con,
        id as campaign_id,
        store_ids,
        absolute_rdgmv_budget,
        absolute_sdgmv_budget,
        updated_by,
        updated_at,
        to_date(from_unixtime(created_at)) as created_dt,
        to_date(from_unixtime(start_time)) as start_dt,
        to_date(from_unixtime(end_time)) as end_dt,
        rdgmv_percentage_tolerance_v2.target_value as rdgmv_target_value,
        sdgmv_percentage_tolerance_v2.target_value as sdgmv_target_value,
        rdgmv_percentage_tolerance_v2.lower_tolerance as rdgmv_target_LT,
        sdgmv_percentage_tolerance_v2.lower_tolerance as sdgmv_target_LT,
        rdgmv_percentage_tolerance_v2.upper_tolerance as rdgmv_target_UT,
        sdgmv_percentage_tolerance_v2.upper_tolerance as sdgmv_target_UT,
        campaign_status,
        consent_status,
        from_unixtime(created_at) as created_at,
        smart_discount_enabled,
        to_date(from_unixtime(updated_at)) as updated_dt
    from 
    
    (select a.dt_con, b.*,
     row_number() over (partition by a.dt_con, b.id order by updated_at desc) as rn
    from dt a
    left join  
    (
        select
            *,
            to_date(from_unixtime(updated_at)) as updated_dt
        from prod.streams_delta.growth_campaign_crud_event
    ) b on b.updated_dt <= a.dt_con
    qualify rn = 1) a

 ) a
 LATERAL VIEW OUTER EXPLODE(a.store_ids) s AS store_id_val
where campaign_status = 'Growth_CAMPAIGN_STATUS_ACTIVE'
-- and consent_status = 'Growth_CAMPAIGN_CONSENT_STATUS_APPROVED'
and smart_discount_enabled = true
and store_ids[0] <> 'test'
group by all;

--=====================================================================================================================
WITH rid_list AS 
(select as_of_dt, store_id, campaign_id from active_rid_list),

campaign_run_variant AS (
select run_date,campaign_id, variant, run_ts, row_number() over (partition by run_date, campaign_id order by run_ts desc) as rnk
FROM dev.data_science_dev.orion_rule_engine_experiment_assignments
where run_date in ('2026-08-21','2026-08-28') --==PLEASE CHANGE THE DATE HERE=====
qualify rnk = 1
),

customer_tiers AS (
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
    WHERE dt = '2026-08-01' -- This should be month start date if all dates are from same month
),

offer_lock_meta AS
    (
    SELECT offer_id, orion_lock, is_dnt,
    COALESCE(MAX(CASE WHEN CAST(tag.value AS STRING)='NBH_OFFER' THEN 1 ELSE 0 END),0) AS is_nbh
    FROM (
    SELECT offer_id,
    COALESCE((CASE WHEN LOWER(orion_lock)='true' THEN 1 ELSE 0 END),0) AS orion_lock,
    CASE WHEN LOWER(orion_lock)='false' OR orion_lock IS NULL OR orion_lock=''
              OR ((SIZE(store_ids)>0
                   AND (CASE WHEN city_ids IS NOT NULL THEN SIZE(city_ids) ELSE 0 END)=0
                   AND (CASE WHEN customer_ids IS NOT NULL THEN SIZE(customer_ids) ELSE 0 END)=0
                   AND service_fee_type=0))
         THEN 0 ELSE 1 END AS is_dnt,
    tags,
    ROW_NUMBER() OVER (PARTITION BY offer_id ORDER BY dt DESC,hr DESC,updated_at DESC) AS rn
    FROM prod.streams_delta.offer_crud_event
    WHERE dt>='2026-03-01'
    ) base
    LATERAL VIEW OUTER EXPLODE(base.tags) f AS tag
    WHERE base.rn=1
    GROUP BY offer_id, orion_lock, is_dnt
    ),

post_metrics as (
    select dt,
    store_id,
    customer_id,
    count(distinct order_id) as completed_orders,
    count(distinct case when cdgmv>0 then order_id end) as discounted_orders,
    sum(gmv) as gmv,
    sum(cdgmv) as cdgmv,
    sum(rdgmv) as rdgmv,
    sum(sdgmv) as sdgmv,
    sum(nbh_cdgmv) as nbh_cdgmv,
    sum(nbh_sdgmv) as nbh_sdgmv,
    sum(nbh_rdgmv) as nbh_rdgmv
    from
    (SELECT a.dt,
    a.restaurant_id AS store_id,
    a.order_id,
    b.gmv_total as gmv,
    customer_id,
    SUM(COALESCE(a.store_discount, 0))  AS rdgmv,
    SUM(COALESCE(a.swiggy_discount, 0)) AS sdgmv,
    SUM(COALESCE(a.store_discount, 0))+ SUM(COALESCE(a.swiggy_discount, 0)) as cdgmv,

    SUM(case when coalesce(is_nbh,0)= 1 then  COALESCE(a.store_discount, 0) end )  AS nbh_rdgmv,
    SUM(case when coalesce(is_nbh,0)= 1 then COALESCE(a.swiggy_discount, 0) end ) AS nbh_sdgmv,
    SUM(case when coalesce(is_nbh,0)= 1 then COALESCE(a.store_discount, 0) end)+ SUM(case when coalesce(is_nbh,0)= 1 then COALESCE(a.swiggy_discount, 0) end) as nbh_cdgmv
    FROM prod.analytics_prod.cp_order_offer a
    -- join fact.dp_order_fact b on a.order_id = b.order_id and a.dt = b.dt
join (select dt , order_id, order_restaurant_bill as gmv_total, user_id as customer_id
from transformer.uoms_food_orders 
where dt in ('2026-08-21', '2026-08-28') --===== PLEASE CHANGE THE DATE HERE==============
and (toing_order_flag = 0 or toing_order_flag is null)) b on a.order_id = b.order_id and a.dt = b.dt
left join offer_lock_meta c on coalesce(a.offer_id,0) = c.offer_id

where to_date(a.dt) in('2026-08-21', '2026-08-28') --==== PLEASE CHANGE THE HR AND DATE HERE=========
and a.hr <= 14 --==== PLEASE CHANGE THE HR HERE=========
and a.order_status = 'completed'
and city_code <> '10000'
GROUP BY all)
group by all
)

select
b.dt,
coalesce(c.customer_segment,'Orion_unclassified_1') as customer_segment,
coalesce(vr.variant,'control') as xp_variant,
sum(completed_orders) as completed_orders,
sum(discounted_orders) as discounted_orders,
sum(gmv) as gmv,
sum(cdgmv) as cdgmv,
sum(sdgmv) as sdgmv,
sum(rdgmv) as rdgmv,
sum(nbh_cdgmv) as nbh_cdgmv,
sum(nbh_sdgmv) as nbh_sdgmv,
sum(nbh_rdgmv) as nbh_rdgmv
from rid_list a
join post_metrics b on a.store_id = b.store_id and a.as_of_dt = b.dt
left join customer_tiers c on b.customer_id = c.customer_id
left join campaign_run_variant vr on a.campaign_id = vr.campaign_id and a.as_of_dt = vr.run_date
group by all
