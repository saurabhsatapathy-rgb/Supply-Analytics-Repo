with dt as
(select distinct dt dt_con 
from transformer.uoms_food_orders
where dt between '2026-08-28' and '2026-08-28') -- change the date for which we need active campaigns

 select a.dt_con,
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
    
-- and to_date(from_unixtime(start_time)) <= '2026-08-18' 
-- and to_date(from_unixtime(end_time)) > '2026-08-18'
where campaign_status = 'Growth_CAMPAIGN_STATUS_ACTIVE'
-- and consent_status = 'Growth_CAMPAIGN_CONSENT_STATUS_APPROVED'
and smart_discount_enabled = true
and store_ids[0] <> 'test'
group by all
order by  1 desc
