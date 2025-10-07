CREATE OR REPLACE PROCEDURE delete_card_type_proc(
    p_card_type_id INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM card_type WHERE card_type_id = p_card_type_id) THEN
        RAISE NOTICE 'Böyle bir kart tipi yok. ID: %', p_card_type_id;
    ELSE
        DELETE FROM card_type
        WHERE card_type_id = p_card_type_id;

        RAISE NOTICE 'Kart tipi silindi. ID: %', p_card_type_id;
    END IF;
END;
$$;
