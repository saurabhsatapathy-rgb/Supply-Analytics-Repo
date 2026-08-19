with dt as
(select distinct dt dt_con 
from fact.dp_order_fact
where dt between '2026-08-17' and '2026-08-17') -- change the date for which we need active campaigns

 select a.*
 from
 (select a.dt_con,
        id as campaign_id,
        store_ids[0] as store_id,
        absolute_rdgmv_budget,
        absolute_sdgmv_budget,
        updated_by,
        to_date(from_unixtime(created_at)) as created_on,
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
    ) b on b.updated_dt <= a.dt_con) a
where rn = 1
 ) a
    
-- and to_date(from_unixtime(start_time)) <= '2026-08-18' 
-- and to_date(from_unixtime(end_time)) > '2026-08-18'
where campaign_status = 'Growth_CAMPAIGN_STATUS_ACTIVE'
-- and consent_status = 'Growth_CAMPAIGN_CONSENT_STATUS_APPROVED'
and smart_discount_enabled = true
group by all
order by  1 desc

