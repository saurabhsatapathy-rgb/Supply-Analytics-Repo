 select
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
        smart_discount_enabled
    from (
        select
            *,
            row_number() over (
                partition by id
                order by dt desc, hr desc, updated_at desc
            ) as rn
        from prod.streams_delta.growth_campaign_crud_event
    ) x
    where rn = 1
       AND FROM_UNIXTIME(start_time) <= current_timestamp
            AND FROM_UNIXTIME(end_time) >= current_timestamp
    and campaign_status = 'Growth_CAMPAIGN_STATUS_ACTIVE'
    -- and consent_status = 'Growth_CAMPAIGN_CONSENT_STATUS_APPROVED'
    and smart_discount_enabled = true



    --Growth_CAMPAIGN_CONSENT_STATUS_APPROVED
