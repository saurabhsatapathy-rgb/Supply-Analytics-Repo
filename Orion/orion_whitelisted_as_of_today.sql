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
        SELECT DISTINCT
            store_ids[0] AS store_id
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY id
                    ORDER BY dt DESC, hr DESC, updated_at DESC
                ) AS rn
            FROM prod.streams_delta.growth_campaign_crud_event
        ) x
        WHERE rn = 1
            AND FROM_UNIXTIME(start_time) <= current_timestamp
            AND FROM_UNIXTIME(end_time) >= current_timestamp
            AND campaign_status = 'Growth_CAMPAIGN_STATUS_ACTIVE'
            -- AND consent_status = 'Growth_CAMPAIGN_CONSENT_STATUS_APPROVED'
            AND smart_discount_enabled = true
    );
