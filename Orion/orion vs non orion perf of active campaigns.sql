WITH rid_list AS (
select distinct store_id
    from
(select id as campaign_id,
        store_id_val as store_id,
        store_ids,
        absolute_rdgmv_budget,
        absolute_sdgmv_budget,
        smart_discount_enabled,
        updated_by,
        from_unixtime(updated_at) as updated_at,
        to_date(from_unixtime(updated_at)) as updated_at_dt,
        to_date(from_unixtime(created_at)) as created_on,
        to_date(from_unixtime(start_time)) as start_dt,
        to_date(from_unixtime(end_time)) as end_dt,
        rdgmv_percentage_tolerance_v2.target_value as rdgmv_target_value,
        sdgmv_percentage_tolerance_v2.target_value as sdgmv_target_value,
        rdgmv_percentage_tolerance_v2.lower_tolerance as rdgmv_target_LT,
        sdgmv_percentage_tolerance_v2.lower_tolerance as sdgmv_target_LT,
        rdgmv_percentage_tolerance_v2.upper_tolerance as rdgmv_target_UT,
        sdgmv_percentage_tolerance_v2.upper_tolerance as sdgmv_target_UT,
        nbh_sdgmv_percentage_tolerance.target_value as nbh_sdgmv_target_value,
        nbh_sdgmv_percentage_tolerance.lower_tolerance as nbh_sdgmv_target_LT,
        nbh_sdgmv_percentage_tolerance.upper_tolerance as nbh_sdgmv_target_UT
    from (
        select
            *,
            row_number() over (
                partition by id
                order by dt desc, hr desc, updated_at desc
            ) as rn
        from prod.streams_delta.growth_campaign_crud_event
        qualify rn = 1
    ) x
    LATERAL VIEW OUTER EXPLODE(x.store_ids) s AS store_id_val
    where FROM_UNIXTIME(start_time) <= current_timestamp
            AND FROM_UNIXTIME(end_time) >= current_timestamp
    and campaign_status = 'Growth_CAMPAIGN_STATUS_ACTIVE'
    and smart_discount_enabled = true
)
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
    WHERE dt = '2026-08-01'
),

latest_offer AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY offer_id
            ORDER BY
                _server_time_stamp DESC,
                updated_at DESC,
                dt DESC,
                CAST(hr AS INT) DESC
        ) AS rn
    FROM prod.streams_delta.offer_crud_event
    WHERE dt BETWEEN DATE_SUB('2026-08-22', 90) AND '2026-08-22'
),

offer_orion_flag AS (
    SELECT
        offer_id,
        CASE
            WHEN CAST(ingestion_source AS STRING) = '21'
                THEN 'Orion'
            ELSE 'Non-Orion'
        END AS orion_flag
    FROM latest_offer
    WHERE rn = 1
),

post_metrics as (
    select dt,
    store_id,
    customer_id,
    discount_type,
    orion_flag,
    count(distinct order_id) as completed_orders,
    count(distinct case when cdgmv>0 then order_id end) as discounted_orders,
    sum(cdgmv) as cdgmv,
    sum(rdgmv) as rdgmv,
    sum(sdgmv) as sdgmv
    from
    (SELECT a.dt,
    a.restaurant_id AS store_id,
    a.order_id,
    customer_id,
    coalesce(f.orion_flag, 'Non-Orion') as orion_flag,
case when offer_type = 'coupon_offer' and discount_type = 'FLAT_CASHBACK' then 'Cashback'
when offer_type = 'coupon_offer' and discount_type = 'BXGY' then 'BXGY'
when offer_type = 'coupon_offer' and discount_type = 'PERCENTAGE' then 'Percentage off'
when offer_type = 'coupon_offer' and discount_type = 'FLAT' then 'Flat Off'
when offer_type = 'trade_offer' and benefit_type in ('CASHBACK') then 'Cashback'
when offer_type = 'trade_offer' and applied in ('APPLIES_ON_EXPRESS_FEE') then 'Ex_Fee'
when offer_type = 'trade_offer' and applied in ('APPLIES_ON_DELIVERY_FEE') then 'Del_Fee'
when offer_type = 'trade_offer' and applied in ('APPLIES_ON_WEATHER_RAIN_FEE') then 'Wea_Fee'
when offer_type = 'trade_offer' and applied in ('APPLIES_ON_CATALOG_ITEM') and discount_type = 'FREEBIE' then 'FREEBIE'
when offer_type = 'trade_offer' and applied in ('APPLIES_ON_CATALOG_ITEM') and discount_type = 'FINAL_PRICE' then 'FVO'
 when offer_type = 'trade_offer' and applied in ('APPLIES_ON_PACKAGING_FEE') and discount_type = 'PERCENTAGE' then 'Packaging Fees'
 when offer_type = 'trade_offer' and applied in ('APPLIES_ON_CATALOG_ITEM','APPLIES_ON_CART_BILL') and discount_type in ('PERCENTAGE') then 'Percentage off TD'
 when offer_type = 'trade_offer' and applied in ('APPLIES_ON_CATALOG_ITEM','APPLIES_ON_CART_BILL') and discount_type in ('FLAT') then 'Flat TD'
  when offer_type = 'trade_offer' and applied in ('APPLIES_ON_CATALOG_ITEM') and discount_type in ('ANCHOR_PRICE') then 'Toing'
    when offer_type = 'trade_offer' and applied in ('APPLIES_ON_CATALOG_ITEM') and benefit_type in ('BANK_OFFER') then 'Bank Offer'
 else 'other' end as discount_type,
    SUM(COALESCE(a.store_discount, 0))  AS rdgmv,
    SUM(COALESCE(a.swiggy_discount, 0)) AS sdgmv,
    SUM(COALESCE(a.store_discount, 0))+ SUM(COALESCE(a.swiggy_discount, 0)) as cdgmv
    FROM prod.analytics_prod.cp_order_offer a
    join fact.dp_order_fact b on a.order_id = b.order_id and a.dt = b.dt
    left join offer_orion_flag f on a.offer_id = f.offer_id
    where to_date(a.dt) between '2026-08-21' and '2026-08-22'
    and a.order_status = 'completed'
    and (b.toing_order_flag = '0' or b.toing_order_flag is null)
    and b.ignore_order_flag = 0
    and city_code <> '10000'
    GROUP BY all)
    group by all
)

select
b.dt,
coalesce(c.customer_segment,'Orion_unclassified_1') as customer_segment,
b.orion_flag,
discount_type,
sum(completed_orders) as completed_orders,
sum(discounted_orders) as discounted_orders,
sum(cdgmv) as cdgmv,
sum(sdgmv) as sdgmv,
sum(rdgmv) as rdgmv
from rid_list a
join post_metrics b on a.store_id = b.store_id
left join customer_tiers c on b.customer_id = c.customer_id
group by all
