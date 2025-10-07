CREATE OR REPLACE FUNCTION get_detail_card_func(
    p_card_id INT
)
RETURNS card
LANGUAGE plpgsql
AS $$
DECLARE
    result_card card;
BEGIN
    SELECT *
    INTO result_card
    FROM card
    WHERE card_id = p_card_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE NOTICE 'İlgili ID ile aktif kart bulunamadı (ID: %)', p_card_id;
        RETURN NULL;
    END IF;

    RETURN result_card;
END;
$$;
