CREATE OR REPLACE PROCEDURE update_card_type_proc(
    p_card_type_id INT,
    p_type_name VARCHAR,
    p_description VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    p_exists INT;
BEGIN
    SELECT 1 INTO p_exists
    FROM card_type
    WHERE card_type_id = p_card_type_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Böyle bir kart tipi yok. ID: %', p_card_type_id;
    ELSE
        UPDATE card_type
        SET type_name = p_type_name,
            description = p_description
        WHERE card_type_id = p_card_type_id;

        RAISE NOTICE 'Kart tipi güncellendi. ID: %', p_card_type_id;
    END IF;
END;
$$;

