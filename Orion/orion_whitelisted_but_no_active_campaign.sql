SELECT
    store_id,
    status,
    updated_at,
    updated_by,
    ROW_NUMBER() OVER (
        PARTITION BY store_id
        ORDER BY updated_at DESC
    ) AS rn
FROM prod.streams_delta.orion_store_crud_event
QUALIFY rn = 1
    AND status = true
    AND store_id NOT IN (
select distinct store_id
    from
(select id as campaign_id,
        store_id_val as store_id,
        store_ids,
        absolute_rdgmv_budget,
        absolute_sdgmv_budget,
        updated_by,
        smart_discount_enabled,
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
    
    );
